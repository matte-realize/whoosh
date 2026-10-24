import SwiftUI

/// A compact status chip that always conveys state with **icon + text**, never
/// color alone (Requirements 10.5 / 15.3). Used for ride state, GPS readiness,
/// the inert rear-detection placeholder, and sync status.
///
/// Each variant pairs an SF Symbol with a label and supplies its own fill /
/// foreground so callers just pick a case. A single accessibility label reads
/// the combined meaning aloud.
struct StateChip: View {
    enum Variant {
        case recording
        case paused
        case signalLost
        case gpsReady
        case rearDetectionOff
        case synced
        case pending
        case onDevice

        var title: String {
            switch self {
            case .recording: return "Recording"
            case .paused: return "Paused"
            case .signalLost: return "Signal lost"
            case .gpsReady: return "GPS ready"
            case .rearDetectionOff: return "Rear detection off"
            case .synced: return "Synced"
            case .pending: return "Pending"
            case .onDevice: return "On device"
            }
        }

        var systemImage: String {
            switch self {
            case .recording: return "record.circle.fill"
            case .paused: return "pause.circle.fill"
            case .signalLost: return "exclamationmark.triangle.fill"
            case .gpsReady: return "dot.radiowaves.left.and.right"
            case .rearDetectionOff: return "eye.slash"
            case .synced: return "checkmark.icloud"
            case .pending: return "clock"
            case .onDevice: return "iphone"
            }
        }
    }

    enum Scheme {
        /// Chip tuned for light app chrome.
        case light
        /// Chip tuned for the dark ride screen (translucent ink fill, stroke).
        case dark
    }

    let variant: Variant
    var scheme: Scheme = .light

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: variant.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(variant.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(background)
        .clipShape(Capsule())
        .overlay(strokeOverlay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(variant.title))
    }

    // MARK: - Colors

    private var iconColor: Color {
        switch variant {
        case .recording: return Theme.Colors.recordingDot
        case .paused: return scheme == .dark ? Theme.Colors.rideSecondaryText : Theme.Colors.textPrimary
        case .signalLost: return Theme.Palette.ink
        case .gpsReady: return Theme.Colors.positive
        case .rearDetectionOff: return Theme.Colors.rideSecondaryText
        case .synced: return Theme.Colors.positive
        case .pending: return Theme.Palette.amber
        case .onDevice: return Theme.Colors.textSecondary
        }
    }

    private var textColor: Color {
        switch variant {
        case .signalLost:
            return Theme.Palette.ink
        default:
            switch scheme {
            case .dark: return .white
            case .light: return Theme.Colors.textPrimary
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch variant {
        case .signalLost:
            Theme.Palette.amber
        default:
            switch scheme {
            case .dark: Theme.Colors.rideChipFill.opacity(0.88)
            case .light: Theme.Colors.subtleFill
            }
        }
    }

    @ViewBuilder private var strokeOverlay: some View {
        if scheme == .dark, variant != .signalLost {
            Capsule().stroke(Theme.Colors.rideChipStroke, lineWidth: 1)
        }
    }
}

#Preview("StateChip — light") {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        StateChip(variant: .gpsReady)
        StateChip(variant: .synced)
        StateChip(variant: .pending)
        StateChip(variant: .onDevice)
        StateChip(variant: .signalLost)
    }
    .padding()
    .background(Theme.Colors.screenBackground)
}

#Preview("StateChip — dark ride") {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        StateChip(variant: .recording, scheme: .dark)
        StateChip(variant: .paused, scheme: .dark)
        StateChip(variant: .rearDetectionOff, scheme: .dark)
    }
    .padding()
    .background(Theme.Colors.rideBackground)
}
