import SwiftUI

/// The Whoosh design system (Requirement 15).
///
/// Defines the five brand color tokens — Ink `#0B0F14`, Lime `#C8F135`, Amber
/// `#F5A524`, Alert `#D32F2F`, Mist `#F4F5F7` — plus typography, spacing, and
/// corner-radius constants used across every screen. App chrome (Home, History,
/// Settings, Summary) uses the light theme; the active-ride screen is always
/// dark (Requirement 15.5).
///
/// Colors are defined in code (rather than an asset catalog) so the tokens live
/// in one reviewable place and can carry sensible light/dark variants via a
/// dynamic `UIColor` provider. The five brand hues are brand-constant; the
/// *semantic* roles (screen background, card surface, primary/secondary text)
/// adapt between light and dark. `Theme` is the only place hard-coded colors
/// appear; views reference these tokens.
enum Theme {
    // MARK: - Brand color tokens (constant hues)

    enum Palette {
        /// `#0B0F14` — near-black text / dark ride background.
        static let ink = Color(hex: 0x0B0F14)
        /// `#C8F135` — primary action (Start Ride, route polyline).
        static let lime = Color(hex: 0xC8F135)
        /// `#F5A524` — signal-lost / warning.
        static let amber = Color(hex: 0xF5A524)
        /// `#D32F2F` — destructive.
        static let alert = Color(hex: 0xD32F2F)
        /// `#F4F5F7` — light chrome background.
        static let mist = Color(hex: 0xF4F5F7)
    }

    // MARK: - Semantic colors (adapt light/dark for app chrome)

    enum Colors {
        /// Screen background for light app chrome. Mist in light, Ink in dark.
        static let screenBackground = Color(
            light: 0xF4F5F7, dark: 0x0B0F14
        )
        /// Card / surface color. White in light, an elevated dark in dark mode.
        static let cardSurface = Color(
            light: 0xFFFFFF, dark: 0x11161D
        )
        /// A subtly recessed fill (step chips, chart baseline). 
        static let subtleFill = Color(
            light: 0xF4F5F7, dark: 0x1F2833
        )
        /// Hairline separators inside cards.
        static let separator = Color(
            light: 0xEEF0F3, dark: 0x2A3542
        )
        /// Primary text (near-black on light, near-white on dark).
        static let textPrimary = Color(
            light: 0x0B0F14, dark: 0xF4F5F7
        )
        /// Secondary / caption text.
        static let textSecondary = Color(
            light: 0x5B6472, dark: 0x8A94A3
        )
        /// Positive / ready indicator dot (GPS ready).
        static let positive = Color(hex: 0x2FB344)

        // Fixed dark-screen tokens (the ride screen is always dark, so these do
        // not adapt). Kept here so the ride UI uses named tokens, not literals.
        static let rideBackground = Color(hex: 0x0B0F14)
        static let rideCard = Color(hex: 0x11161D)
        static let rideChipFill = Color(hex: 0x0B0F14)
        static let rideChipStroke = Color(hex: 0x2A3542)
        static let rideSecondaryText = Color(hex: 0x8A94A3)
        static let recordingDot = Color(hex: 0xE5484D)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner radius

    enum Radius {
        static let chip: CGFloat = 13
        static let card: CGFloat = 16
        static let largeCard: CGFloat = 18
        /// Pill controls (Start Ride, Done). Half of a ≥60pt height reads as a pill.
        static let pill: CGFloat = 33
    }

    // MARK: - Sizing

    enum Size {
        /// Minimum touch target for primary controls, per the thumb-zone
        /// principle (Requirements 10.6 / 15.4).
        static let minTouchTarget: CGFloat = 60
    }

    // MARK: - Typography

    enum Typography {
        /// A large, bold, tabular (monospaced-digit) numeral for ride metrics so
        /// values don't jitter as they update (Requirement 15.2).
        static func metric(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold).monospacedDigit()
        }

        /// Screen title (e.g. "Settings", "Ride complete").
        static let title = Font.system(size: 22, weight: .bold)
        /// Section header (small, uppercase, tracked).
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        /// Standard body text.
        static let body = Font.system(size: 15)
        /// Row title inside cards.
        static let rowTitle = Font.system(size: 15, weight: .semibold)
        /// Caption / subtitle.
        static let caption = Font.system(size: 12)
    }
}
