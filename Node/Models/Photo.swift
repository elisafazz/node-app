import Foundation

struct Photo: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let nodeId: UUID
    let authorUserId: UUID
    let cloudinaryPublicId: String
    var caption: String?
    var tag: String?
    var isFavorite: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId = "node_id"
        case authorUserId = "author_user_id"
        case cloudinaryPublicId = "cloudinary_public_id"
        case caption
        case tag
        case isFavorite = "is_favorite"
        case createdAt = "created_at"
    }

    // is_favorite was added in migration 0011. Decode tolerantly so a Photo
    // row read from a not-yet-migrated env still loads (default false).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.nodeId = try c.decode(UUID.self, forKey: .nodeId)
        self.authorUserId = try c.decode(UUID.self, forKey: .authorUserId)
        self.cloudinaryPublicId = try c.decode(String.self, forKey: .cloudinaryPublicId)
        self.caption = try c.decodeIfPresent(String.self, forKey: .caption)
        self.tag = try c.decodeIfPresent(String.self, forKey: .tag)
        self.isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    init(id: UUID, nodeId: UUID, authorUserId: UUID, cloudinaryPublicId: String, caption: String?, tag: String?, isFavorite: Bool = false, createdAt: Date) {
        self.id = id
        self.nodeId = nodeId
        self.authorUserId = authorUserId
        self.cloudinaryPublicId = cloudinaryPublicId
        self.caption = caption
        self.tag = tag
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    var thumbnailURL: URL? {
        URL(string: "https://res.cloudinary.com/\(Constants.Cloudinary.cloudName)/image/upload/w_360,q_auto,f_auto/\(cloudinaryPublicId)")
    }

    var fullURL: URL? {
        URL(string: "https://res.cloudinary.com/\(Constants.Cloudinary.cloudName)/image/upload/w_1080,q_auto,f_auto/\(cloudinaryPublicId)")
    }
}
