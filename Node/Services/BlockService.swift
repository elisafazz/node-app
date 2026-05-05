import Foundation

@MainActor
@Observable
final class BlockService {
    static let shared = BlockService()

    private(set) var blockedUserIds: Set<UUID> = []

    func loadBlockedUsers() async {
        struct BlockRow: Decodable { let blocked_user_id: UUID }
        do {
            let blocks: [BlockRow] = try await SupabaseService.shared.database
                .from("blocks")
                .select("blocked_user_id")
                .execute()
                .value
            self.blockedUserIds = Set(blocks.map(\.blocked_user_id))
        } catch {
            print("blocks_load_failed:", error)
        }
    }

    func block(userId: UUID) async throws {
        struct BlockInsert: Encodable { let blocker_user_id: UUID; let blocked_user_id: UUID }
        guard let me = AuthService.shared.session?.user.id else { return }
        try await SupabaseService.shared.database
            .from("blocks")
            .insert(BlockInsert(blocker_user_id: me, blocked_user_id: userId))
            .execute()
        await loadBlockedUsers()
    }

    func unblock(userId: UUID) async throws {
        guard let me = AuthService.shared.session?.user.id else { return }
        try await SupabaseService.shared.database
            .from("blocks")
            .delete()
            .eq("blocker_user_id", value: me.uuidString)
            .eq("blocked_user_id", value: userId.uuidString)
            .execute()
        await loadBlockedUsers()
    }

    func isBlocked(_ userId: UUID) -> Bool {
        blockedUserIds.contains(userId)
    }
}
