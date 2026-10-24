import SwiftUI

/// The primary lime action button (Requirement 15.3).
///
/// A full-width lime pill at least 60pt tall so it sits comfortably in the
/// one-handed thumb zone with a large touch target (Requirements 10.6 / 15.4).
/// Supports an optional leading SF Symbol and a secondary (outline) style for
/// the lower-emphasis action beneath it (e.g. "View past rides").
struct PrimaryButton: View {
    enum Style {
        /// Solid lime fill with ink text — the main action.
        case primary
        /// Transparent with ink text — a secondary action.
        case secondary
    }

    let title: String
    var systemImage: String?
    var style: Style = .primary
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.minTouchTarget)
            .background(background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        switch style {
        case .primary: return Theme.Palette.ink
        case .secondary: return Theme.Colors.textPrimary
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary:
            Theme.Palette.lime
        case .secondary:
            Color.clear
        }
    }
}

#Preview("PrimaryButton") {
    VStack(spacing: Theme.Spacing.lg) {
        PrimaryButton("Start Ride", systemImage: "play.fill") {}
        PrimaryButton("Open Settings") {}
        PrimaryButton("View past rides", style: .secondary) {}
    }
    .padding()
    .background(Theme.Colors.screenBackground)
}
