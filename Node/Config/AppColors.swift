import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Placeholder palette. Will be set during Phase 3 design pick (TBD with Elisa).
// Uses SwiftUI / UIKit semantic colors so light/dark mode adapt automatically.
extension Color {
    #if canImport(UIKit)
    static let nodeBackground = Color(uiColor: .systemBackground)
    static let nodeSurface = Color(uiColor: .secondarySystemBackground)
    static let nodeBorder = Color(uiColor: .separator)
    #else
    static let nodeBackground = Color.white
    static let nodeSurface = Color.gray.opacity(0.1)
    static let nodeBorder = Color.gray.opacity(0.3)
    #endif

    static let nodeText = Color.primary
    static let nodeTextSubtle = Color.secondary
    static let nodeAccent = Color.accentColor

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

    private static func deterministicAccent(for seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.77, green: 0.45, blue: 0.29),  // terracotta
            Color(red: 0.50, green: 0.65, blue: 0.45),  // sage
            Color(red: 0.85, green: 0.70, blue: 0.30),  // amber
            Color(red: 0.45, green: 0.55, blue: 0.75),  // dusty blue
            Color(red: 0.70, green: 0.45, blue: 0.65),  // mauve
            Color(red: 0.50, green: 0.40, blue: 0.30),  // mocha
        ]
        let idx = abs(seed.hashValue) % palette.count
        return palette[idx]
    }
}
