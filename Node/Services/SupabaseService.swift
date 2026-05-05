import Foundation
import Supabase

@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: Constants.Backend.supabaseURL,
            supabaseKey: Constants.Backend.supabaseAnonKey
        )
    }

    var auth: AuthClient { client.auth }
    var database: PostgrestClient { client.database }
    var realtime: RealtimeClientV2 { client.realtimeV2 }
    var functions: FunctionsClient { client.functions }
}
