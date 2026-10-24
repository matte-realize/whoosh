import Foundation
import SwiftData

/// The composition root (task 23). Builds and owns the concrete services and
/// view models, and is the **only** place that wires framework service types —
/// views stay free of them (layering table: "Composition knows about
/// everything").
///
/// Two factories exist:
/// - `live()` builds the real stack: a `SwiftDataRideRepository` over a
///   `ModelContainer` for `RideRecord`, `CoreLocationTracker`s, `SystemClock`,
///   and the no-op detector/alert seams.
/// - `preview(seeded:)` / the test initializer build a fake stack
///   (`InMemoryRideRepository`, `FakeLocationTracker`, an injected `Clock`) so
///   SwiftUI previews and unit tests never touch Core Location or on-disk
///   storage.
///
/// Location wiring note: `HomeViewModel` and `RideSessionViewModel` each take
/// their own `LocationTracking` instance (both set the single
/// `onAuthorizationChange` callback, so sharing one would clobber the other).
/// Home only needs authorization status + the first-run prompt; the ride
/// session owns the recording tracker. On a real device both wrap a
/// `CLLocationManager` and report the same system authorization.
@MainActor
final class AppEnvironment {
    let repository: RideRepository
    let clock: Clock
    let detector: HazardDetector
    let alertManager: AlertManager

    /// The opt-in crash-response sub-environment (crash-response task 26). Owns
    /// the coordinator, stores, and seams; always Tier 0 (Noop notifier, no
    /// network) here. With crash alerts off, nothing in it touches the network,
    /// so the app behaves exactly as the MVP (Requirement 1.5).
    let crash: CrashResponseEnvironment

    /// A calm, non-fatal notice to show the user when local storage had to fall
    /// back to a non-persistent store (Requirement 11.4). `nil` in the normal
    /// case. App-written copy only — never raw framework error text.
    let storageNotice: String?

    /// Persisted GPS-accuracy setting; fed into `RideTuning` for each new ride.
    let settingsViewModel: SettingsViewModel
    /// Drives the "Rear camera" Settings section and the first-enable camera
    /// permission flow (rear-camera spec Requirement 2/18.1, task 20). Off by
    /// default; the camera is requested only when the rider enables recording.
    let rearCameraSettingsViewModel: RearCameraSettingsViewModel
    /// The Home hub view model (owns its own tracker for authorization).
    let homeViewModel: HomeViewModel

    /// Demo mode's controller (demo-mode tasks 8–9). Built **always** but inert
    /// while its toggle is off, so the off path is the exact normal path
    /// (Requirement 9.1). The only composition-root branch on demo state lives
    /// in `makeRideSession()`.
    let demo: DemoModeController

    /// The opt-in sync coordinator. Backed by `NoopRideSyncService` in previews/
    /// tests and whenever no Supabase config is present, so with sync OFF the
    /// app makes zero network calls and behaves exactly as before.
    let syncCoordinator: SyncCoordinator

    /// Builds a fresh `LocationTracking` for a ride session. Injectable so
    /// previews/tests supply a `FakeLocationTracker`.
    private let makeRideTracker: () -> LocationTracking

    private init(
        repository: RideRepository,
        clock: Clock,
        detector: HazardDetector,
        alertManager: AlertManager,
        crash: CrashResponseEnvironment,
        calendar: Calendar,
        defaults: UserDefaults,
        storageNotice: String? = nil,
        supabaseProvider: SupabaseClientProvider?,
        appVersion: String,
        pendingDeletes: PendingRemoteDeleteStore,
        cameraPermission: CameraPermission,
        rearCameraStore: RearCameraSettingsStore,
        makeHomeTracker: () -> LocationTracking,
        makeRideTracker: @escaping () -> LocationTracking
    ) {
        self.repository = repository
        self.clock = clock
        self.detector = detector
        self.alertManager = alertManager
        self.crash = crash
        self.storageNotice = storageNotice
        self.makeRideTracker = makeRideTracker
        let settings = SettingsViewModel(repository: repository, defaults: defaults)
        self.settingsViewModel = settings
        self.rearCameraSettingsViewModel = RearCameraSettingsViewModel(
            permission: cameraPermission,
            store: rearCameraStore,
            clipRepository: InMemoryClipRepository()
        )
        self.homeViewModel = HomeViewModel(
            repository: repository,
            clock: clock,
            calendar: calendar,
            tracker: makeHomeTracker()
        )
        // Build the demo controller over the same repository/clock/alert seams.
        // A simulated ride is recorded by a real `RideSessionViewModel` whose
        // tracker is a `SimulatedRouteTracker` (no mixing with real GPS by
        // construction, Requirement 5.4); the accuracy comes from the persisted
        // Settings choice, exactly like a normal ride.
        self.demo = DemoModeController(
            defaults: defaults,
            clock: clock,
            alertManager: alertManager,
            repository: repository,
            makeSimulatedTracker: { script, factor in
                SimulatedRouteTracker(script: script, clock: clock, speedFactor: factor)
            },
            makeSimulatedSession: { tracker in
                var tuning = RideTuning()
                tuning.accuracy = settings.trackingAccuracy
                return RideSessionViewModel(
                    tracker: tracker,
                    clock: clock,
                    repository: repository,
                    tuning: tuning
                )
            }
        )

        // Choose the sync service: the real Supabase one only when a client is
        // configured (secrets present); otherwise the Noop (sync never signs in).
        // Its `isEnabled` reads a thread-safe flag mirrored from the live
        // Settings toggle, so with sync OFF the coordinator makes zero network
        // calls and the app behaves as before.
        let enabledFlag = SyncEnabledFlag(settings.syncEnabled)
        let service: RideSyncService
        if let provider = supabaseProvider, let client = provider.client {
            let transport = SupabaseRideSyncTransport(client: client)
            service = SupabaseRideSyncService(
                transport: transport,
                appVersion: appVersion,
                isEnabled: { enabledFlag.isOn }
            )
        } else {
            service = NoopRideSyncService()
        }
        let coordinator = SyncCoordinator(
            service: service,
            repository: repository,
            pendingDeletes: pendingDeletes
        )
        self.syncCoordinator = coordinator

        // Mirror the Settings toggle into the flag and retry pending uploads
        // when the user turns sync on.
        settings.onSyncEnabledChange = { enabled in
            enabledFlag.set(enabled)
            guard enabled else { return }
            Task { await coordinator.retryPending() }
        }
        // When the user chooses to unshare already-shared rides.
        let repo = repository
        settings.onUnshareAllSharedRides = { [weak coordinator] in
            guard let coordinator else { return }
            let shared = ((try? repo.allRides()) ?? []).filter { $0.sharePublicly }
            Task { await coordinator.unshareRides(shared) }
        }
        // Propagate remote deletes after "Delete all rides".
        settings.onDidDeleteAllRides = { [weak coordinator] ids in
            guard let coordinator, !ids.isEmpty else { return }
            Task { await coordinator.allRidesWereDeleted(previouslySynced: ids) }
        }
    }

    // MARK: - Sync lifecycle hooks (called by the app / history)

    /// After a ride is saved locally, mirror it to the backend (stamping the
    /// current global sharing flag). No-op while sync is off.
    func rideDidFinish(_ ride: Ride) async {
        await syncCoordinator.rideDidFinish(
            ride,
            shareNewRidesPublicly: settingsViewModel.shareNewRidesPublicly
        )
    }

    /// After a ride is deleted locally, request its remote deletion.
    func rideWasDeleted(_ ride: Ride) async {
        await syncCoordinator.rideWasDeleted(ride)
    }

    /// Before/after "Delete all rides", propagate remote deletes for any rides
    /// that had been uploaded. Pass the ids collected before the wipe.
    func allRidesWereDeleted(previouslySynced ids: [UUID]) async {
        await syncCoordinator.allRidesWereDeleted(previouslySynced: ids)
    }

    /// App-foreground retry of pending uploads and deletes.
    func retryPendingSync() async {
        await syncCoordinator.retryPending()
    }

    // MARK: - Factories for view models

    /// A fresh ride session, with `RideTuning.accuracy` taken from the persisted
    /// Settings choice so the setting applies to the next ride (Requirement
    /// 14.2). A new tracker is created so the session owns its location stream.
    ///
    /// Demo branch (the **only** composition-root branch on demo state): when a
    /// simulated ride has been requested, the demo controller already owns a
    /// `SimulatedRouteTracker`-backed session, so return that one — one ride ⇒
    /// one tracker ⇒ all-scripted or all-real, never mixed (Requirement 5.4).
    /// With demo mode off (or no simulated ride requested) this returns exactly
    /// today's `CoreLocationTracker`-backed session, so the off path is the
    /// identity path (Requirement 9.1).
    ///
    /// Also attaches the crash-response bridge to the session so detection can
    /// arm while recording (no-op unless the rider enabled crash alerts); the
    /// bridge is detached when the ride is cleared (`clearRideSession()`).
    func makeRideSession() -> RideSessionViewModel {
        if let simulated = demo.simulatedSession {
            // Demo rides get the bridge too, so a crash drill can arm during one.
            crash.attachRide(simulated)
            return simulated
        }
        var tuning = RideTuning()
        tuning.accuracy = settingsViewModel.trackingAccuracy
        let session = RideSessionViewModel(
            tracker: makeRideTracker(),
            clock: clock,
            repository: repository,
            tuning: tuning
        )
        crash.attachRide(session)
        return session
    }

    /// Detach the crash bridge when a ride session is cleared (ride finished or
    /// an interrupted-ride probe is thrown away). Safe to call repeatedly.
    func clearRideSession() {
        crash.detachRide()
    }

    /// A fresh History view model over the shared repository.
    func makeHistoryViewModel(calendar: Calendar = .current) -> HistoryViewModel {
        HistoryViewModel(repository: repository, calendar: calendar)
    }

    // MARK: - Live stack

    /// The real composition root. Falls back to an in-memory SwiftData container
    /// if an on-disk store cannot be created, so the app still launches (history
    /// simply won't persist across launches in that degraded case).
    static func live() -> AppEnvironment {
        let (repository, crashRepository, storageNotice) = Self.makeLiveRepositories()
        let clock = SystemClock()

        // The single Supabase client provider, shared by opt-in ride sync and
        // opt-in crash alerts. When no secrets are present `isConfigured` is
        // false and both features stay offline (Noop notifier / Noop sync).
        let supabaseProvider = SupabaseClientProvider()
        let appVersion = Self.appVersion()

        // Crash-response stores (device-local only; no network). Contacts live
        // only in the Keychain; orphaned items are purged on a fresh install.
        let markerStore = UserDefaultsFreshInstallMarkerStore()
        let contactStore = KeychainEmergencyContactStore(markerStore: markerStore)
        try? contactStore.purgeOrphansIfFreshInstall()
        let settingsStore = UserDefaultsCrashAlertSettingsStore()
        let consentStore = UserDefaultsConsentStore()

        // Detector source: the demo simulator when developer tools are on, else
        // the no-op. Either way detection is only armed by the bridge while a
        // ride is recording with consent, a label, and a reachable contact.
        let developerToolsOn = settingsStore.current().developerToolsEnabled
        let simulator: DebugCrashSimulator? = developerToolsOn ? DebugCrashSimulator(clock: clock) : nil
        let detector: CrashDetector = simulator ?? NoopCrashDetector()

        // Notifier: Tier 1 `SupabaseCrashNotifier` when a Supabase client is
        // configured (auto-send on the rider's behalf — the owner's "if it's
        // bad the user won't be able to click send" requirement); otherwise the
        // Tier 0 Noop (no network), so the composer fallback and local
        // notification remain. Only `Services/Notification` touches the network.
        let notifier: CrashNotifier
        let messagingConnected: Bool
        if let client = supabaseProvider.client {
            let transport = SupabaseFunctionsCrashTransport(client: client)
            notifier = SupabaseCrashNotifier(
                transport: transport,
                appVersion: appVersion
            )
            messagingConnected = true
        } else {
            notifier = NoopCrashNotifier()           // Tier 0: no network
            messagingConnected = false
        }

        let crash = CrashResponseEnvironment(
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: crashRepository,
            connectivity: NWPathConnectivityMonitor(),
            scheduler: UserNotificationsCrashNotificationScheduler(),
            notifier: notifier,
            feedback: SystemCountdownFeedback(),
            footageBuffer: NoopFootageBuffer(),
            detector: detector,
            simulator: simulator,
            clock: clock,
            isMessagingConnected: messagingConnected
        )

        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            // Ship the real alert manager app-wide (D-DM5): it is inert until
            // `fire(_:)` is called, so normal mode is unchanged (the rear-alert
            // gate won't call it until a real detector exists), and the demo's
            // forced-alert path produces real haptics/audio.
            alertManager: HapticAudioAlertManager(clock: clock),
            crash: crash,
            calendar: .current,
            defaults: .standard,
            storageNotice: storageNotice,
            supabaseProvider: supabaseProvider,
            appVersion: appVersion,
            pendingDeletes: UserDefaultsPendingRemoteDeleteStore(),
            cameraPermission: AVCameraPermission(),
            rearCameraStore: UserDefaultsRearCameraSettingsStore(),
            makeHomeTracker: { CoreLocationTracker() },
            makeRideTracker: { CoreLocationTracker() }
        )
    }

    /// The short build string (`CFBundleShortVersionString`), capped at the
    /// contract's 32-char `app_version` limit.
    private static func appVersion() -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        return String(raw.prefix(32))
    }

    /// Builds the ride repository and the crash-alert repository over a **single
    /// shared `ModelContainer`** holding both `RideRecord` and
    /// `CrashAlertRecordEntity` (crash-response task 26: the crash record entity
    /// is added to the same live container as rides, keeping the container-
    /// retention rule and the in-memory fallback). Existing ride data is
    /// untouched by adding the new `@Model`.
    private static func makeLiveRepositories() -> (RideRepository, CrashAlertRepository, String?) {
        let schema: [any PersistentModel.Type] = [RideRecord.self, CrashAlertRecordEntity.self]
        do {
            let container = try ModelContainer(for: Schema(schema))
            let context = container.mainContext
            return (
                SwiftDataRideRepository(context: context),
                SwiftDataCrashAlertRepository(context: context),
                nil
            )
        } catch {
            // Degrade gracefully: an in-memory store keeps the app usable. Never
            // surface the raw framework error — a calm, app-written notice only
            // (Requirements 11.4 / design: SwiftData container failure is a
            // non-fatal notice, not a crash).
            let notice = "Saved rides are unavailable right now, so new rides won't be kept after you close the app. Everything else works."
            if let inMemory = try? ModelContainer(
                for: Schema(schema),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                let context = inMemory.mainContext
                return (
                    SwiftDataRideRepository(context: context),
                    SwiftDataCrashAlertRepository(context: context),
                    notice
                )
            }
            return (InMemoryRideRepository(), InMemoryCrashAlertRepository(), notice)
        }
    }

    // MARK: - Preview / test stack

    /// A fake-backed environment for SwiftUI previews and unit tests. All
    /// dependencies are fakes; nothing touches Core Location or disk.
    static func preview(
        seeded: Bool = true,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> AppEnvironment {
        let rides = seeded ? PreviewSeed.rides(now: Date()) : []
        let repository = InMemoryRideRepository(rides: rides)
        let crash = CrashResponseEnvironment(
            contactStore: InMemoryEmergencyContactStore(),
            consentStore: InMemoryConsentStore(),
            settingsStore: InMemoryCrashAlertSettingsStore(),
            repository: InMemoryCrashAlertRepository(),
            connectivity: FakeConnectivityMonitor(isOnline: true),
            scheduler: FakeCrashNotificationScheduler(),
            notifier: NoopCrashNotifier(),
            feedback: NoopCountdownFeedback(),
            footageBuffer: NoopFootageBuffer(),
            detector: NoopCrashDetector(),
            simulator: nil,
            clock: clock
        )
        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            alertManager: StubAlertManager(),
            crash: crash,
            calendar: calendar,
            defaults: defaults,
            supabaseProvider: nil,
            appVersion: "preview",
            pendingDeletes: InMemoryPendingRemoteDeleteStore(),
            cameraPermission: FakeCameraPermission(status: .notDetermined),
            rearCameraStore: InMemoryRearCameraSettingsStore(),
            makeHomeTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) },
            makeRideTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) }
        )
    }
}
