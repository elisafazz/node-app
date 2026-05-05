import Foundation

@MainActor
@Observable
final class ThoughtService {
    static let shared = ThoughtService()

    private(set) var thoughtsByNodeId: [UUID: [Thought]] = [:]
    private(set) var lastError: String?

    func fetchThoughts(nodeId: UUID) async {
        do {
            let thoughts: [Thought] = try await SupabaseService.shared.database
                .from("thoughts")
                .select()
                .eq("node_id", value: nodeId.uuidString)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            self.thoughtsByNodeId[nodeId] = thoughts
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func createThought(nodeId: UUID, authorUserId: UUID, body: String) async throws -> Thought {
        struct ThoughtInsert: Encodable {
            let node_id: UUID
            let author_user_id: UUID
            let body: String
        }
        let inserted: Thought = try await SupabaseService.shared.database
            .from("thoughts")
            .insert(ThoughtInsert(node_id: nodeId, author_user_id: authorUserId, body: body))
            .select()
            .single()
            .execute()
            .value
        await fetchThoughts(nodeId: nodeId)
        return inserted
    }

    func deleteThought(_ thought: Thought) async throws {
        try await SupabaseService.shared.database
            .from("thoughts")
            .delete()
            .eq("id", value: thought.id.uuidString)
            .execute()
        await fetchThoughts(nodeId: thought.nodeId)
    }
}
