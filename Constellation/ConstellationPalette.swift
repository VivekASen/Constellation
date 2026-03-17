import SwiftUI
import UIKit

enum ConstellationPalette {
    static let accent = Color(red: 0.22, green: 0.57, blue: 1.0)
    static let accentSoft = Color(red: 0.37, green: 0.72, blue: 1.0)
    static let deepNavy = Color(red: 0.03, green: 0.06, blue: 0.16)
    static let deepIndigo = Color(red: 0.07, green: 0.08, blue: 0.23)
    static let cosmicPurple = Color(red: 0.16, green: 0.11, blue: 0.30)
    static let surface = Color(uiColor: UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.10)
        }
        return UIColor.white.withAlphaComponent(0.90)
    })
    static let surfaceStrong = Color(uiColor: UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.14)
        }
        return UIColor.white.withAlphaComponent(0.95)
    })
    // Backward-compatible aliases used by in-flight UI files.
    static let card = surface
    static let cardStrong = surfaceStrong
    static let border = Color(uiColor: UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.28)
        }
        return UIColor.white.withAlphaComponent(0.20)
    })
}
