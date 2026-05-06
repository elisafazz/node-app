import Foundation

struct Boop: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let senderUserId: UUID
    var message: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderUserId = "sender_user_id"
        case message
        case createdAt = "created_at"
    }
}
