import Foundation
import Supabase

@MainActor
@Observable
final class NodeService {
    static let shared = NodeService()

    private(set) var myNodes: [NodeRecord] = []
    private(set) var myMembershipsByNodeId: [UUID: Membership] = [:]
    private(set) var lastError: String?

    enum JoinResult: Equatable {
        case joined(nodeId: UUID, name: String)
        case alreadyMember(nodeId: UUID, name: String)
        case invalidCode
        case rateLimited
        case nodeFull
    }

    func loadMyNodes() async {
        do {
            let memberships: [Membership] = try await SupabaseService.shared.database
                .from("memberships")
                .select()
                .execute()
                .value
            myMembershipsByNodeId = Dictionary(uniqueKeysWithValues: memberships.map { ($0.nodeId, $0) })

            let nodeIds = memberships.map(\.nodeId)
            guard !nodeIds.isEmpty else { myNodes = []; return }
            let nodes: [NodeRecord] = try await SupabaseService.shared.database
                .from("nodes")
                .select()
                .in("id", values: nodeIds.map(\.uuidString))
                .order("updated_at", ascending: false)
                .execute()
                .value
            self.myNodes = nodes
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Calls the security-definer create_node RPC. Returns (nodeId, inviteCode).
    func createNode(name: String) async throws -> (nodeId: UUID, inviteCode: String) {
        struct CreateRow: Decodable { let node_id: UUID; let invite_code: String }
        let rows: [CreateRow] = try await SupabaseService.shared.database
            .rpc("create_node", params: ["node_name": name])
            .execute()
            .value
        guard let first = rows.first else { throw NSError(domain: "NodeService", code: -1) }
        await loadMyNodes()
        return (first.node_id, first.invite_code)
    }

    func joinByInviteCode(_ code: String) async throws -> JoinResult {
        struct JoinRow: Decodable { let node_id: UUID?; let node_name: String?; let error: String? }
        let rows: [JoinRow] = try await SupabaseService.shared.database
            .rpc("join_node_by_invite_code", params: ["code": code])
            .execute()
            .value
        guard let first = rows.first else { return .invalidCode }
        if let err = first.error {
            switch err {
            case "rate_limited": return .rateLimited
            case "invalid_code": return .invalidCode
            case "node_full": return .nodeFull
            case "already_member":
                if let id = first.node_id, let name = first.node_name {
                    return .alreadyMember(nodeId: id, name: name)
                }
                return .invalidCode
            default: return .invalidCode
            }
        }
        guard let id = first.node_id, let name = first.node_name else { return .invalidCode }
        await loadMyNodes()
        return .joined(nodeId: id, name: name)
    }

    func rotateInviteCode(nodeId: UUID) async throws -> String {
        let rows: [String] = try await SupabaseService.shared.database
            .rpc("rotate_invite_code", params: ["target_node_id": nodeId.uuidString])
            .execute()
            .value
        guard let code = rows.first else { throw NSError(domain: "NodeService", code: -2) }
        await loadMyNodes()
        return code
    }

    func leaveNode(nodeId: UUID, userId: UUID) async throws {
        try await SupabaseService.shared.database
            .from("memberships")
            .delete()
            .eq("node_id", value: nodeId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        await loadMyNodes()
    }

    func members(of nodeId: UUID) async throws -> [NodeMember] {
        let memberships: [Membership] = try await SupabaseService.shared.database
            .from("memberships")
            .select()
            .eq("node_id", value: nodeId.uuidString)
            .execute()
            .value
        let userIds = memberships.map { $0.userId.uuidString }
        let users: [AppUser] = try await SupabaseService.shared.database
            .from("users")
            .select()
            .in("id", values: userIds)
            .execute()
            .value
        let userById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        return memberships.compactMap { m in
            guard let user = userById[m.userId] else { return nil }
            return NodeMember(user: user, membership: m)
        }
    }

    func updateMyMembership(nodeId: UUID, displayName: String?, accentColorHex: String?, emoji: String?) async throws {
        struct Patch: Encodable {
            let per_node_display_name: String?
            let per_node_accent_color: String?
            let per_node_emoji: String?
        }
        let patch = Patch(
            per_node_display_name: displayName,
            per_node_accent_color: accentColorHex,
            per_node_emoji: emoji
        )
        try await SupabaseService.shared.database
            .from("memberships")
            .update(patch)
            .eq("node_id", value: nodeId.uuidString)
            .execute()
        await loadMyNodes()
    }
}
