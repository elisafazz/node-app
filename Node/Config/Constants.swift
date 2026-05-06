import Foundation

enum Constants {
    enum Backend {
        static let supabaseURL = URL(string: "https://dbytvajhgtkigarirxni.supabase.co")!
        static let supabaseAnonKey = "sb_publishable_wX22cZiuKkCAe8NilA27cg_3Nsf5xJJ"  // Public, safe to embed
        static let pushFanoutURL = URL(string: "https://node-app-backend.vercel.app/api/push")!
    }

    enum Cloudinary {
        static let cloudName = "dhkw1tuq6"
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
        static let tos = URL(string: "https://node-app-backend.vercel.app/tos")!
        static let privacy = URL(string: "https://node-app-backend.vercel.app/privacy")!
        static let eula = URL(string: "https://node-app-backend.vercel.app/eula")!
        static let contact = URL(string: "https://node-app-backend.vercel.app/contact")!
    }
}
