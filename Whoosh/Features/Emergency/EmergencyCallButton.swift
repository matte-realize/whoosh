import SwiftUI

/// The rider-tapped **"Call 911"** control (spec Requirement 17.2, design
/// "Countdown/Status screens"). This is the **only** place in the app that
/// constructs a `tel:` URL (privacy-check rule 8), and it opens the dialer
/// **only when the rider taps it** — iOS then shows its own call confirmation.
///
/// Whoosh never calls or texts emergency services automatically under any state
/// or error (Requirement 17.1). This control is hidden for drills by its callers
/// (`CrashCountdownView`, `CrashAlertStatusView`), which render an inert "Demo"
/// tag instead so no accidental real 911 call can happen during the demo
/// (Requirement 17.3).
///
/// It intentionally carries no automatic path and no completion side effects: it
/// requests the system to open the dialer and nothing else.
struct EmergencyCallButton: View {
    /// Visual style for the surface the button sits on.
    enum Style {
        /// On the red countdown takeover (white outline on red).
        case countdown
        /// On the light status screen (alert-red outline on white).
        case status
    }

    var style: Style = .status
    /// The number to dial; `911` by default. Injectable for previews/tests.
    var number: String = "911"

    var body: some View {
        Button(action: placeCall) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Call 911")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.minTouchTarget)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(strokeColor, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call 911")
        .accessibilityHint("Opens your phone's dialer. You confirm the call.")
    }

    /// Open the system dialer for `number`. iOS presents its own call
    /// confirmation; this never dials without the rider's confirmation.
    private func placeCall() {
        guard let url = URL(string: "tel://\(number)") else { return }
        UIApplication.shared.open(url)
    }

    private var foreground: Color {
        switch style {
        case .countdown: return .white
        case .status: return Theme.Palette.alert
        }
    }

    private var strokeColor: Color {
        switch style {
        case .countdown: return .white.opacity(0.7)
        case .status: return Theme.Palette.alert.opacity(0.6)
        }
    }
}

#Preview("Call 911 — status") {
    EmergencyCallButton(style: .status)
        .padding()
        .background(Theme.Colors.screenBackground)
}
