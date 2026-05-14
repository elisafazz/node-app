import Foundation

/// A Story is now author-owned and visible across N nodes via the `story_visibility` junction
/// (see ADR-012). The DB column `node_id` was renamed to `origin_node_id` in migration 0002 --
/// it's nullable telemetry for "where compose was launched from", not a visibility scope.
struct Story: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let originNodeId: UUID?
    let authorUserId: UUID
    let cloudinaryPublicId: String
    var caption: String?
    var location: String?
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case originNodeId = "origin_node_id"
        case authorUserId = "author_user_id"
        case cloudinaryPublicId = "cloudinary_public_id"
        case caption
        case location
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    // location was added in migration 0011. Decode tolerantly so a Story row
    // from a not-yet-migrated env still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.originNodeId = try c.decodeIfPresent(UUID.self, forKey: .originNodeId)
        self.authorUserId = try c.decode(UUID.self, forKey: .authorUserId)
        self.cloudinaryPublicId = try c.decode(String.self, forKey: .cloudinaryPublicId)
        self.caption = try c.decodeIfPresent(String.self, forKey: .caption)
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.expiresAt = try c.decode(Date.self, forKey: .expiresAt)
    }

    init(id: UUID, originNodeId: UUID?, authorUserId: UUID, cloudinaryPublicId: String, caption: String?, location: String? = nil, createdAt: Date, expiresAt: Date) {
        self.id = id
        self.originNodeId = originNodeId
        self.authorUserId = authorUserId
        self.cloudinaryPublicId = cloudinaryPublicId
        self.caption = caption
        self.location = location
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var thumbnailURL: URL? {
        cloudinaryURL(transform: "w_360,q_auto,f_auto")
    }

    var fullURL: URL? {
        cloudinaryURL(transform: "w_1080,q_auto,f_auto")
    }

    private func cloudinaryURL(transform: String) -> URL? {
        URL(string: "https://res.cloudinary.com/\(Constants.Cloudinary.cloudName)/image/upload/\(transform)/\(cloudinaryPublicId)")
    }
}
