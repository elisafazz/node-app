import Foundation

struct Story: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let nodeId: UUID
    let authorUserId: UUID
    let cloudinaryPublicId: String
    var caption: String?
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId = "node_id"
        case authorUserId = "author_user_id"
        case cloudinaryPublicId = "cloudinary_public_id"
        case caption
        case createdAt = "created_at"
        case expiresAt = "expires_at"
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
