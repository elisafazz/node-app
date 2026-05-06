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
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case originNodeId = "origin_node_id"
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
