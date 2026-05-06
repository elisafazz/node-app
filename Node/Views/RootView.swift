import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(NodeService.self) private var nodes
    @State private var profileLoadFailed = false
    @State private var retrying = false
    @State private var selectedTab = 0
    @State private var pushErrorMessage: String?
    @State private var pendingInviteCode: String?
    @State private var showJoinFromDeeplink = false

    var body: some View {
        Group {
            if auth.session == nil {
                LoginView()
            } else if auth.profile == nil {
                if profileLoadFailed {
                    profileLoadErrorState
                } else {
                    loadingState
                }
            } else {
                mainTabView
            }
        }
        .animation(.easeInOut, value: auth.session?.accessToken)
        .task(id: auth.session?.accessToken) {
            guard auth.session != nil, auth.profile == nil else { return }
            await loadProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushRegistrationFailed)) { note in
            pushErrorMessage = note.object as? String ?? "Push notifications could not be enabled on this device."
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { note in
            // Map APNs categories to top-level tabs. Deep-linking to a specific
            // story / meeting / boop is a follow-up; this at least lands the user
            // on the relevant surface instead of the home tab.
            guard let userInfo = note.userInfo,
                  let category = userInfo["category"] as? String else { return }
            switch category {
            case "node-story", "node-boop":
                selectedTab = 0  // Hub
            case "node-meeting-confirmed", "node-meeting-poll":
                selectedTab = 2  // Calendar
            case "node-thought":
                selectedTab = 1  // Nodes (per-node tab is where thoughts live)
            default:
                break
            }
        }
        .alert("Push notifications unavailable", isPresented: Binding(
            get: { pushErrorMessage != nil },
            set: { if !$0 { pushErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { pushErrorMessage = nil }
        } message: {
            Text(pushErrorMessage ?? "")
        }
        .onOpenURL { url in
            // Universal Link: https://node.elisafazzari.com/join/<8-char-code>
            guard let code = Self.inviteCode(from: url) else { return }
            pendingInviteCode = code
            showJoinFromDeeplink = true
        }
        .sheet(isPresented: $showJoinFromDeeplink, onDismiss: { pendingInviteCode = nil }) {
            if let code = pendingInviteCode {
                JoinNodeView(prefillCode: code)
            }
        }
    }

    private static func inviteCode(from url: URL) -> String? {
        guard let host = url.host, host.hasSuffix("elisafazzari.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "join" else { return nil }
        let code = parts[1]
        return code.count == 8 ? code.uppercased() : nil
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            NetworkHubView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            MyNodesView()
                .tabItem { Label("Nodes", systemImage: "circle.hexagongrid") }
                .tag(1)
            MeetingsListView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(2)
            GlobalSettingsView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(3)
        }
        .tint(Color.nodeBrand)
        .task(id: nodes.myNodes.isEmpty) {
            // Strand-prevention: a brand-new account with zero nodes lands on the Nodes tab
            // (where MyNodesView shows the "Create or Join" empty state). Otherwise the Hub graph
            // is empty and the quick actions all open sheets with disabled buttons.
            if nodes.myNodes.isEmpty {
                selectedTab = 1
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Signing you in…").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var profileLoadErrorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Could not load your profile").font(.headline)
            Text("This usually clears after a moment or two. If not, sign out and back in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack {
                Button("Try again") {
                    profileLoadFailed = false
                    Task { await loadProfile() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.nodeBrand)
                .disabled(retrying)
                Button("Sign out") {
                    Task { try? await auth.signOut() }
                }
                .buttonStyle(.bordered)
                .tint(Color.nodeBrand)
            }
        }
    }

    private func loadProfile() async {
        retrying = true
        defer { retrying = false }
        do {
            try await auth.fetchProfile()
            profileLoadFailed = false
        } catch {
            profileLoadFailed = true
        }
    }
}
