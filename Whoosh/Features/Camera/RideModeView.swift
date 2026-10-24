import SwiftUI

/// The ride-mode overlay: a true-black, minimum-brightness, touch-locked screen
/// that makes a rear-mounted phone "look off" while the camera and GPS run
/// (rear-camera spec Requirement 10, task 21, design "Ride mode"). It sits above
/// the active-ride content inside the existing non-dismissible ride cover and is
/// a thin view over the `RideModeController`'s read-only state — all logic lives
/// in the controller and the pure `ScreenModeStateMachine`.
///
/// Surfaces, and nothing else:
/// - a **mount-grace** countdown with "Dim now" and "Keep screen on" while the
///   rider clips the phone on;
/// - once dimmed, a solid-black screen with only a small **recording dot** (red,
///   or an amber ring when the camera/GPS is in trouble) that shifts a few
///   points every 60 s to protect the OLED;
/// - a full-screen **touch lock** that ignores incidental touches; the only
///   recognised gesture is a **two-finger long press** (1.0 s) that unlocks;
/// - a VoiceOver-friendly single element with a custom **Unlock controls**
///   action, so a non-visual rider can unlock without the gesture;
/// - very dim, transient **toasts** ("Clip saved" / "Couldn't save clip").
///
/// Honesty (privacy steering): dimming saves power and is never described as
/// hiding the camera; the recording dot stays visible and no system
/// camera/location indicator is hidden or imitated.
struct RideModeView: View {
    /// The ride-mode controller (read-only state + intents).
    @Bindable var controller: RideModeController

    /// Drives the OLED-protecting dot shift (toggles every `redDotShiftPeriod`).
    @State private var dotShifted = false

    var body: some View {
        ZStack {
            // True black; ignores safe areas and hides system chrome.
            Color.black.ignoresSafeArea()

            switch controller.mode {
            case .graceCountdown:
                graceCountdown
            case .dimLocked:
                lockedScreen
            case .unlockedTemporarily:
                // Controls are owned by the active-ride screen underneath; the
                // overlay only needs to let touches through while unlocked, so
                // it renders just the dot (kept visible, Requirement 10.6).
                recordingDot
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Theme.Spacing.lg)
                    .allowsHitTesting(false)
            case .normal, .suspended:
                EmptyView()
            }

            toastOverlay
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Mount grace

    private var graceCountdown: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "bicycle")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Mount your phone")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("The screen dims so the phone looks off while the camera and GPS keep running. Recording is for your own records.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
            if let deadline = controller.graceDeadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                    Text("Dimming in \(remaining)s")
                        .font(Theme.Typography.metric(40))
                        .foregroundStyle(.white)
                        .accessibilityLabel("Dimming in \(remaining) seconds")
                }
            }
            Spacer()
            VStack(spacing: Theme.Spacing.md) {
                Button {
                    controller.dimNow()
                } label: {
                    Text("Dim now")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.minTouchTarget)
                        .background(Theme.Palette.lime)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Dims and locks the screen now.")

                Button {
                    controller.keepScreenOn()
                } label: {
                    Text("Keep screen on")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.minTouchTarget)
                        .overlay(
                            Capsule().stroke(.white.opacity(0.6), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Keeps the normal ride screen for this ride.")
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - Locked (dimmed) screen

    private var lockedScreen: some View {
        ZStack {
            // A full-screen touch-absorbing layer whose only recognised gesture
            // is a deliberate two-finger long press (incidental touches ignored).
            TwoFingerLongPressLock(minimumDuration: controller.unlockHoldDuration) {
                controller.twoFingerHoldCompleted()
            }
            .ignoresSafeArea()

            recordingDot
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(Theme.Spacing.lg)
                .allowsHitTesting(false)
        }
        // One VoiceOver element with a custom unlock action so a non-visual
        // rider can unlock without the gesture (Requirement 10.7).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride mode. Camera recording. Screen locked.")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: Text("Unlock controls")) {
            controller.accessibilityUnlock()
        }
    }

    // MARK: - Recording dot

    /// The small recording/detection indicator: a filled red circle while
    /// recording, an amber ring while in trouble. Never hidden; shifts a few
    /// points every `redDotShiftPeriod` to protect the OLED.
    private var recordingDot: some View {
        Group {
            if controller.isTrouble {
                Circle()
                    .stroke(Theme.Palette.amber, lineWidth: 3)
                    .frame(width: 14, height: 14)
                    .accessibilityLabel("Camera attention needed")
            } else {
                Circle()
                    .fill(Theme.Palette.alert)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Recording")
            }
        }
        .offset(x: dotShifted ? -6 : 0, y: dotShifted ? 6 : 0)
        .animation(.easeInOut(duration: 1), value: dotShifted)
        .onReceive(
            Timer.publish(
                every: controller.redDotShiftPeriod,
                on: .main,
                in: .common
            ).autoconnect()
        ) { _ in
            dotShifted.toggle()
        }
    }

    // MARK: - Toasts

    @ViewBuilder private var toastOverlay: some View {
        if let toast = controller.toast {
            VStack {
                Spacer()
                Text(toast.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, Theme.Spacing.xl)
                    .accessibilityLabel(toast.text)
            }
            .transition(.opacity)
            .task {
                // Fade the toast after ~2 s (design "Ride mode").
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                controller.clearToast()
            }
        }
    }
}
