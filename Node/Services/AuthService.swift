import Foundation
import AuthenticationServices
import Supabase

@MainActor
@Observable
final class AuthService: NSObject {
    static let shared = AuthService()

    private(set) var session: Session?
    private(set) var profile: AppUser?

    enum AuthError: Error, LocalizedError {
        case appleNoIdentityToken
        case appleNoAuthorizationCode
        case codeExchangeFailed(statusCode: Int)
        case sessionMissing
        case deletionFailed(String)

        var errorDescription: String? {
            switch self {
            case .appleNoIdentityToken: return "Sign in with Apple did not return an identity token."
            case .appleNoAuthorizationCode: return "Sign in with Apple did not return an authorization code."
            case .codeExchangeFailed(let code): return "Backend code exchange failed (HTTP \(code))."
            case .sessionMissing: return "No active session."
            case .deletionFailed(let msg): return "Account deletion failed: \(msg)"
            }
        }
    }

    /// Submits an Apple ID identity token + authorization code to Supabase Auth + our custom code-exchange Edge Function.
    /// The identity token logs the user in to Supabase. The authorization code is sent ONCE to apple-exchange-code so we can capture
    /// the refresh token for future revocation (ADR-004).
    func signInWithApple(identityToken: String, nonce: String, authorizationCode: String) async throws {
        let supabase = SupabaseService.shared
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: identityToken, nonce: nonce)
        )
        self.session = session
        try await fetchProfile()

        // Exchange the authorization code for a refresh token (stored server-side).
        // This is best-effort -- if it fails we log it. Sign-in still succeeds.
        do {
            try await exchangeAppleCode(authorizationCode)
        } catch {
            Log.shared.error("apple_code_exchange_failed", error: error)
        }
    }

    private func exchangeAppleCode(_ code: String) async throws {
        guard let session else { throw AuthError.sessionMissing }
        let response: [String: Bool] = try await SupabaseService.shared.functions.invoke(
            "apple-exchange-code",
            options: .init(body: ["code": code])
        )
        if response["ok"] != true {
            throw AuthError.codeExchangeFailed(statusCode: -1)
        }
    }

    func fetchProfile() async throws {
        guard let session else { throw AuthError.sessionMissing }
        let user: AppUser = try await SupabaseService.shared.database
            .from("users")
            .select()
            .eq("id", value: session.user.id)
            .single()
            .execute()
            .value
        self.profile = user
    }

    func signOut() async throws {
        try await SupabaseService.shared.auth.signOut()
        self.session = nil
        self.profile = nil
    }

    /// Calls the delete-user-data Edge Function which performs the full Apple-compliant cascade.
    func deleteAccount() async throws {
        guard session != nil else { throw AuthError.sessionMissing }
        struct DeleteResult: Decodable { let ok: Bool; let cloudinary_failed_count: Int? }
        let result: DeleteResult = try await SupabaseService.shared.functions.invoke(
            "delete-user-data",
            options: .init(body: [String: String]())  // no body needed; user is identified by JWT
        )
        if !result.ok {
            throw AuthError.deletionFailed("server returned not-ok")
        }
        // Local cleanup
        try? await SupabaseService.shared.auth.signOut()
        self.session = nil
        self.profile = nil
    }

    /// Restore session on app launch.
    func bootstrap() async {
        do {
            let session = try await SupabaseService.shared.auth.session
            self.session = session
            try await fetchProfile()
        } catch {
            self.session = nil
            self.profile = nil
        }
    }
}
