import Foundation

// `NodeRecord` to avoid clashing with `Node` (the app name) in scope.
struct NodeRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let ownerId: UUID
    var inviteCode: String
    var inviteCodeRevokedAt: Date?
    var memberCap: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case inviteCode = "invite_code"
        case inviteCodeRevokedAt = "invite_code_revoked_at"
        case memberCap = "member_cap"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
