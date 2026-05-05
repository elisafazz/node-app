import Foundation

@MainActor
@Observable
final class StoryService {
    static let shared = StoryService()

    /// Active stories per node id (within 24h window).
    private(set) var activeByNodeId: [UUID: [Story]] = [:]
    private(set) var archiveByNodeIdYear: [String: [Story]] = [:]
    private(set) var lastError: String?

    private func archiveKey(nodeId: UUID, year: Int) -> String { "\(nodeId.uuidString)-\(year)" }

    func fetchActive(nodeId: UUID) async {
        do {
            let cutoff = Date().addingTimeInterval(-Constants.Story.activeWindowSeconds)
            let stories: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select()
                .eq("node_id", value: nodeId.uuidString)
                .gt("created_at", value: ISO8601DateFormatter().string(from: cutoff))
                .order("created_at", ascending: false)  // newest-first per Sunzzari S57 + Miracles S9
                .execute()
                .value
            self.activeByNodeId[nodeId] = stories
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func fetchArchive(nodeId: UUID, year: Int) async {
        do {
            let yearStart = ISO8601DateFormatter().string(from: Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))!)
            let yearEnd = ISO8601DateFormatter().string(from: Calendar(identifier: .gregorian).date(from: DateComponents(year: year + 1, month: 1, day: 1))!)
            let stories: [Story] = try await SupabaseService.shared.database
                .from("stories")
                .select()
                .eq("node_id", value: nodeId.uuidString)
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

    func createStory(nodeId: UUID, authorUserId: UUID, cloudinaryPublicId: String, caption: String?) async throws -> Story {
        struct StoryInsert: Encodable {
            let node_id: UUID
            let author_user_id: UUID
            let cloudinary_public_id: String
            let caption: String?
            let expires_at: String
        }
        let now = Date()
        let payload = StoryInsert(
            node_id: nodeId,
            author_user_id: authorUserId,
            cloudinary_public_id: cloudinaryPublicId,
            caption: caption,
            expires_at: ISO8601DateFormatter().string(from: now.addingTimeInterval(Constants.Story.activeWindowSeconds))
        )
        let inserted: Story = try await SupabaseService.shared.database
            .from("stories")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        await fetchActive(nodeId: nodeId)
        await PushService.shared.fanOutStoryNotification(nodeId: nodeId, authorUserId: authorUserId, caption: caption)
        return inserted
    }

    func deleteStory(_ storyId: UUID, nodeId: UUID) async throws {
        try await SupabaseService.shared.database
            .from("stories")
            .delete()
            .eq("id", value: storyId.uuidString)
            .execute()
        await fetchActive(nodeId: nodeId)
    }
}
