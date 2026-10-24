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

    /// The in-ride controls shown while temporarily unlocked (big Stop,
    /// Pause/Resume, Save clip). `nil` in previews/tests that only exercise the
    /// dim/lock visuals; the ride can then still be stopped by unlocking to the
    /// active-ride screen underneath. Owner device-testing feedback: a ride must
    /// always be stoppable from ride mode.
    var controls: RideModeControls?

    /// Drives the OLED-protecting dot shift (toggles every `redDotShiftPeriod`).
    @State private var dotShifted = false

    /// Whether the ride-mode overlay is in its unlocked (controls-visible) state.
    private var isUnlocked: Bool {
        if case .unlockedTemporarily = controller.mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            // True black while dimmed/locked so the phone "looks off". While
            // temporarily unlocked, a lighter scrim lets the rider read the big
            // Stop / Pause / Save controls (owner feedback).
            (isUnlocked ? Color.black.opacity(0.82) : Color.black)
                .ignoresSafeArea()

            switch controller.mode {
            case .graceCountdown:
                graceCountdown
            case .dimLocked:
                lockedScreen
            case .unlockedTemporarily:
                // The big in-ride controls (Stop / Pause / Save). A ride must
                // always be stoppable from ride mode (owner feedback). The dot
                // stays visible. Any touch here extends the unlock window.
                unlockedControls
                    .contentShape(Rectangle())
                    .onTapGesture { controller.touchActivity() }
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
            // A full-screen touch-absorbing layer whose only recognised gestures
            // are deliberate one- or two-finger long presses (incidental touches
            // ignored). One finger is enough once the phone is in hand; two
            // fingers still works as before.
            RideModeUnlockLock(minimumDuration: controller.unlockHoldDuration) {
                controller.twoFingerHoldCompleted()
            }
            .ignoresSafeArea()

            // Always-visible, faint unlock hint so a rider who picks the phone up
            // mid-ride always sees how to stop (owner device-testing feedback).
            // Brightens while a pickup is detected (the controller raises
            // brightness and sets this flag) so it is readable the moment the
            // phone is lifted.
            unlockHint

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

    /// The faint, always-visible "Press and hold to unlock" hint on the black
    /// locked screen. Normally very dim (OLED-friendly, unobtrusive); it
    /// brightens and enlarges while the controller reports a pickup so the rider
    /// can see how to stop the moment they lift the phone.
    private var unlockHint: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Spacer()
            Image(systemName: "hand.tap.fill")
                .font(.system(size: controller.isPickupPrompting ? 30 : 20, weight: .semibold))
            Text("Press and hold to unlock")
                .font(.system(size: controller.isPickupPrompting ? 17 : 13, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.white.opacity(controller.isPickupPrompting ? 0.9 : 0.18))
        .animation(.easeInOut(duration: 0.3), value: controller.isPickupPrompting)
        .allowsHitTesting(false)
        .accessibilityHidden(true) // the accessibility unlock action is on the lock
    }

    // MARK: - Unlocked controls

    /// The big, eyes-on controls shown while temporarily unlocked: a huge Stop
    /// (press-and-hold so a ride is never ended by accident), Pause/Resume, and
    /// Save clip. Reuses `HoldToStopButton`. When no `controls` are injected
    /// (previews) it shows a short hint instead.
    @ViewBuilder private var unlockedControls: some View {
        if let controls {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                Text("Ride controls")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                // Big press-and-hold Stop so the ride is always stoppable here.
                HoldToStopButton(onStop: controls.onStop)
                    .frame(width: 220, height: 64)

                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        controller.touchActivity()
                        controls.onTogglePause()
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: controls.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 17, weight: .bold))
                            Text(controls.isPaused ? "Resume" : "Pause")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.minTouchTarget)
                        .background(Theme.Palette.lime)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(controls.isPaused ? "Resume ride" : "Pause ride")

                    if let onSaveClip = controls.onSaveClip {
                        Button {
                            controller.touchActivity()
                            _ = onSaveClip()
                        } label: {
                            Label("Save clip", systemImage: "bookmark.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: Theme.Size.minTouchTarget)
                                .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save clip")
                        .accessibilityHint("Saves a clip of the last moments to this phone.")
                    }
                }
                .frame(maxWidth: 360)

                Text("Locks again after a few seconds")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else {
            VStack {
                Spacer()
                Text("Unlocked")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
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
