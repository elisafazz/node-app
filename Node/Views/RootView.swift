import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @State private var profileLoadFailed = false
    @State private var retrying = false

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
                MyNodesView()
            }
        }
        .animation(.easeInOut, value: auth.session?.accessToken)
        .task(id: auth.session?.accessToken) {
            guard auth.session != nil, auth.profile == nil else { return }
            await loadProfile()
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
                .disabled(retrying)
                Button("Sign out") {
                    Task { try? await auth.signOut() }
                }
                .buttonStyle(.bordered)
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
