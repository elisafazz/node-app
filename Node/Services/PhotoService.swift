import Foundation

@MainActor
@Observable
final class PhotoService {
    static let shared = PhotoService()

    private(set) var photosByNodeId: [UUID: [Photo]] = [:]
    private(set) var lastError: String?

    func fetchPhotos(nodeId: UUID) async {
        do {
            let photos: [Photo] = try await SupabaseService.shared.database
                .from("photos")
                .select()
                .eq("node_id", value: nodeId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.photosByNodeId[nodeId] = photos
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func createPhoto(nodeId: UUID, authorUserId: UUID, cloudinaryPublicId: String, caption: String?, tag: String?) async throws -> Photo {
        struct PhotoInsert: Encodable {
            let node_id: UUID
            let author_user_id: UUID
            let cloudinary_public_id: String
            let caption: String?
            let tag: String?
        }
        let payload = PhotoInsert(
            node_id: nodeId,
            author_user_id: authorUserId,
            cloudinary_public_id: cloudinaryPublicId,
            caption: caption,
            tag: tag
        )
        let inserted: Photo = try await SupabaseService.shared.database
            .from("photos")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        await fetchPhotos(nodeId: nodeId)
        return inserted
    }

    func updatePhoto(_ photo: Photo, caption: String?, tag: String?) async throws {
        struct PhotoPatch: Encodable { let caption: String?; let tag: String? }
        try await SupabaseService.shared.database
            .from("photos")
            .update(PhotoPatch(caption: caption, tag: tag))
            .eq("id", value: photo.id.uuidString)
            .execute()
        await fetchPhotos(nodeId: photo.nodeId)
    }

    func deletePhoto(_ photo: Photo) async throws {
        try await SupabaseService.shared.database
            .from("photos")
            .delete()
            .eq("id", value: photo.id.uuidString)
            .execute()
        await fetchPhotos(nodeId: photo.nodeId)
    }
}
