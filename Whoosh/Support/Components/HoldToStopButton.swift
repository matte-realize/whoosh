import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A red-tinted square **press-and-hold Stop** control for the active-ride
/// screen (Requirements 3.4 / 3.9, mockups 2/3).
///
/// Ending a ride requires an explicit ~1 second hold so an accidental bump can't
/// stop a ride. The fill rises from the bottom in step with how long the finger
/// has actually been down (`HoldProgress`), and drops back the moment it lifts.
/// Releasing before the threshold, or sliding off the control, cancels with
/// **no state change**; a quick tap only shows a brief "Hold to stop" hint.
/// Completing the hold fires `onStop` exactly once.
///
/// Accessibility: the control carries the label "Stop ride, press and hold" and
/// an `accessibilityAction(named: "Stop ride")` custom action that calls
/// `onStop` immediately, so VoiceOver users don't need the timed hold.
///
/// Haptics use plain `UIKit` feedback generators (a light impact at the start of
/// the hold, a success notification on completion) — these are ordinary UI
/// feedback, deliberately *not* the `AlertManager` safety-alert system.
struct HoldToStopButton: View {
    /// Called once when the hold completes (or the VoiceOver action fires).
    let onStop: () -> Void
    /// How long the user must hold before the ride stops.
    var holdDuration: TimeInterval = 1.0

    /// When the current press began; `nil` while not pressed.
    @State private var pressStart: Date?
    /// Set once the finger slides too far, so the rest of that drag is ignored.
    @State private var movedOff = false
    /// Guards against firing `onStop` more than once per press.
    @State private var didFire = false
    @State private var completionTask: Task<Void, Never>?
    @State private var showTapHint = false

    private let size: CGFloat = 78
    /// How far the finger may slide before the press counts as abandoned.
    private let maxDistance: CGFloat = 40
    /// Releases shorter than this read as a tap and show the hint.
    private let tapThreshold: TimeInterval = 0.3

    var body: some View {
        ZStack {
            // Base fill + red border (mockup: #2A1517 fill, #E5484D border).
            RoundedRectangle(cornerRadius: Theme.Radius.pill)
                .fill(Color(hex: 0x2A1517))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill)
                        .strokeBorder(Theme.Colors.recordingDot, lineWidth: 1.5)
                )

            // Hold progress, redrawn every frame only while pressed.
            TimelineView(.animation(paused: pressStart == nil)) { context in
                GeometryReader { geo in
                    Theme.Colors.recordingDot.opacity(0.35)
                        .frame(height: geo.size.height * fill(at: context.date))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill))

            VStack(spacing: Theme.Spacing.xs) {
                // Red stop square.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Colors.recordingDot)
                    .frame(width: 16, height: 16)
                Text("Hold")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF8A8D))
            }
        }
        .frame(width: size, height: Theme.Size.minTouchTarget)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.pill))
        .gesture(holdGesture)
        .overlay(alignment: .top) { tapHint }
        .onDisappear { completionTask?.cancel() }
        .accessibilityElement()
        .accessibilityLabel("Stop ride, press and hold")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Stop ride") {
            onStop()
        }
    }

    private func fill(at date: Date) -> CGFloat {
        CGFloat(HoldProgress.progress(pressStart: pressStart, now: date, holdDuration: holdDuration))
    }

    // MARK: - Gesture

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance > maxDistance {
                    if pressStart != nil {
                        movedOff = true
                        cancelHold(showHint: false)
                    }
                    return
                }
                if pressStart == nil, !movedOff, !didFire {
                    beginHold()
                }
            }
            .onEnded { _ in
                if pressStart != nil, !didFire {
                    let held = Date().timeIntervalSince(pressStart ?? Date())
                    cancelHold(showHint: held < tapThreshold)
                }
                movedOff = false
                didFire = false
            }
    }

    private func beginHold() {
        let start = Date()
        pressStart = start
        showTapHint = false
        impact()
        completionTask?.cancel()
        completionTask = Task {
            try? await Task.sleep(for: .seconds(holdDuration))
            // Only complete if this same press is still down and the hold is
            // genuinely full (an early release clears `pressStart`).
            guard !Task.isCancelled, pressStart == start,
                  HoldProgress.isComplete(pressStart: start, now: Date(), holdDuration: holdDuration)
            else { return }
            completeHold()
        }
    }

    private func completeHold() {
        guard pressStart != nil, !didFire else { return }
        didFire = true
        pressStart = nil
        success()
        onStop()
    }

    private func cancelHold(showHint: Bool) {
        completionTask?.cancel()
        completionTask = nil
        pressStart = nil
        if showHint { flashTapHint() }
    }

    private func flashTapHint() {
        showTapHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            showTapHint = false
        }
    }

    @ViewBuilder private var tapHint: some View {
        if showTapHint {
            Text("Hold to stop")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: 0x2A1517)))
                .offset(y: -26)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Haptics (plain UI feedback, not the alert system)

    private func impact() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    private func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}

#Preview("HoldToStopButton") {
    HoldToStopButton(onStop: {})
        .frame(width: 78, height: 60)
        .padding()
        .background(Theme.Colors.rideBackground)
}
