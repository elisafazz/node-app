import Foundation

@MainActor
@Observable
final class StoryService {
    static let shared = StoryService()

    private(set) var activeByNodeId: [UUID: [Story]] = [:]
    private(set) var archiveByNodeIdYear: [String: [Story]] = [:]
    /// All active stories visible to the current user across every node they belong to.
    private(set) var allVisible: [Story] = []
    private(set) var lastError: String?

    private func archiveKey(nodeId: UUID, year: Int) -> String { "\(nodeId.uuidString)-\(year)" }

    /// Active stories for a single node, resolved via story_visibility (supports cross-node posts).
    /// Clock skew: subtract 5 minutes from "now" to tolerate devices with fast clocks showing
    /// stories that the server hasn't expired yet. Stories near expiry may show briefly after
    /// actual expiry, but that's less disruptive than premature disappearance.
    func fetchActive(nodeId: UUID) async {
        do {
            let threshold = Date().addingTimeInterval(-300)
            let stories: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select("*, story_visibility!inner(node_id)")
                .eq("story_visibility.node_id", value: nodeId.uuidString)
                .gt("expires_at", value: ISO8601DateFormatter().string(from: threshold))
                .order("created_at", ascending: false)
                .execute()
                .value
            self.activeByNodeId[nodeId] = stories
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// All active stories visible to the viewer across all their nodes (RLS enforces membership).
    /// Limited to 200 rows to keep Hub feed snappy. Deduped by id so cross-node posts appear once.
    /// Blocked authors are filtered client-side after fetch (200-row cap makes this negligible).
    /// No story_visibility join here -- the join produces one row per visibility entry (a story shared
    /// to N nodes = N rows), which exhausts the 200-row limit far faster than N unique stories would.
    /// RLS policy stories_visible_to_viewer already enforces membership via story_visibility.
    func fetchAllVisible() async {
        do {
            let raw: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select()
                .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            let blocked = BlockService.shared.blockedUserIds
            var seen = Set<UUID>()
            self.allVisible = raw.filter {
                !blocked.contains($0.authorUserId) && seen.insert($0.id).inserted
            }
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Stories for the permanent year archive of a node, resolved via story_visibility.
    func fetchArchive(nodeId: UUID, year: Int) async {
        do {
            // UTC calendar so year boundaries match the server-side created_at timestamps.
            // Device-local calendar would shift Jan 1 by the UTC offset (e.g. LA = Jan 1 08:00 UTC),
            // causing stories posted in the first hours of a new year to appear in the wrong bucket.
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let yearStart = ISO8601DateFormatter().string(from: cal.date(from: DateComponents(year: year, month: 1, day: 1))!)
            let yearEnd = ISO8601DateFormatter().string(from: cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!)
            let stories: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select("*, story_visibility!inner(node_id)")
                .eq("story_visibility.node_id", value: nodeId.uuidString)
                .gte("created_at", value: yearStart)
                .lt("created_at", value: yearEnd)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.archiveByNodeIdYear[archiveKey(nodeId: nodeId, year: year)] = stories
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Creates a story shared to one or more nodes via the create_story_with_visibility RPC.
    /// The RPC validates membership in every requested node, then inserts atomically.
    func createStory(
        nodeIds: [UUID],
        cloudinaryPublicId: String,
        caption: String?,
        originNodeId: UUID? = nil
    ) async throws -> Story {
        guard let userId = AuthService.shared.session?.user.id else {
            throw StoryError.notAuthenticated
        }
        struct RPCParams: Encodable {
            let p_cloudinary_public_id: String
            let p_caption: String?
            let p_node_ids: [UUID]
            let p_origin_node_id: UUID?
            let p_active_window_seconds: Int
        }
        struct RPCResult: Decodable {
            let story_id: UUID
            let expires_at: Date
        }
        let params = RPCParams(
            p_cloudinary_public_id: cloudinaryPublicId,
            p_caption: caption,
            p_node_ids: nodeIds,
            p_origin_node_id: originNodeId,
            p_active_window_seconds: Int(Constants.Story.activeWindowSeconds)
        )
        let result: RPCResult = try await SupabaseService.shared.database
            .rpc("create_story_with_visibility", params: params)
            .single()
            .execute()
            .value
        let story = Story(
            id: result.story_id,
            originNodeId: originNodeId,
            authorUserId: userId,
            cloudinaryPublicId: cloudinaryPublicId,
            caption: caption,
            createdAt: Date(),
            expiresAt: result.expires_at
        )
        for nodeId in nodeIds { await fetchActive(nodeId: nodeId) }
        await fetchAllVisible()
        await PushService.shared.fanOutStoryNotification(nodeIds: nodeIds, authorUserId: userId, caption: caption)
        return story
    }

    func deleteStory(_ storyId: UUID, nodeId: UUID) async throws {
        try await SupabaseService.shared.database
            .from("stories")
            .delete()
            .eq("id", value: storyId.uuidString)
            .execute()
        await fetchActive(nodeId: nodeId)
        await fetchAllVisible()
    }

    /// Removes a story's visibility from a single node without deleting the story globally.
    /// Server-side delete_story_visibility RPC enforces that the caller is the node owner.
    func removeFromNode(storyId: UUID, nodeId: UUID) async throws {
        struct RPCParams: Encodable {
            let p_story_id: UUID
            let p_node_id: UUID
        }
        try await SupabaseService.shared.database
            .rpc("delete_story_visibility", params: RPCParams(p_story_id: storyId, p_node_id: nodeId))
            .execute()
        await fetchActive(nodeId: nodeId)
    }

    func clearCache() {
        activeByNodeId = [:]
        archiveByNodeIdYear = [:]
        allVisible = []
        lastError = nil
    }
}

enum StoryError: Error, LocalizedError {
    case notAuthenticated
    var errorDescription: String? { "You must be signed in to post a story." }
}
