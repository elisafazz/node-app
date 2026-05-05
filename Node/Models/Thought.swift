import Foundation

struct Thought: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let nodeId: UUID
    let authorUserId: UUID
    var body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId = "node_id"
        case authorUserId = "author_user_id"
        case body
        case createdAt = "created_at"
    }
}
