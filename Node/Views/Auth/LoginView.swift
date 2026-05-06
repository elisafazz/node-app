import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var currentNonce: String?
    @State private var error: String?
    @State private var hasAcceptedTerms = false
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Node")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                Text("Small invite-only groups for sharing photos, stories, and thoughts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $hasAcceptedTerms) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I am at least 13 years old.")
                            .font(.subheadline)
                        Text("I have read and agree to the [Terms of Service](\(Constants.URLs.tos.absoluteString)), [Privacy Policy](\(Constants.URLs.privacy.absoluteString)), and [EULA](\(Constants.URLs.eula.absoluteString)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal)

            SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: handleAppleResult)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .padding(.horizontal, 24)
                .disabled(!hasAcceptedTerms || isSigningIn)
                .opacity(hasAcceptedTerms && !isSigningIn ? 1 : 0.4)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 24)
        }
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = sha256(nonce)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            self.error = "Sign in failed. \(UserFacingError.message(for: err))"
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                self.error = "Sign in did not return an identity token. Try again."
                return
            }
            guard
                let codeData = credential.authorizationCode,
                let authorizationCode = String(data: codeData, encoding: .utf8)
            else {
                self.error = "Sign in did not return an authorization code. Try again."
                return
            }
            isSigningIn = true
            Task {
                do {
                    try await auth.signInWithApple(identityToken: identityToken, nonce: nonce, authorizationCode: authorizationCode)
                } catch {
                    self.error = UserFacingError.message(for: error)
                    isSigningIn = false
                }
                // On success RootView transitions away, so no need to reset isSigningIn.
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            randoms.forEach { random in
                if remaining > 0, random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
