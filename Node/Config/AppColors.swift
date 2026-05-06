import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Placeholder palette. Will be set during Phase 3 design pick (TBD with Elisa).
// Uses SwiftUI / UIKit semantic colors so light/dark mode adapt automatically.
extension Color {
    #if canImport(UIKit)
    /// Warm cream #FBF6EE in light mode; system background in dark mode.
    static let nodeBackground = Color(uiColor: UIColor(dynamicProvider: { traits in
        traits.userInterfaceStyle == .dark
            ? .systemBackground
            : UIColor(red: 0.984, green: 0.965, blue: 0.937, alpha: 1)
    }))
    static let nodeSurface = Color(uiColor: UIColor(dynamicProvider: { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemBackground
            : UIColor(red: 0.957, green: 0.937, blue: 0.910, alpha: 1)
    }))
    static let nodeBorder = Color(uiColor: .separator)
    #else
    static let nodeBackground = Color(red: 0.984, green: 0.965, blue: 0.937)
    static let nodeSurface = Color(red: 0.957, green: 0.937, blue: 0.910)
    static let nodeBorder = Color.gray.opacity(0.3)
    #endif

    static let nodeText = Color.primary
    static let nodeTextSubtle = Color.secondary
    static let nodeAccent = Color.accentColor

    /// Primary brand accent from the Stitch design language: warm coral/red-orange used on the
    /// "Node" wordmark, the create-node + button, the floating action button, and active tab states.
    /// Hex ~#E94B26.
    static let nodeBrand = Color(red: 0.914, green: 0.294, blue: 0.149)

    /// Cover-art logo color (teal ~#2A7A8C). Reserved for the brand mark / app icon contexts only;
    /// the UI accent throughout the app is `nodeBrand` (warm coral). Kept available so logo
    /// renderings stay consistent with the cover art.
    static let nodeLogoTeal = Color(red: 0.165, green: 0.478, blue: 0.549)

    /// Resolve a per-node accent color from the membership override hex or a deterministic fallback per user-in-node.
    static func forMembership(hex: String?, fallbackSeed: String) -> Color {
        if let hex, let color = Color(hex: hex) { return color }
        return deterministicAccent(for: fallbackSeed)
    }

    init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// Returns a 6-char uppercase hex string (no #) for the color's RGB components.
    var hexString: String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "E94B26"
        #endif
    }

    private static func deterministicAccent(for seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.77, green: 0.45, blue: 0.29),  // terracotta
            Color(red: 0.50, green: 0.65, blue: 0.45),  // sage
            Color(red: 0.85, green: 0.70, blue: 0.30),  // amber
            Color(red: 0.45, green: 0.55, blue: 0.75),  // dusty blue
            Color(red: 0.70, green: 0.45, blue: 0.65),  // mauve
            Color(red: 0.50, green: 0.40, blue: 0.30),  // mocha
        ]
        // Use a stable FNV-1a hash instead of String.hashValue, which is randomized
        // per process launch (Swift hash randomization). This ensures the same node/user
        // always gets the same color across app restarts.
        var hash: UInt32 = 2166136261
        for byte in seed.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        let idx = Int(hash) % palette.count
        return palette[idx]
    }
}
