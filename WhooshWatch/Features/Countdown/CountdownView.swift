import SwiftUI
import WhooshWire

/// The crash-countdown takeover (watch-companion design "Pages → a
/// crash/countdown takeover appears above everything"). A minimal version for
/// the demo drill (the full flow, backup notification, and retries are task 21):
/// relative remaining seconds, a count-only sentence, a large "I'm OK — Cancel"
/// (≥ 80 pt), a DEMO label for drills, and a short honest disclaimer. Reduce
/// Motion keeps it static.
///
/// Honest copy: Whoosh is not a guaranteed emergency-response service; it cannot
/// guarantee detection or delivery and does not contact emergency services.
struct CountdownView: View {
    let model: WatchSessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if model.countdownIsDrill {
                Text("DEMO — NOT REAL")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(WatchTheme.amber, in: Capsule())
            }

            Text("\(model.countdownSeconds)")
                .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .accessibilityLabel("\(model.countdownSeconds) seconds")

            Text(sentence)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))

            Button {
                model.cancelCountdown()
            } label: {
                Text("I'm OK — Cancel")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.cancelTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(WatchTheme.alert)
            .accessibilityHint("Cancels the alert")

            Text("Whoosh cannot guarantee detection or delivery and does not contact emergency services.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.alert)
        .animation(reduceMotion ? nil : .default, value: model.countdownSeconds)
    }

    private var sentence: String {
        let n = model.countdownContactCount
        let contacts = n == 1 ? "1 contact" : "\(n) contacts"
        switch model.countdownPhase {
        case .cancelling: return "Cancelling…"
        case .cancelled: return "Cancelled"
        case .tooLate, .sending, .sent, .queued: return "Alert is sending to \(contacts)"
        case .failed: return "Could not cancel"
        default:
            return "A possible crash was detected. If not cancelled, Whoosh will text \(contacts)."
        }
    }
}

#Preview("Crash drill") {
    CountdownView(model: WatchDemo.makeModel(scenario: .crashDrill))
}
