import Foundation

@MainActor
@Observable
final class BoopService {
    static let shared = BoopService()

    private(set) var lastError: String?

    /// Sends a boop to selected nodes via the send_boop SECURITY DEFINER RPC.
    func sendBoop(message: String?, nodeIds: [UUID]) async throws -> UUID {
        struct RPCParams: Encodable {
            let p_message: String?
            let p_node_ids: [UUID]
        }
        let params = RPCParams(p_message: message, p_node_ids: nodeIds)
        let boopId: UUID = try await SupabaseService.shared.database
            .rpc("send_boop", params: params)
            .single()
            .execute()
            .value
        await fanOutBoopNotification(nodeIds: nodeIds, message: message)
        return boopId
    }

    private func fanOutBoopNotification(nodeIds: [UUID], message: String?) async {
        guard let session = AuthService.shared.session else { return }
        let title = "Someone booped you"
        let body = message?.isEmpty == false ? message! : "Tap to see who"
        await PushService.shared.sendMultiNode(
            nodeIds: nodeIds,
            authorUserId: session.user.id,
            title: title,
            body: body,
            category: "node-boop"
        )
    }
}
