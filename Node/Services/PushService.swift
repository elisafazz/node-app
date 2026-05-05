import Foundation
import UIKit

/// Pushes APNs device token registration up to the user's memberships, and triggers fan-out for new stories.
@MainActor
@Observable
final class PushService {
    static let shared = PushService()

    private(set) var deviceToken: String?

    /// Called from AppDelegate or NodeApp on successful APNs registration.
    func registerDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        await persistTokenToMyMemberships(token)
    }

    private func persistTokenToMyMemberships(_ token: String) async {
        struct DeviceTokenPatch: Encodable { let device_token: String }
        do {
            try await SupabaseService.shared.database
                .from("memberships")
                .update(DeviceTokenPatch(device_token: token))
                .execute()
        } catch {
            print("device_token_persist_failed:", error)
        }
    }

    func fanOutStoryNotification(nodeId: UUID, authorUserId: UUID, caption: String?) async {
        // Pulls authorDisplayName lookup is best-effort -- if it fails we still send a generic message
        let title = "Someone posted a story"
        let body = caption?.isEmpty == false ? caption! : "Tap to watch"

        var request = URLRequest(url: Constants.Backend.pushFanoutURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include the user's Supabase JWT so the server can identify the caller (PUSH_FANOUT_SECRET shared by server-to-server mode is alternative)
        if let session = AuthService.shared.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        struct PushBody: Encodable {
            let node_id: UUID
            let author_user_id: UUID
            let title: String
            let body: String
            let category: String
        }
        let payload = PushBody(node_id: nodeId, author_user_id: authorUserId, title: title, body: body, category: "node-story")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Push fan-out is best-effort. Story still posts even if push fails.
            print("push_fanout_failed:", error)
        }
    }
}
