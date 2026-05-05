import Foundation

enum Constants {
    enum Backend {
        static let supabaseURL = URL(string: "https://YOUR-PROJECT.supabase.co")!  // Set via Phase 1 once Supabase project exists
        static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"  // Public, safe to embed
        static let pushFanoutURL = URL(string: "https://node-backend.vercel.app/api/push")!
    }

    enum Cloudinary {
        static let cloudName = "YOUR_CLOUDINARY_CLOUD"
    }

    enum AppleSignIn {
        static let serviceID = "com.elisafazzari.node.signin"  // Set in Apple Developer Console
    }

    enum Bundle {
        static let identifier = "com.elisafazzari.node"
        static let displayName = "Node"
    }

    enum Story {
        static let activeWindowSeconds: TimeInterval = 24 * 60 * 60  // 24h
        static let segmentDurationSeconds: TimeInterval = 5
    }

    enum Node {
        static let memberCapDefault = 10
        static let inviteCodeLength = 8
    }

    enum URLs {
        static let tos = URL(string: "https://node-backend.vercel.app/tos")!
        static let privacy = URL(string: "https://node-backend.vercel.app/privacy")!
        static let eula = URL(string: "https://node-backend.vercel.app/eula")!
        static let contact = URL(string: "https://node-backend.vercel.app/contact")!
    }
}
