import SwiftUI

/// The full-screen **crash-countdown takeover** (spec Requirement 8, design
/// "Countdown screen", crash-response task 20). It appears above every other
/// screen while a crash event is in `countdown`, shows a very large remaining-
/// seconds numeral, an honest sentence naming the contacts, and a prominent
/// one-tap "I'm OK — Cancel" control at least 80 pt tall in the thumb zone. A
/// separate, distant "Send now" skips the wait; a clearly secondary manual
/// "Call 911" is shown only for real events (hidden for drills, Requirement
/// 17.3).
///
/// A thin view over the `CrashResponseCoordinator`'s read-only state; all logic
/// lives in the coordinator and the pure reducer. The view:
/// - keeps the screen awake while visible (idle timer disabled);
/// - is **modal** for accessibility so VoiceOver focus stays on the takeover
///   and it cannot be swiped away;
/// - is **flashing-safe**: at most one slow luminance pulse per second, and a
///   static high-contrast state when Reduce Motion is on (Requirement 8.6);
/// - posts VoiceOver announcements at the start, every 10 s, and the last 5 s
///   via the pure `CountdownAnnouncementSchedule` (Requirement 18.3).
///
/// Honest copy only: the screen never claims a confirmed crash, never promises
/// delivery, and states Whoosh cannot guarantee detection or delivery and does
/// not contact emergency services (Requirement 1.1/1.3).
struct CrashCountdownView: View {
    let coordinator: CrashResponseCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Drives the once-per-second pulse (disabled under Reduce Motion).
    @State private var pulsed = false
    /// The last `remaining` value we announced, so we announce each mark once.
    @State private var lastAnnounced: Int?

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                header
                numeral
                sentence
                Spacer(minLength: Theme.Spacing.lg)
                controls
                finePrint
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Modal: VoiceOver focus is trapped on the takeover (Requirement 18.3).
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        // Keep the screen awake for the duration (Requirement 8.8 / 13.4).
        .onAppear {
            KeepAwake.shared.acquire(.crashCountdown)
            announceIfNeeded()
            startPulse()
        }
        .onDisappear {
            KeepAwake.shared.release(.crashCountdown)
        }
        // Re-announce on each per-second change of the remaining value.
        .onChange(of: coordinator.remainingSeconds) { _, _ in
            announceIfNeeded()
            pulseOnce()
        }
    }

    // MARK: - Background (flashing-safe)

    @ViewBuilder private var background: some View {
        if reduceMotion {
            // Static high-contrast state; no flashing (Requirement 8.6).
            Theme.Palette.alert
        } else {
            // At most one slow luminance change per second.
            Theme.Palette.alert
                .brightness(pulsed ? 0.04 : 0.0)
                .animation(.easeInOut(duration: 0.5), value: pulsed)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .bold))
            Text(coordinator.isDrill ? "Demo — not real" : "Crash detected")
                .font(.system(size: 26, weight: .bold))
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(coordinator.isDrill ? "Demo, not real" : "Crash detected")
    }

    // MARK: - Numeral (fixed large scale, tabular)

    private var numeral: some View {
        Text("\(coordinator.remainingSeconds ?? 0)")
            .font(Theme.Typography.metric(120))
            .foregroundStyle(.white)
            // Fixed scale (like ride metrics): does not grow with Dynamic Type.
            .accessibilityLabel("\(coordinator.remainingSeconds ?? 0) seconds remaining")
    }

    // MARK: - Sentence (names the contacts; scales with Dynamic Type)

    private var sentence: some View {
        Text(sentenceText)
            .font(.system(size: 20, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(sentenceText)
    }

    private var sentenceText: String {
        let seconds = coordinator.remainingSeconds ?? 0
        let names = contactListText
        let verb = coordinator.isDrill ? "Sending a demo alert" : "Sending an alert"
        if names.isEmpty {
            return "\(verb) in \(seconds) seconds."
        }
        return "\(verb) to \(names) in \(seconds) seconds."
    }

    /// "Mom", "Mom and Sam", or "Mom and 2 others" (truncated to fit).
    private var contactListText: String {
        let labels = coordinator.recipients.map(\.label)
        switch labels.count {
        case 0: return ""
        case 1: return labels[0]
        case 2: return "\(labels[0]) and \(labels[1])"
        default: return "\(labels[0]) and \(labels.count - 1) others"
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Theme.Spacing.lg) {
            cancelButton
            HStack(spacing: Theme.Spacing.lg) {
                sendNowButton
                if !coordinator.isDrill {
                    callButton
                } else {
                    demoTag
                }
            }
        }
    }

    /// The primary "I'm OK — Cancel": full width, ≥ 80 pt tall, single tap,
    /// bottom thumb zone (Requirement 8.3/8.4).
    private var cancelButton: some View {
        Button {
            coordinator.riderCancel()
        } label: {
            Text("I'm OK — Cancel")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Theme.Palette.alert)
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I'm OK. Cancel the alert.")
        .accessibilityHint("Stops the countdown and sends nothing.")
        .accessibilityAddTraits(.isButton)
    }

    /// Secondary "Send now", placed away from Cancel (Requirement 8.9).
    private var sendNowButton: some View {
        Button {
            coordinator.sendNow()
        } label: {
            Text("Send now")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.minTouchTarget)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .stroke(.white.opacity(0.7), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send the alert now")
        .accessibilityHint("Skips the remaining wait and sends immediately.")
    }

    /// The manual, rider-tapped "Call 911" control (Requirement 17.2). Hidden
    /// for drills; `EmergencyCallButton` is the only `tel:` path in the app.
    private var callButton: some View {
        EmergencyCallButton(style: .countdown)
            .frame(maxWidth: .infinity)
    }

    /// An inert "Demo" tag shown instead of Call 911 during a drill
    /// (Requirement 17.3) so no accidental real 911 call can happen.
    private var demoTag: some View {
        Text("Demo")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.minTouchTarget)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(.white.opacity(0.4), lineWidth: 1.5)
            )
            .accessibilityLabel("Demo. Call 911 is disabled during a demo.")
    }

    // MARK: - Fine print (honest copy)

    private var finePrint: some View {
        Text("Whoosh is not a guaranteed emergency service. It can't guarantee detection or delivery. It does not contact emergency services.")
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pulse (flashing-safe)

    private func startPulse() {
        guard !reduceMotion else { return }
        pulsed = true
    }

    private func pulseOnce() {
        guard !reduceMotion else { return }
        pulsed.toggle()
    }

    // MARK: - VoiceOver announcements

    private func announceIfNeeded() {
        guard let total = coordinator.totalCountdownSeconds,
              let remaining = coordinator.remainingSeconds else { return }
        let schedule = CountdownAnnouncementSchedule(totalSeconds: total)
        guard schedule.shouldAnnounce(remaining: remaining),
              lastAnnounced != remaining,
              let text = schedule.announcement(remaining: remaining) else { return }
        lastAnnounced = remaining
        AccessibilityNotification.Announcement(text).post()
    }
}
