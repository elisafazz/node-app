import Foundation

struct Membership: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let nodeId: UUID
    let userId: UUID
    let role: Role
    var perNodeDisplayName: String?
    var perNodeAccentColor: String?
    var perNodeEmoji: String?
    var deviceToken: String?
    let joinedAt: Date

    enum Role: String, Codable, Sendable {
        case owner
        case member
    }

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId = "node_id"
        case userId = "user_id"
        case role
        case perNodeDisplayName = "per_node_display_name"
        case perNodeAccentColor = "per_node_accent_color"
        case perNodeEmoji = "per_node_emoji"
        case deviceToken = "device_token"
        case joinedAt = "joined_at"
    }
}

/// View-friendly composite: a Membership joined with the User's public profile.
/// Used for member lists, story author headers, etc.
struct NodeMember: Identifiable, Hashable, Sendable {
    let user: AppUser
    let membership: Membership

    var id: UUID { membership.id }
    var displayName: String { membership.perNodeDisplayName ?? user.displayName }
    var emoji: String? { membership.perNodeEmoji }
    var accentColorHex: String? { membership.perNodeAccentColor }
}
