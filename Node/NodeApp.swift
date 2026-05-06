import SwiftUI
import UIKit
import UserNotifications

@main
struct NodeApp: App {
    @UIApplicationDelegateAdaptor(NodeAppDelegate.self) private var appDelegate

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
    }

    // Allow stories / new-thought banners while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
