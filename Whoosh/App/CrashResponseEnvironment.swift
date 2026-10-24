import Foundation

/// The composition root's crash-response sub-environment (crash-response
/// task 26). Owns the opt-in crash subsystem's concrete services and the single
/// `CrashResponseCoordinator`, and wires a per-ride `RideSessionBridge` when a
/// ride starts — without the ride engine knowing anything about it.
///
/// ## Why a relay `RideContext`
/// The coordinator holds one `RideContext` for its whole lifetime, but the ride
/// engine (`RideSessionViewModel`) is created fresh per ride session. So this
/// environment gives the coordinator a stable `RelayRideContext` that forwards
/// to the **current** `RideSessionBridge`, or reports "idle, no fix" when no
/// ride is in progress. Starting a ride attaches a bridge; finishing clears it.
///
/// ## Tier 0 only
/// The notifier is always `NoopCrashNotifier` here (Tier 0): there is **no
/// network code**, no sign-in, and no notification prompt until the rider
/// enables crash alerts. `SupabaseCrashNotifier` is task 25 (blocked). With
/// crash alerts off, nothing in this subsystem touches the network, so the app
/// behaves exactly like the MVP (Requirement 1.5, PRIV-1).
///
/// ## Detector source
/// The detector is a `DebugCrashSimulator` when the rider has turned on the
/// developer/demo tools (so "Simulate crash" works), and a `NoopCrashDetector`
/// otherwise. Either way detection is only *armed* by the bridge while the ride
/// is recording/signalLost with consent, a label, and a reachable contact (O10).
@MainActor
final class CrashResponseEnvironment {
    // MARK: Owned services (concrete types live only here)

    let contactStore: EmergencyContactStore
    let consentStore: ConsentStore
    let settingsStore: CrashAlertSettingsStore
    let repository: CrashAlertRepository
    let connectivity: ConnectivityMonitor
    let scheduler: CrashNotificationScheduler
    private let notifier: CrashNotifier
    private let feedback: CountdownFeedback

    /// The notifier used by the test/intro flow in the setup hub. In Tier 0 this
    /// is the `NoopCrashNotifier` (no network); in Tier 1 it is the
    /// `SupabaseCrashNotifier`. The test flow shows the honest "not connected"
    /// fallback only when `isMessagingConnected` is `false`.
    var noopNotifier: CrashNotifier { notifier }
    private let footageBuffer: FootageBuffer
    private let detector: CrashDetector
    private let clock: Clock
    private let messagingConnected: Bool

    /// Shared with the live `MotionCrashDetector` (when present) so the detector
    /// can read the ride's current GPS speed. The ride bridge publishes into it.
    private let speedSnapshot: RideSpeedSnapshot

    /// The relay the coordinator holds; forwards to the current bridge.
    private let relayContext: RelayRideContext

    /// The one crash-response coordinator for the app's lifetime.
    let coordinator: CrashResponseCoordinator

    /// The simulator, when developer tools are on (used by Settings' "Simulate
    /// crash" control). `nil` when the detector is the no-op.
    let simulator: DebugCrashSimulator?

    /// The bridge for the current ride session, if any. Observes that session
    /// and arms/disarms the shared detector.
    private var bridge: RideSessionBridge?

    init(
        contactStore: EmergencyContactStore,
        consentStore: ConsentStore,
        settingsStore: CrashAlertSettingsStore,
        repository: CrashAlertRepository,
        connectivity: ConnectivityMonitor,
        scheduler: CrashNotificationScheduler,
        notifier: CrashNotifier,
        feedback: CountdownFeedback,
        footageBuffer: FootageBuffer,
        detector: CrashDetector,
        simulator: DebugCrashSimulator?,
        clock: Clock,
        speedSnapshot: RideSpeedSnapshot = RideSpeedSnapshot(),
        isMessagingConnected: Bool = false
    ) {
        self.contactStore = contactStore
        self.consentStore = consentStore
        self.settingsStore = settingsStore
        self.repository = repository
        self.connectivity = connectivity
        self.scheduler = scheduler
        self.notifier = notifier
        self.feedback = feedback
        self.footageBuffer = footageBuffer
        self.detector = detector
        self.simulator = simulator
        self.clock = clock
        self.speedSnapshot = speedSnapshot
        self.messagingConnected = isMessagingConnected

        let relay = RelayRideContext()
        self.relayContext = relay
        self.coordinator = CrashResponseCoordinator(
            detector: detector,
            rideContext: relay,
            footageBuffer: footageBuffer,
            notifier: notifier,
            scheduler: scheduler,
            feedback: feedback,
            connectivity: connectivity,
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: repository,
            clock: clock
        )

        // Begin observing reachability so a queued-offline alert retries when
        // connectivity returns (Requirement 12.1). Makes no network requests.
        connectivity.start()
    }

    /// Whether the feature is wired to a real messaging backend. `true` in
    /// Tier 1 (a `SupabaseCrashNotifier` over a configured client); `false` in
    /// Tier 0 (the Noop notifier), where the test flow shows the honest "not
    /// connected" fallback instead of pretending to send.
    var isMessagingConnected: Bool { messagingConnected }

    /// The on/off state for the Home / ride-screen chip and arming inputs.
    var isFeatureOn: Bool { settingsStore.current().enabled }

    // MARK: - Ride session attach / detach

    /// Attach a bridge observing the given ride session so detection can arm
    /// while recording. The coordinator's relay forwards to this bridge until
    /// the ride finishes (`detachRide()`). Also re-evaluates arming immediately.
    func attachRide(_ session: RideSessionViewModel) {
        let bridge = RideSessionBridge(
            rideViewModel: session,
            detector: detector,
            armingInputs: { [weak self] in self?.armingInputs() ?? .disabled },
            publishSpeed: { [weak self] speed in self?.speedSnapshot.update(speed) }
        )
        self.bridge = bridge
        relayContext.underlying = bridge
        bridge.start()
    }

    /// Detach the current ride bridge (ride finished / cleared). Disarms the
    /// detector and returns the relay to its idle default.
    func detachRide() {
        bridge?.stop()
        bridge = nil
        relayContext.underlying = nil
        speedSnapshot.update(nil)
    }

    /// Re-evaluate arming after a non-ride input changed (contacts edited,
    /// consent recorded/revoked, feature toggled). Safe to call with no ride.
    func reevaluateArming() {
        bridge?.reevaluateArming()
    }

    /// Run a demo-mode crash **drill** through the real coordinator (demo-mode
    /// task 12). Bypasses arming for this one drill only; it uses the `drill`
    /// template, hides "Call 911", never consumes the real-alert cap, and never
    /// sends a real (non-drill) alert. Works with no ride, consent, or contacts.
    func triggerCrashDrill() {
        coordinator.triggerDrill()
    }

    /// Reconcile a persisted active event on launch (task 14). Safe to call with
    /// no active event.
    func reconcileOnLaunch() {
        coordinator.reconcileOnLaunch()
    }

    // MARK: - Arming inputs snapshot

    private func armingInputs() -> RideSessionBridge.ArmingInputs {
        let settings = settingsStore.current()
        let reachable = contactStore.contactsOrEmpty().filter { $0.verification == .reachable }.count
        return RideSessionBridge.ArmingInputs(
            enabled: settings.enabled,
            consentCurrent: consentStore.current()?.isCurrent(minimumVersion: 1) ?? false,
            riderLabelPresent: (settings.riderLabel?.isEmpty == false),
            reachableContactCount: reachable
        )
    }
}

private extension RideSessionBridge.ArmingInputs {
    /// The all-off inputs used when the environment is torn down (never armed).
    static var disabled: RideSessionBridge.ArmingInputs {
        RideSessionBridge.ArmingInputs(
            enabled: false,
            consentCurrent: false,
            riderLabelPresent: false,
            reachableContactCount: 0
        )
    }
}

/// A `RideContext` that forwards to a swappable `underlying` context, or reports
/// "idle, no active ride, no fix" when none is set. Lets the single long-lived
/// coordinator track a ride session that is created fresh per ride.
@MainActor
final class RelayRideContext: RideContext {
    /// The current real context (a `RideSessionBridge`), or `nil` when idle.
    var underlying: RideContext?

    var isRideActive: Bool { underlying?.isRideActive ?? false }
    var isRecordingOrSignalLost: Bool { underlying?.isRecordingOrSignalLost ?? false }
    var latestAcceptedFix: RideFix? { underlying?.latestAcceptedFix }
    var currentRideID: UUID? { underlying?.currentRideID }
}
