import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A red-tinted square **press-and-hold Stop** control for the active-ride
/// screen (Requirements 3.4 / 3.9, mockups 2/3).
///
/// Ending a ride requires an explicit ~1 second hold so an accidental bump can't
/// stop a ride. A linear progress fill rises from the bottom while the gesture
/// is in flight; releasing before the threshold cancels with **no state change**
/// (the ride keeps recording). A quick tap does nothing but briefly shows a
/// "Hold to stop" hint. Completing the hold fires `onStop` exactly once.
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

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var showTapHint = false
    /// Guards against firing `onStop` more than once per hold.
    @State private var didFire = false

    private let size: CGFloat = 78

    var body: some View {
        ZStack {
            // Base fill + red border (mockup: #2A1517 fill, #E5484D border).
            RoundedRectangle(cornerRadius: Theme.Radius.pill)
                .fill(Color(hex: 0x2A1517))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill)
                        .strokeBorder(Theme.Colors.recordingDot, lineWidth: 1.5)
                )

            // Hold progress: a lime-tinted fill rising from the bottom.
            GeometryReader { geo in
                Theme.Colors.recordingDot.opacity(0.35)
                    .frame(height: geo.size.height * progress)
                    .frame(maxHeight: .infinity, alignment: .bottom)
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
        .accessibilityElement()
        .accessibilityLabel("Stop ride, press and hold")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Stop ride") {
            onStop()
        }
    }

    // MARK: - Gesture

    private var holdGesture: some Gesture {
        // A long-press gesture drives start/cancel; an animated progress fill
        // runs for `holdDuration`, and a timer fires completion. Using the
        // gesture's `onEnded`/pressing state keeps early-release a clean cancel.
        LongPressGesture(minimumDuration: holdDuration, maximumDistance: 40)
            .onEnded { _ in
                complete()
            }
            .simultaneously(with:
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding { beginHold() }
                    }
                    .onEnded { _ in
                        // Released: if the hold hadn't completed, cancel it.
                        if !didFire { cancelHold() }
                    }
            )
    }

    private func beginHold() {
        isHolding = true
        didFire = false
        showTapHint = false
        impact()
        withAnimation(.linear(duration: holdDuration)) {
            progress = 1
        }
    }

    private func complete() {
        guard isHolding, !didFire else { return }
        didFire = true
        isHolding = false
        success()
        onStop()
        // Reset the fill after firing.
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }

    private func cancelHold() {
        // Early release before the threshold: cancel, no state change.
        let completed = progress >= 1
        isHolding = false
        if !completed {
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            // A very short press reads as a tap: show a brief hint.
            flashTapHint()
        }
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
