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
        // Drain any APNs token captured before the session existed.
        await PushService.shared.drainPendingToken()
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
        // Local state is the source of truth for "is this app signed in." If the
        // server signOut throws (network down, token already revoked), holding on
        // to a stale session leaves the UI in a half-signed-in state that the user
        // can't recover from -- they tap Sign Out, it errors, but they're still
        // visibly signed in. Defer guarantees the local clear runs whether the
        // server call succeeds or throws.
        defer {
            self.session = nil
            self.profile = nil
            // Clear all cached feature data so a subsequent sign-in starts clean.
            NodeService.shared.clearCache()
            StoryService.shared.clearCache()
            PhotoService.shared.clearCache()
            ThoughtService.shared.clearCache()
            MeetingService.shared.clearCache()
            BlockService.shared.clearCache()
        }
        try await SupabaseService.shared.auth.signOut()
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
        // signOut() clears session, profile, and all feature service caches atomically.
        // Calling it here instead of open-coding the cleanup means we can't diverge
        // from signOut()'s cache-clear list as new services are added.
        try? await signOut()
    }

    /// Restore session on app launch.
    func bootstrap() async {
        // Distinguish "Supabase has no valid session" (real signed-out state)
        // from "fetchProfile failed on a transient network error" (still signed in,
        // just couldn't load the user row yet). The old combined catch wiped a valid
        // session every time the profile query hiccuped on launch.
        do {
            self.session = try await SupabaseService.shared.auth.session
        } catch {
            self.session = nil
            self.profile = nil
            return
        }
        // Profile fetch is best-effort -- a transient failure here must not log the user out.
        do {
            try await fetchProfile()
        } catch {
            Log.shared.error("bootstrap_profile_fetch_failed", error: error)
        }
        // Drain any APNs token that arrived before the session was restored.
        await PushService.shared.drainPendingToken()
    }
}
