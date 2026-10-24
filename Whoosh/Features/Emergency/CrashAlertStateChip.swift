import SwiftUI

/// A small "Crash alerts on/off" status chip for Home and the active-ride
/// screen (spec Requirement 18.6). Always icon + text, never color alone; it
/// adds **no** fourth number to the ride screen.
///
/// The on/off mapping is a pure, testable value (`CrashAlertChipState`) so the
/// title and SF Symbol can be asserted in unit tests without rendering. The
/// chip reuses the ride screen's dark `Scheme` so it sits beside the existing
/// `StateChip`.
enum CrashAlertChipState: Equatable {
    case on
    case off

    init(isOn: Bool) {
        self = isOn ? .on : .off
    }

    var title: String {
        switch self {
        case .on: return "Crash alerts on"
        case .off: return "Crash alerts off"
        }
    }

    var systemImage: String {
        switch self {
        case .on: return "shield.lefthalf.filled"
        case .off: return "shield.slash"
        }
    }
}

/// The SwiftUI chip rendering a `CrashAlertChipState`. Light scheme for Home;
/// dark scheme for the ride screen (translucent ink fill + stroke), mirroring
/// `StateChip`.
struct CrashAlertStateChip: View {
    enum Scheme {
        case light
        case dark
    }

    let state: CrashAlertChipState
    var scheme: Scheme = .light

    init(isOn: Bool, scheme: Scheme = .light) {
        self.state = CrashAlertChipState(isOn: isOn)
        self.scheme = scheme
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: state.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(state.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(background)
        .clipShape(Capsule())
        .overlay(strokeOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.title))
    }

    // MARK: - Colors

    private var iconColor: Color {
        switch state {
        case .on:
            return Theme.Colors.positive
        case .off:
            return scheme == .dark ? Theme.Colors.rideSecondaryText : Theme.Colors.textSecondary
        }
    }

    private var textColor: Color {
        switch scheme {
        case .dark: return .white
        case .light: return Theme.Colors.textPrimary
        }
    }

    @ViewBuilder private var background: some View {
        switch scheme {
        case .dark: Theme.Colors.rideChipFill.opacity(0.88)
        case .light: Theme.Colors.subtleFill
        }
    }

    @ViewBuilder private var strokeOverlay: some View {
        if scheme == .dark {
            Capsule().stroke(Theme.Colors.rideChipStroke, lineWidth: 1)
        }
    }
}

#Preview("CrashAlertStateChip — light") {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        CrashAlertStateChip(isOn: true)
        CrashAlertStateChip(isOn: false)
    }
    .padding()
    .background(Theme.Colors.screenBackground)
}

#Preview("CrashAlertStateChip — dark ride") {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        CrashAlertStateChip(isOn: true, scheme: .dark)
        CrashAlertStateChip(isOn: false, scheme: .dark)
    }
    .padding()
    .background(Theme.Colors.rideBackground)
}
