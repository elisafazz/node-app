import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.session == nil {
                LoginView()
            } else if auth.profile == nil {
                ProgressView("Loading…")
            } else {
                MyNodesView()
            }
        }
        .animation(.easeInOut, value: auth.session?.accessToken)
    }
}
