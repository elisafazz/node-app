import Foundation

struct Photo: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let nodeId: UUID
    let authorUserId: UUID
    let cloudinaryPublicId: String
    var caption: String?
    var tag: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId = "node_id"
        case authorUserId = "author_user_id"
        case cloudinaryPublicId = "cloudinary_public_id"
        case caption
        case tag
        case createdAt = "created_at"
    }

    var thumbnailURL: URL? {
        URL(string: "https://res.cloudinary.com/\(Constants.Cloudinary.cloudName)/image/upload/w_360,q_auto,f_auto/\(cloudinaryPublicId)")
    }

    var fullURL: URL? {
        URL(string: "https://res.cloudinary.com/\(Constants.Cloudinary.cloudName)/image/upload/w_1080,q_auto,f_auto/\(cloudinaryPublicId)")
    }
}
