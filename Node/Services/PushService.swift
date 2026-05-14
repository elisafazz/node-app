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
    // APNs delivers the device token as soon as the OS has it -- often before
    // AuthService.bootstrap has finished restoring the Supabase session. Hold the
    // token here and let drainPendingToken flush it after sign-in completes.
    private var pendingToken: String?

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Called by AppDelegate after APNs returns a token in response to `registerForRemoteNotifications()`.
    func registerDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        Log.shared.push("device_token_received")
        if AuthService.shared.session != nil {
            await persistDeviceToken(token)
        } else {
            pendingToken = token
        }
    }

    /// Called by AuthService.bootstrap and signInWithApple once a session is established,
    /// so a token captured during the unauthenticated window finally lands in device_tokens.
    func drainPendingToken() async {
        guard let t = pendingToken else { return }
        pendingToken = nil
        await persistDeviceToken(t)
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

    private func persistDeviceToken(_ token: String) async {
        struct DeviceTokenUpsert: Encodable {
            let user_id: UUID
            let token: String
            let updated_at: String
        }
        guard let me = AuthService.shared.session?.user.id else {
            // Bootstrap still hasn't finished -- keep the token queued.
            pendingToken = token
            return
        }
        let payload = DeviceTokenUpsert(
            user_id: me,
            token: token,
            updated_at: Self.iso8601.string(from: Date())
        )
        do {
            // upsert on the unique token column: if this device already has a row,
            // update user_id + updated_at (handles re-installs where same token gets a new user).
            try await SupabaseService.shared.database
                .from("device_tokens")
                .upsert(payload, onConflict: "token")
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
        // Pull the access token from the live SDK session, NOT AuthService.session,
        // which is a snapshot from sign-in/bootstrap and goes stale after the SDK's
        // background refresh (~1h). Using the snapshot causes 401s once expired.
        if let accessToken = try? await SupabaseService.shared.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
            let (data, response) = try await URLSession.shared.data(for: request)
            // URLSession only throws on transport errors -- HTTP 4xx/5xx come back as
            // a normal response object. Surface the status so a misconfigured push
            // pipeline (expired JWT, bad payload, server outage) is visible in logs.
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodySnippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                Log.shared.push("push_fanout_http_\(http.statusCode): \(bodySnippet)")
            }
        } catch {
            Log.shared.error("push_fanout_failed", error: error)
        }
    }
}
