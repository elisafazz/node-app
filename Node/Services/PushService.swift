import Foundation
import UIKit
import UserNotifications

/// Pushes APNs device token registration up to the user's memberships, and triggers fan-out for new stories.
/// Permission is requested in context (per Apple HIG): the first time the user creates or joins a node, not on launch.
@MainActor
@Observable
final class PushService {
    static let shared = PushService()

    private(set) var deviceToken: String?

    /// Called by AppDelegate after APNs returns a token in response to `registerForRemoteNotifications()`.
    func registerDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        Log.shared.push("device_token_received")
        await persistTokenToMyMemberships(token)
    }

    /// In-context prompt: call this from CreateNodeView/JoinNodeView success paths.
    /// If the user has already responded (granted or denied), this is a no-op.
    /// If they granted previously, registers for remote notifications to refresh the token.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                Log.shared.push(granted ? "permission_granted" : "permission_denied")
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                Log.shared.error("permission_request_failed", error: error)
            }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            // User explicitly denied; do not re-prompt. Settings deep-link handled elsewhere if we want to nudge.
            Log.shared.push("permission_already_denied")
        @unknown default:
            break
        }
    }

    /// Called on app launch from NodeApp.task. If the user previously granted, this re-registers so the token stays fresh.
    /// Does NOT trigger the permission dialog.
    func refreshRegistrationIfAlreadyAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func persistTokenToMyMemberships(_ token: String) async {
        struct DeviceTokenPatch: Encodable { let device_token: String }
        guard let me = AuthService.shared.session?.user.id else { return }
        do {
            try await SupabaseService.shared.database
                .from("memberships")
                .update(DeviceTokenPatch(device_token: token))
                .eq("user_id", value: me.uuidString)
                .execute()
        } catch {
            Log.shared.error("device_token_persist_failed", error: error)
        }
    }

    func fanOutStoryNotification(nodeIds: [UUID], authorUserId: UUID, caption: String?) async {
        let title = "Someone posted a story"
        let body = caption?.isEmpty == false ? caption! : "Tap to watch"
        await sendMultiNode(
            nodeIds: nodeIds,
            authorUserId: authorUserId,
            title: title,
            body: body,
            category: "node-story"
        )
    }

    /// Single multi-node push: server unions memberships across all node_ids, dedupes recipients
    /// by user_id, and sends one APNs payload per unique recipient device token. Replaces the old
    /// per-node loop which double-pushed users in multiple shared nodes.
    func sendMultiNode(
        nodeIds: [UUID],
        authorUserId: UUID,
        title: String,
        body: String,
        category: String
    ) async {
        guard !nodeIds.isEmpty else { return }
        struct PushBody: Encodable {
            let node_ids: [UUID]
            let author_user_id: UUID
            let title: String
            let body: String
            let category: String
        }
        var request = URLRequest(url: Constants.Backend.pushFanoutURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session = AuthService.shared.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        let payload = PushBody(
            node_ids: nodeIds,
            author_user_id: authorUserId,
            title: title,
            body: body,
            category: category
        )
        request.httpBody = try? JSONEncoder().encode(payload)
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            Log.shared.error("push_fanout_failed", error: error)
        }
    }
}
