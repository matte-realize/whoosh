import SwiftUI

/// Maps a `ContactVerification` to an **icon + text** presentation (never color
/// alone, Requirement 2.5 / 18.3). Used by the contact editor, the setup hub,
/// and anywhere a contact's reachability is shown.
///
/// The pure `title`/`systemImage` mapping is also reachable without SwiftUI via
/// the static helpers, so it can be asserted in unit tests.
struct ContactVerificationDisplay {
    let verification: ContactVerification

    init(_ verification: ContactVerification) {
        self.verification = verification
    }

    var title: String { Self.title(for: verification) }
    var systemImage: String { Self.systemImage(for: verification) }

    /// A tint for the icon. Text always accompanies it, so color is decorative.
    var tint: Color {
        switch verification {
        case .reachable:
            return Theme.Colors.positive
        case .unverified, .introSent:
            return Theme.Colors.textSecondary
        case .undeliverable, .optedOut:
            return Theme.Palette.alert
        }
    }

    /// Plain, honest label for each verification state (Requirement 2.5).
    static func title(for verification: ContactVerification) -> String {
        switch verification {
        case .unverified: return "Not verified yet"
        case .introSent: return "Intro sent"
        case .reachable: return "Reachable"
        case .undeliverable: return "Couldn't reach"
        case .optedOut: return "Opted out"
        }
    }

    static func systemImage(for verification: ContactVerification) -> String {
        switch verification {
        case .unverified: return "questionmark.circle"
        case .introSent: return "paperplane"
        case .reachable: return "checkmark.circle.fill"
        case .undeliverable: return "exclamationmark.triangle.fill"
        case .optedOut: return "hand.raised.fill"
        }
    }
}
