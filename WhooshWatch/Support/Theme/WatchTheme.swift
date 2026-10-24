import SwiftUI

/// Brand tokens for the watch companion (watch-companion design "Pages →
/// Brand tokens": Ink background, Lime primary action, Amber warning, Alert red
/// for the countdown only, Mist text). Kept small and watch-specific; the phone
/// app owns its own theme. Reduced-luminance (Always-On) shows elapsed time and
/// state glyphs only, so warning/alert colors are used sparingly.
enum WatchTheme {
    /// True-black background (OLED, reduced-luminance friendly).
    static let ink = Color.black
    /// Primary action (start / resume / confirm).
    static let lime = Color(red: 0.72, green: 0.95, blue: 0.20)
    /// Warning: signal lost, camera trouble, battery.
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.20)
    /// Alert red — the crash countdown only.
    static let alert = Color(red: 0.95, green: 0.26, blue: 0.21)
    /// Primary text.
    static let mist = Color(red: 0.90, green: 0.93, blue: 0.95)
    /// Secondary / dimmed text.
    static let mistDim = Color(red: 0.62, green: 0.66, blue: 0.70)

    /// Minimum thumb target for watch controls (design: ≥ 60 pt).
    static let minTarget: CGFloat = 60
    /// Minimum crash-cancel target (design: ≥ 80 pt).
    static let cancelTarget: CGFloat = 80
}

extension Font {
    /// The large tabular elapsed-time face (fixed scale so digits don't jump).
    static var watchMetricLarge: Font {
        .system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()
    }
    /// The secondary metric face (distance / speed).
    static var watchMetric: Font {
        .system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    }
}
