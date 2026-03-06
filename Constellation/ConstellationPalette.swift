import SwiftUI

enum ConstellationPalette {
    static let accent = Color(red: 0.22, green: 0.57, blue: 1.0)
    static let accentSoft = Color(red: 0.37, green: 0.72, blue: 1.0)
    static let deepNavy = Color(red: 0.03, green: 0.06, blue: 0.16)
    static let deepIndigo = Color(red: 0.07, green: 0.08, blue: 0.23)
    static let cosmicPurple = Color(red: 0.16, green: 0.11, blue: 0.30)
    static let surface = Color.white.opacity(0.90)
    static let surfaceStrong = Color.white.opacity(0.95)
    // Backward-compatible aliases used by in-flight UI files.
    static let card = surface
    static let cardStrong = surfaceStrong
    static let border = Color.white.opacity(0.20)
}
