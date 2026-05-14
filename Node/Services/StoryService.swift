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

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

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
                .gt("expires_at", value: Self.iso8601.string(from: threshold))
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
                .gt("expires_at", value: Self.iso8601.string(from: Date()))
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
            let yearStart = Self.iso8601.string(from: cal.date(from: DateComponents(year: year, month: 1, day: 1))!)
            let yearEnd = Self.iso8601.string(from: cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!)
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
        location: String? = nil,
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
        // If the RPC call fails after a successful Cloudinary upload, the image is orphaned.
        // Apple-compliant deletion from the client requires the Cloudinary Admin API (secret)
        // which must not live in the bundle. The delete-user-data Edge Function handles bulk
        // cleanup on account deletion; single-photo orphan cleanup is a Phase B follow-up.
        // Log the public_id so it's detectable in Supabase logs.
        let result: RPCResult
        do {
            result = try await SupabaseService.shared.database
                .rpc("create_story_with_visibility", params: params)
                .single()
                .execute()
                .value
        } catch {
            Log.shared.error("create_story_rpc_failed orphan=\(cloudinaryPublicId)", error: error)
            throw error
        }
        // Location is patched in via a follow-up UPDATE rather than threaded into
        // the create_story_with_visibility RPC -- avoids changing the RPC signature
        // (which would need a new migration + service_role grant rebuild) and keeps
        // the RPC focused on the multi-node visibility insert. RLS lets the author
        // update their own row.
        //
        // Critically, the patch failure must NOT throw. The story has already been
        // committed by the RPC; if we threw here, the caller's catch would surface
        // an error and a retry would skip the upload (cached publicID) but call the
        // RPC again, creating a duplicate story for the same image. Location is a
        // non-critical optional field -- log and continue is the safe path.
        if let location, !location.isEmpty {
            struct LocationPatch: Encodable { let location: String }
            do {
                try await SupabaseService.shared.database
                    .from("stories")
                    .update(LocationPatch(location: location))
                    .eq("id", value: result.story_id.uuidString)
                    .execute()
            } catch {
                Log.shared.error("create_story_location_patch_failed story_id=\(result.story_id)", error: error)
            }
        }
        let story = Story(
            id: result.story_id,
            originNodeId: originNodeId,
            authorUserId: userId,
            cloudinaryPublicId: cloudinaryPublicId,
            caption: caption,
            location: location,
            createdAt: Date(),
            expiresAt: result.expires_at
        )
        // Refresh per-node caches in parallel rather than sequentially -- posting
        // to 5 nodes shouldn't take 5x the round-trip time.
        await withTaskGroup(of: Void.self) { group in
            for nodeId in nodeIds {
                group.addTask { @MainActor in await self.fetchActive(nodeId: nodeId) }
            }
        }
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
        // The DB delete cascades to story_visibility, so the story is gone in every
        // node it was shared to -- not just the one the user invoked deletion from.
        // Strip it out of every cached node bucket so the user doesn't see ghost
        // stories in the other nodes until they manually pull-to-refresh.
        for key in activeByNodeId.keys {
            activeByNodeId[key]?.removeAll { $0.id == storyId }
        }
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

/// Tracks which story IDs the local user has already watched. Used to show
/// accurate unseen ring state — total count was misleading once some stories
/// were already viewed. Stored in UserDefaults; stays bounded since stories
/// expire after 24h.
final class SeenStoriesStore: @unchecked Sendable {
    static let shared = SeenStoriesStore()

    private let key = "node_seen_story_ids"
    private let queue = DispatchQueue(label: "node.seenstories")
    private var ids: Set<UUID>

    private init() {
        let raw = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        ids = Set(raw.compactMap { UUID(uuidString: $0) })
    }

    func isSeen(_ id: UUID) -> Bool {
        queue.sync { ids.contains(id) }
    }

    func markSeen(_ id: UUID) {
        queue.sync {
            guard !ids.contains(id) else { return }
            ids.insert(id)
            UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
        }
    }

    func unseenCount(in stories: [Story]) -> Int {
        queue.sync { stories.filter { !ids.contains($0.id) }.count }
    }
}

extension Notification.Name {
    static let storiesDidMarkSeen = Notification.Name("node.storiesDidMarkSeen")
}
