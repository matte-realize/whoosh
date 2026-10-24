import Foundation
import Observation

/// The single source of truth for "is demo mode on", and the owner of the live
/// demo activity (demo-mode design "DemoModeController (the heart of the
/// feature)"; tasks 8–11).
///
/// `@Observable`, `@MainActor`. It is created by `AppEnvironment` **always**, but
/// it only *activates* simulated services when enabled. With the toggle off it
/// is inert: every intent is a no-op, the badge is hidden, no simulated service
/// is wired, and the app behaves exactly as it does without this feature
/// (Requirement 9.1).
///
/// It depends only on service **protocols** (`AlertManager`, `RideRepository`),
/// the injected `Clock`, and factory closures the composition root supplies —
/// never on concrete framework types — so previews and tests build it over
/// fakes (`TestClock`, a recording `AlertManager` fake, `InMemoryRideRepository`).
///
/// Everything demo mode does runs through the app's real code paths with
/// simulated inputs: the simulated ride plays a scripted route through the real
/// `RideSessionViewModel`; the forced rear-vehicle cue fires the real
/// `AlertManager`; seeding/removal uses the real `RideRepository` via
/// `DemoDataSeeder`. Nothing here sends a real alert, dials, or uploads.
@Observable
@MainActor
final class DemoModeController {
    /// Stable `UserDefaults` key for the persisted toggle (mirrors
    /// `SettingsViewModel`'s pattern).
    static let enabledDefaultsKey = "whoosh.demo.enabled"

    /// Debug-only launch argument that presets the toggle **on** for UI tests
    /// (O-DM3). It only *presets* the stored value; it never triggers any demo
    /// action by itself, and it is honored in Debug builds only.
    static let enableLaunchArgument = "-whoosh.demo.enabled"

    // MARK: Injected dependencies

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let alertManager: AlertManager
    @ObservationIgnored private let repository: RideRepository
    @ObservationIgnored private let seeder: DemoDataSeeder
    @ObservationIgnored private let script: DemoRideScript
    @ObservationIgnored private let tuning: DemoTuning
    /// Builds a fresh `SimulatedRouteTracker` for a new simulated ride at the
    /// current speed factor. Injected so the composition root owns how a tracker
    /// is made and tests can substitute a fake-backed one.
    @ObservationIgnored private let makeSimulatedTracker: (DemoRideScript, Double) -> LocationTracking
    /// Builds a `RideSessionViewModel` over a given tracker (the composition
    /// root supplies the repository/`RideTuning`/`Clock`). The controller drives
    /// it like the normal ride flow would.
    @ObservationIgnored private let makeSimulatedSession: (LocationTracking) -> RideSessionViewModel
    /// Runs a crash **drill** through the real crash-response coordinator
    /// (demo-mode task 12). Injected by the composition root so the controller
    /// stays free of concrete crash types; defaults to a no-op so previews/tests
    /// that don't exercise the drill need not supply it. The drill bypasses
    /// arming (drills only), uses the `drill` template, and never sends a real
    /// alert.
    @ObservationIgnored private let triggerCrashDrill: () -> Void

    // MARK: Observable state

    /// The persisted on/off state. Setting it runs `activate()` / `deactivate()`
    /// and persists to `UserDefaults` so it survives relaunch (Requirement 1.2).
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            persistEnabled()
            if isEnabled {
                activate()
            } else {
                deactivate()
            }
        }
    }

    /// The DEMO MODE badge is visible iff demo mode is on (Requirement 2.1).
    var badgeVisible: Bool { isEnabled }

    /// Simulated-ride playback speed; `1×` by default, accelerated factors from
    /// `DemoTuning` (Requirement 5.3).
    private(set) var simulatedSpeedFactor: Double

    /// The active simulated-ride session, or `nil` when none is playing. The app
    /// presents this exactly like a normal ride; the controller drives its
    /// pause/resume at the scripted boundaries.
    private(set) var simulatedSession: RideSessionViewModel?

    /// Whether a simulated ride is currently playing (Requirement 1.6/5.7).
    var activeSimulatedRide: Bool { simulatedSession != nil }

    /// `true` while the forced-alert auto-trigger is running (Requirement 4.4).
    private(set) var autoAlertActive = false

    /// The state preview to render, or `nil` when none (Requirement 8).
    var statePreview: DemoStatePreview?

    /// A plain, user-facing report from the most recent seed/remove action
    /// (Requirement 7.6); `nil` when there is nothing to show.
    var dataActionMessage: String?

    /// The number of demo rides found on the last re-seed check, surfaced so the
    /// operator can choose to remove them first before seeding again (O-DM7).
    private(set) var existingDemoRideCount = 0

    // MARK: Private demo bookkeeping

    @ObservationIgnored private var autoAlertTimer: Cancellable?
    @ObservationIgnored private var pauseTimer: Cancellable?
    @ObservationIgnored private var resumeTimer: Cancellable?

    init(
        defaults: UserDefaults,
        clock: Clock,
        alertManager: AlertManager,
        repository: RideRepository,
        script: DemoRideScript = .charlesRiverLoop,
        tuning: DemoTuning = DemoTuning(),
        makeSimulatedTracker: @escaping (DemoRideScript, Double) -> LocationTracking,
        makeSimulatedSession: @escaping (LocationTracking) -> RideSessionViewModel,
        triggerCrashDrill: @escaping () -> Void = {}
    ) {
        self.defaults = defaults
        self.clock = clock
        self.alertManager = alertManager
        self.repository = repository
        self.seeder = DemoDataSeeder(repository: repository, clock: clock)
        self.script = script
        self.tuning = tuning
        self.makeSimulatedTracker = makeSimulatedTracker
        self.makeSimulatedSession = makeSimulatedSession
        self.triggerCrashDrill = triggerCrashDrill
        self.simulatedSpeedFactor = tuning.defaultSpeedFactor

        // Resolve the initial toggle state: a Debug-only launch argument may
        // preset it on for UI tests (O-DM3); otherwise read the persisted value
        // (default off).
        self.isEnabled = Self.resolveInitialEnabled(defaults: defaults)
    }

    // MARK: - Enable / disable lifecycle

    /// Wire the live demo activity. Idempotent and only meaningful while
    /// enabled; the simulated services are created lazily by the intents.
    private func activate() {
        // Nothing to eagerly wire: simulated services are created on demand by
        // `startSimulatedRide()` / `fireRearAlertOnce()`. This hook exists so the
        // transition is explicit and symmetrical with `deactivate()`.
    }

    /// Tear down every simulated service, the auto-trigger, any active simulated
    /// ride (finalize-and-keep per O-DM6), and previews — returning the app to
    /// the exact normal path (Requirement 1.4/1.6/9.7).
    private func deactivate() {
        stopAutoRearAlert()
        finalizeSimulatedRideIfActive()
        statePreview = nil
        dataActionMessage = nil
    }

    // MARK: - Simulated ride (Requirement 5)

    /// Start a simulated ride: build a `SimulatedRouteTracker` at the current
    /// speed factor, run it through a real `RideSessionViewModel`, and schedule
    /// the scripted pause/resume at the pause-segment boundaries so the paused
    /// state appears. No-op while disabled or when a simulated ride is already
    /// playing.
    func startSimulatedRide() {
        guard isEnabled, simulatedSession == nil else { return }
        let tracker = makeSimulatedTracker(script, simulatedSpeedFactor)
        let session = makeSimulatedSession(tracker)
        simulatedSession = session
        session.start()
        // The tracker only emits after `startUpdating`, which the ride engine
        // calls from `start()` → `beginRecording()`; nothing more is needed to
        // begin playback.
        scheduleScriptedPauseResume()
    }

    /// Stop the active simulated ride as if the rider pressed hold-to-stop: the
    /// ride is finalized and persisted (flagged demo). No-op when none is active.
    func stopSimulatedRide() {
        finalizeSimulatedRideIfActive()
    }

    /// Change the playback speed for the **next** simulated ride (and, when a
    /// ride is active and not yet started playing, future rides). Accelerated
    /// factors come from `DemoTuning`. No-op while disabled.
    func setSimulatedSpeed(_ factor: Double) {
        guard isEnabled else { return }
        simulatedSpeedFactor = max(factor, .leastNonzeroMagnitude)
    }

    /// Finalize (keep) the active simulated ride and clear the scripted timers.
    /// Used by stop and by `deactivate()` (O-DM6 = finalize-and-keep). The
    /// finished ride is re-saved flagged `isDemo` so it is excluded from sync and
    /// stats and shows the "Demo ride" tag (Requirement 5.5).
    private func finalizeSimulatedRideIfActive() {
        cancelScriptedPauseResume()
        guard let session = simulatedSession else { return }
        if session.rideState.isActive {
            session.stop()
        }
        // `RideSessionViewModel` finalizes a plain `Ride` (it doesn't know this
        // was simulated); flag and re-persist it as a demo ride.
        if let finished = session.finishedRide, !finished.isDemo {
            var demoRide = finished
            demoRide.isDemo = true
            try? repository.save(demoRide)
        }
        simulatedSession = nil
    }

    /// Schedule the controller-driven `pause()`/`resume()` at the script's pause
    /// window so the paused state shows during the demo (the player withholds
    /// the pause interior). Timing honors the current speed factor.
    private func scheduleScriptedPauseResume() {
        guard let window = script.pauseWindow else { return }
        let factor = max(simulatedSpeedFactor, .leastNonzeroMagnitude)
        let pauseAt = window.lowerBound / factor
        let resumeAt = window.upperBound / factor
        pauseTimer = clock.schedule(after: pauseAt) { [weak self] in
            self?.simulatedSession?.pause()
        }
        resumeTimer = clock.schedule(after: resumeAt) { [weak self] in
            self?.simulatedSession?.resume()
        }
    }

    private func cancelScriptedPauseResume() {
        pauseTimer?.cancel()
        pauseTimer = nil
        resumeTimer?.cancel()
        resumeTimer = nil
    }

    // MARK: - Forced rear-vehicle alert (Requirement 4)

    /// Fire the **real** rear-vehicle cue once, bypassing the stationary gate
    /// **only** (Requirement 4.3). It does not fabricate a `HazardDetection`, so
    /// nothing is logged as a real detection. No-op while disabled.
    func fireRearAlertOnce() {
        guard isEnabled else { return }
        alertManager.fire(.cautionRearVehicle)
    }

    /// Start firing the forced cue every `interval` seconds via the injected
    /// `Clock` (Requirement 4.4). Fires once immediately, then repeats. No-op
    /// while disabled.
    func startAutoRearAlert(every interval: TimeInterval = DemoTuning().autoAlertInterval) {
        guard isEnabled else { return }
        stopAutoRearAlert()
        autoAlertActive = true
        fireRearAlertOnce()
        scheduleNextAutoAlert(after: interval)
    }

    /// Stop the forced-cue auto-trigger. Called by the tools and by
    /// `deactivate()` so turning demo mode off stops it (Requirement 4.4/9.7).
    func stopAutoRearAlert() {
        autoAlertActive = false
        autoAlertTimer?.cancel()
        autoAlertTimer = nil
    }

    private func scheduleNextAutoAlert(after interval: TimeInterval) {
        autoAlertTimer = clock.schedule(after: interval) { [weak self] in
            guard let self, self.autoAlertActive, self.isEnabled else { return }
            self.alertManager.fire(.cautionRearVehicle)
            self.scheduleNextAutoAlert(after: interval)
        }
    }

    // MARK: - Send test alerts to the watch (watch task 26, owner request)

    /// Fire a short burst of real alerts so the owner can confirm the Apple
    /// Watch shows them exactly as it would in a ride (watch task 26). They flow
    /// through the same `AlertManager` fan-out as a real cue, so the watch sink
    /// buzzes the wrist and shows the rear-vehicle alert screen, escalating to
    /// phone audio when the watch does not confirm. No fabricated detection is
    /// logged. No-op while demo mode is off.
    ///
    /// Honest: the rear-vehicle cue is experimental; Whoosh cannot guarantee
    /// detection or delivery.
    func sendTestAlertsToWatch() {
        guard isEnabled else { return }
        // The rear-vehicle caution (the wrist cue + alert screen).
        alertManager.fire(.cautionRearVehicle)
        // A camera notice a second later so the owner sees a second wrist notice.
        alertManager.fire(.clipSaved)
    }

    // MARK: - Seed / remove sample data (Requirement 7)

    /// How many demo rides are currently stored (updates `existingDemoRideCount`
    /// so the tools can offer remove-first on re-seed, O-DM7). Returns 0 and sets
    /// a plain message on failure.
    @discardableResult
    func refreshExistingDemoCount() -> Int {
        guard isEnabled else { return 0 }
        do {
            existingDemoRideCount = try seeder.existingDemoCount()
            return existingDemoRideCount
        } catch {
            dataActionMessage = "Couldn't check demo data. Please try again."
            return 0
        }
    }

    /// Seed sample demo rides. When `removingExisting` is true, existing demo
    /// rides are cleared first so a re-seed never creates confusing duplicates
    /// (O-DM7). Reports a plain success/failure message. No-op while disabled.
    func seedSampleData(removingExisting: Bool = false) {
        guard isEnabled else { return }
        do {
            let count = try seeder.seed(removingExisting: removingExisting)
            existingDemoRideCount = (try? seeder.existingDemoCount()) ?? count
            dataActionMessage = "Added \(count) demo rides."
        } catch {
            dataActionMessage = "Couldn't add demo data. Please try again."
        }
    }

    /// Remove **only** demo-flagged rides (real rides untouched). Reports a plain
    /// message. No-op while disabled.
    func removeDemoData() {
        guard isEnabled else { return }
        do {
            let count = try seeder.removeDemo()
            existingDemoRideCount = 0
            dataActionMessage = count == 0 ? "No demo rides to remove." : "Removed \(count) demo rides."
        } catch {
            dataActionMessage = "Couldn't remove demo data. Please try again."
        }
    }

    // MARK: - State previews (Requirement 8)

    /// Show a state preview overlay. No-op while disabled.
    func showStatePreview(_ preview: DemoStatePreview) {
        guard isEnabled else { return }
        statePreview = preview
    }

    /// Dismiss the current state preview with no side effect.
    func dismissStatePreview() {
        statePreview = nil
    }

    // MARK: - Crash drill (Requirement 6) — wired in task 12

    /// Run a crash **drill** through the real crash-response coordinator
    /// (demo-mode task 12). The drill bypasses arming in demo mode only (so it
    /// runs with no active ride and even when no contacts or consent exist),
    /// shows the real countdown takeover with the `drill` template
    /// ("DEMO — NOT REAL"), hides "Call 911", and never consumes the real-alert
    /// cap. When contacts and consent exist the same notifier path runs, which
    /// in Tier 0 falls back to the prefilled composer — it never sends a real
    /// (non-drill) alert and never dials. No-op while demo mode is off.
    func simulateCrashDrill() {
        guard isEnabled else { return }
        triggerCrashDrill()
    }

    // MARK: - Persistence

    private func persistEnabled() {
        defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
    }

    private static func resolveInitialEnabled(defaults: UserDefaults) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(enableLaunchArgument) {
            return true
        }
        #endif
        return defaults.bool(forKey: enabledDefaultsKey)
    }
}
