import Foundation

struct AppUser: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let appleUserId: String?
    var displayName: String
    var avatarUrl: URL?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case appleUserId = "apple_user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
