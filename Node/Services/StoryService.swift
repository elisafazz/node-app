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
    func fetchActive(nodeId: UUID) async {
        do {
            let stories: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select("*, story_visibility!inner(node_id)")
                .eq("story_visibility.node_id", value: nodeId.uuidString)
                .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
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
    func fetchAllVisible() async {
        do {
            let stories: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select("*, story_visibility!inner(node_id)")
                .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
                .order("created_at", ascending: false)
                .execute()
                .value
            self.allVisible = stories
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Stories for the permanent year archive of a node, resolved via story_visibility.
    func fetchArchive(nodeId: UUID, year: Int) async {
        do {
            let cal = Calendar(identifier: .gregorian)
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
}

enum StoryError: Error, LocalizedError {
    case notAuthenticated
    var errorDescription: String? { "You must be signed in to post a story." }
}
