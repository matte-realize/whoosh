import Foundation
import Observation

/// The ride-mode controller: an `@Observable`, main-actor object that
/// **composes** the pure `ScreenModeStateMachine` reducer and `BrightnessGuard`
/// with the injected `ScreenController`, `DimGuardStore`, and `Clock`
/// (rear-camera spec Requirement 10, task 21). It never reimplements the
/// transition logic: it feeds `ScreenModeEvent`s to the reducer, then executes
/// the returned **effects-as-data** against the real screen controller and the
/// persisted dim guard — the same pattern as `CrashResponseCoordinator`.
///
/// It owns the two ride-mode timers through the `Clock` seam (so tests drive
/// them deterministically with a `TestClock`):
/// - the **mount-grace** countdown (`ScreenMode.graceCountdown`) fires
///   `graceElapsed` at its deadline;
/// - the **unlock-inactivity** window (`ScreenMode.unlockedTemporarily`) fires
///   `unlockDeadlineReached` at its deadline, re-dimming and re-locking.
///
/// ## Honesty / safety invariants (privacy steering, design "Ride mode")
/// - Dimming saves power; it never hides the red recording dot and never
///   imitates a system indicator — that is the `RideModeView`'s job.
/// - Every exit path (unlock, resign-active, ride end, launch guard) restores
///   the rider's original brightness and clears the persisted guard, so the
///   phone is never left dim.
@Observable
@MainActor
final class RideModeController {
    // MARK: Injected seams

    @ObservationIgnored private let screen: ScreenController
    @ObservationIgnored private let dimGuardStore: DimGuardStore
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let tuning: RideCameraTuning
    @ObservationIgnored private let isRideActive: () -> Bool
    @ObservationIgnored private let isRideModeEnabled: () -> Bool

    // MARK: Observable, read-only state for the view

    /// The current ride-mode screen state (read-only to the UI).
    private(set) var mode: ScreenMode = .normal
    /// Whether the full-screen touch lock is active (only the two-finger unlock
    /// is recognised).
    private(set) var isTouchLocked = false
    /// Whether the unlocked ride controls (Pause/Resume, Save clip, Hold-to-Stop)
    /// should be shown.
    private(set) var isShowingControls = false
    /// Whether the dim overlay is presented (grace or any dimmed/locked state).
    /// The view shows the true-black overlay whenever this is true.
    var isOverlayPresented: Bool {
        switch mode {
        case .normal, .suspended:
            return false
        case .graceCountdown, .dimLocked, .unlockedTemporarily:
            return true
        }
    }
    /// Whether the camera/GPS is in a trouble state (interrupted, stopped,
    /// failed, or signal lost), so the view shows the amber dot instead of red.
    /// Set by the owning coordinator; never hidden.
    private(set) var isTrouble = false
    /// The last transient toast to surface (clip saved / couldn't save), with
    /// the instant it was raised so the view can fade it after ~2 s.
    private(set) var toast: RideModeToast?

    /// The absolute grace-countdown deadline, or `nil` when not in grace. The
    /// view ticks the remaining seconds locally from this.
    var graceDeadline: Date? {
        if case let .graceCountdown(until) = mode { return until }
        return nil
    }

    /// How often the recording dot shifts a few points to protect the OLED
    /// (design "Ride mode": a few points every 60 s). Surfaced for the view.
    var redDotShiftPeriod: TimeInterval { tuning.redDotShiftPeriod }

    /// How long the two-finger unlock press must be held (design: 1.0 s).
    var unlockHoldDuration: TimeInterval { tuning.unlockHoldDuration }

    // MARK: Private bookkeeping (not observed)

    /// The in-memory dim guard mirroring the persisted one, used by
    /// `BrightnessGuard` to decide the restore target without re-reading the
    /// store on every step.
    @ObservationIgnored private var currentGuard: BrightnessGuardState?
    /// True while a crash countdown forces full brightness and suppresses
    /// automatic re-dimming (row 10); cleared when the countdown ends (row 11).
    @ObservationIgnored private var suppressRedim = false
    /// The one active grace-countdown timer.
    @ObservationIgnored private var graceTimer: Cancellable?
    /// The one active unlock-inactivity timer.
    @ObservationIgnored private var unlockTimer: Cancellable?

    init(
        screen: ScreenController,
        dimGuardStore: DimGuardStore,
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning(),
        isRideActive: @escaping () -> Bool,
        isRideModeEnabled: @escaping () -> Bool
    ) {
        self.screen = screen
        self.dimGuardStore = dimGuardStore
        self.clock = clock
        self.tuning = tuning
        self.isRideActive = isRideActive
        self.isRideModeEnabled = isRideModeEnabled
        self.currentGuard = dimGuardStore.guardState
        wireSystemBrightness()
    }

    // MARK: - Wiring

    private func wireSystemBrightness() {
        screen.onSystemBrightnessChange = { [weak self] value in
            guard let self else { return }
            // The rider is treated as the author of a change only while the
            // controls are visible (unlocked); otherwise it is Auto-Brightness
            // fighting the dim and must be re-applied (row 13 / BG-2/BG-6).
            let riderInitiated: Bool
            if case .unlockedTemporarily = self.mode { riderInitiated = true } else { riderInitiated = false }
            self.dispatch(.systemBrightnessChanged(value: value, riderInitiated: riderInitiated))
        }
    }

    // MARK: - Rider / lifecycle intents (forwarded to the reducer)

    /// A ride started (row 1): enter the mount-grace countdown when ride mode is
    /// on.
    func rideStarted() { dispatch(.rideStarted) }

    /// The rider tapped "Dim now" during grace (row 2).
    func dimNow() { dispatch(.dimNow) }

    /// The rider tapped "Keep screen on" during grace (row 3).
    func keepScreenOn() { dispatch(.keepScreenOn) }

    /// The two-finger long-press unlock gesture completed (row 4).
    func twoFingerHoldCompleted() { dispatch(.twoFingerHoldCompleted) }

    /// The VoiceOver "Unlock controls" custom action fired (row 5).
    func accessibilityUnlock() { dispatch(.accessibilityUnlock) }

    /// Touch activity while unlocked (row 6): extend the inactivity window.
    func touchActivity() { dispatch(.touchActivity) }

    /// The app resigned active (row 8): restore brightness, clear the guard.
    func appResignedActive() { dispatch(.appResignedActive) }

    /// The app became active again (row 9).
    func appBecameActive() { dispatch(.appBecameActive) }

    /// A crash countdown started (row 10): force full brightness + unlock.
    func crashCountdownStarted() { dispatch(.crashCountdownStarted) }

    /// A crash countdown ended (row 11).
    func crashCountdownEnded() { dispatch(.crashCountdownEnded) }

    /// The ride ended (row 12): restore brightness, clear the guard, restore the
    /// idle timer.
    func rideEnded() { dispatch(.rideEnded) }

    /// Reconcile a dim guard persisted by a previous run on launch (row 14): if
    /// no ride is active, restore the saved original once and clear the guard.
    func reconcileOnLaunch() {
        guard dimGuardStore.guardState != nil else { return }
        currentGuard = dimGuardStore.guardState
        dispatch(.launchWithActiveGuard)
    }

    // MARK: - Trouble + toasts (set by the owning coordinator)

    /// Raise or clear the camera/GPS trouble state (amber dot). Never hides the
    /// recording indicator; it only changes its shape/colour.
    func setTrouble(_ trouble: Bool) { isTrouble = trouble }

    /// Surface a transient toast (e.g. "Clip saved"); the view fades it.
    func showToast(_ toast: RideModeToast) {
        self.toast = toast
    }

    /// Clear the current toast (the view calls this after the fade).
    func clearToast() { toast = nil }

    // MARK: - The reduce → apply loop

    private func dispatch(_ event: ScreenModeEvent) {
        let context = ScreenModeContext(
            now: clock.now(),
            tuning: tuning,
            rideActive: isRideActive(),
            rideModeEnabled: isRideModeEnabled()
        )
        let reduction = ScreenModeStateMachine.reduce(mode, event, context)
        let previousMode = mode
        mode = reduction.state
        for effect in reduction.effects {
            apply(effect, context: context)
        }
        syncTimers(previousMode: previousMode)
    }

    // MARK: - Effect execution

    private func apply(_ effect: ScreenModeEffect, context: ScreenModeContext) {
        switch effect {
        case let .showGraceCountdown(until):
            // The deadline is encoded in `mode`; nothing else to do here.
            _ = until

        case .storeOriginalBrightnessAndPersistGuard:
            // The current reading is the rider's real brightness on the first
            // entry; a repeated entry keeps the stored original (BG-5).
            let state = BrightnessGuard.guardForEntering(
                existing: currentGuard,
                currentReading: screen.brightness,
                dimTarget: context.tuning.dimBrightness
            )
            currentGuard = state
            dimGuardStore.store(state)

        case let .setBrightness(value):
            screen.setBrightness(value)

        case .restoreBrightness:
            restoreBrightness()

        case .clearGuard:
            currentGuard = nil
            dimGuardStore.clear()

        case let .setIdleTimerDisabled(disabled):
            screen.setIdleTimerDisabled(disabled)

        case let .setTouchLocked(locked):
            isTouchLocked = locked
            if locked { isShowingControls = false }

        case .showControls:
            isShowingControls = true

        case let .suppressRedim(suppress):
            suppressRedim = suppress

        case .restorePersistedOriginal:
            restorePersistedOriginal()
        }
    }

    /// Restore the rider's original brightness when leaving the dimmed state,
    /// using the pure `BrightnessGuard` so a brightness already at the original
    /// is a no-op (BG-3), otherwise restore (BG-1).
    private func restoreBrightness() {
        guard let guardState = currentGuard else { return }
        switch BrightnessGuard.restoreTarget(guard: guardState, currentReading: screen.brightness) {
        case let .restore(value):
            screen.setBrightness(value)
        case let .reapplyDim(value):
            screen.setBrightness(value)
        case .noChange:
            break
        }
    }

    /// Restore the brightness persisted by a previous run's guard, once (row 14).
    private func restorePersistedOriginal() {
        guard let guardState = dimGuardStore.guardState else { return }
        screen.setBrightness(guardState.original)
    }

    // MARK: - Timers (grace + unlock inactivity)

    /// Reconcile the scheduled timers with the current mode after each step. A
    /// crash countdown suppresses the re-dim timer (row 10).
    private func syncTimers(previousMode: ScreenMode) {
        switch mode {
        case let .graceCountdown(until):
            scheduleGrace(until: until)
            cancelUnlockTimer()
        case let .unlockedTemporarily(until):
            cancelGraceTimer()
            if suppressRedim {
                cancelUnlockTimer()
            } else {
                scheduleUnlock(until: until)
            }
        case .dimLocked, .normal, .suspended:
            cancelGraceTimer()
            cancelUnlockTimer()
        }
    }

    private func scheduleGrace(until: Date) {
        graceTimer?.cancel()
        let delay = max(0, until.timeIntervalSince(clock.now()))
        graceTimer = clock.schedule(after: delay) { [weak self] in
            self?.dispatch(.graceElapsed)
        }
    }

    private func scheduleUnlock(until: Date) {
        unlockTimer?.cancel()
        let delay = max(0, until.timeIntervalSince(clock.now()))
        unlockTimer = clock.schedule(after: delay) { [weak self] in
            self?.dispatch(.unlockDeadlineReached)
        }
    }

    private func cancelGraceTimer() {
        graceTimer?.cancel()
        graceTimer = nil
    }

    private func cancelUnlockTimer() {
        unlockTimer?.cancel()
        unlockTimer = nil
    }
}

/// A transient ride-mode toast surfaced very dimly over the black overlay
/// (design "Ride mode": "Clip saved" / "Couldn't save clip" for ~2 s). Honest
/// copy only: recording is for the rider's own records, and Whoosh cannot
/// guarantee detection or delivery, so a toast never overstates what was saved.
enum RideModeToast: Equatable, Sendable {
    /// A clip was saved.
    case clipSaved
    /// A clip could not be saved (with a short, plain reason).
    case clipNotSaved

    /// The very dim text shown over the black screen.
    var text: String {
        switch self {
        case .clipSaved: return "Clip saved"
        case .clipNotSaved: return "Couldn't save clip"
        }
    }
}
