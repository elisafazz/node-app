import SwiftUI
import UIKit
import UserNotifications

@main
struct NodeApp: App {
    @UIApplicationDelegateAdaptor(NodeAppDelegate.self) private var appDelegate

    @State private var auth = AuthService.shared
    @State private var nodes = NodeService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(nodes)
                .task {
                    await auth.bootstrap()
                    if auth.session != nil {
                        await nodes.loadMyNodes()
                        await BlockService.shared.loadBlockedUsers()
                    }
                }
        }
    }
}

final class NodeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushService.shared.registerDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("apns_register_failed:", error)
    }
}
