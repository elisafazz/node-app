import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let pushRegistrationFailed = Notification.Name("com.elisafazzari.node.pushRegistrationFailed")
    /// Posted when the user taps a push notification. userInfo carries the APNs
    /// payload (category, node_id, story_id, meeting_id, etc.) so RootView can
    /// route to the correct destination.
    static let pushNotificationTapped = Notification.Name("com.elisafazzari.node.pushNotificationTapped")
}

@main
struct NodeApp: App {
    @UIApplicationDelegateAdaptor(NodeAppDelegate.self) private var appDelegate

    init() {
        // Give AsyncImage a 100 MB disk cache so thumbnails survive app restarts.
        // Default URLCache is memory-only for simulator + ~50 MB disk on device, which
        // flushes on memory pressure. Cloudinary CDN URLs are stable so disk-caching is safe.
        URLCache.shared = URLCache(memoryCapacity: 20 * 1024 * 1024,
                                   diskCapacity: 100 * 1024 * 1024,
                                   diskPath: "NodeImageCache")
        // Start network path monitoring eagerly so .isExpensive is populated before any view
        // checks it on scenePhase change. Accessing the singleton starts the NWPathMonitor.
        _ = NetworkMonitor.shared
    }

    @State private var auth = AuthService.shared
    @State private var nodes = NodeService.shared
    @State private var stories = StoryService.shared
    @State private var photos = PhotoService.shared
    @State private var thoughts = ThoughtService.shared
    @State private var blocks = BlockService.shared
    @State private var meetings = MeetingService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(nodes)
                .environment(stories)
                .environment(photos)
                .environment(thoughts)
                .environment(blocks)
                .environment(meetings)
                .task {
                    await auth.bootstrap()
                    if auth.session != nil {
                        await nodes.loadMyNodes()
                        await BlockService.shared.loadBlockedUsers()
                        // If push permission was previously granted, re-register on launch so the device token stays fresh.
                        // We do NOT prompt on launch -- that happens in PushService.requestAuthorizationIfNeeded() the
                        // first time the user creates or joins a node. Apple HIG: ask for permissions in context.
                        await PushService.shared.refreshRegistrationIfAlreadyAuthorized()
                    }
                }
        }
    }
}

final class NodeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushService.shared.registerDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.shared.error("apns_register_failed", error: error)
        // Surface the failure so the user knows push notifications won't work.
        // This only fires if the device itself rejects registration (e.g. simulator with push entitlement off, provisioning mismatch).
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .pushRegistrationFailed,
                object: error.localizedDescription
            )
        }
    }

    // Allow stories / new-thought banners while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// User tapped a notification (foreground or background). Forward the userInfo
    /// to RootView via NotificationCenter so it can route to the relevant destination
    /// (story player, meeting detail, boop inbox, etc.). Without this, taps just open
    /// the app to whatever tab was last active, making notifications useless.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .pushNotificationTapped,
                object: nil,
                userInfo: userInfo
            )
        }
        completionHandler()
    }
}
