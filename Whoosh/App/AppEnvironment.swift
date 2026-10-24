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
    /// The Home hub view model (owns its own tracker for authorization).
    let homeViewModel: HomeViewModel

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
        self.settingsViewModel = SettingsViewModel(repository: repository, defaults: defaults)
        self.homeViewModel = HomeViewModel(
            repository: repository,
            clock: clock,
            calendar: calendar,
            tracker: makeHomeTracker()
        )
    }

    // MARK: - Factories for view models

    /// A fresh ride session, with `RideTuning.accuracy` taken from the persisted
    /// Settings choice so the setting applies to the next ride (Requirement
    /// 14.2). A new tracker is created so the session owns its location stream.
    ///
    /// Also attaches the crash-response bridge to the session so detection can
    /// arm while recording (no-op unless the rider enabled crash alerts); the
    /// bridge is detached when the ride is cleared (`clearRideSession()`).
    func makeRideSession() -> RideSessionViewModel {
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

        // Crash-response stores (device-local only; no network). Contacts live
        // only in the Keychain; orphaned items are purged on a fresh install.
        let markerStore = UserDefaultsFreshInstallMarkerStore()
        let contactStore = KeychainEmergencyContactStore(markerStore: markerStore)
        try? contactStore.purgeOrphansIfFreshInstall()
        let settingsStore = UserDefaultsCrashAlertSettingsStore()

        // Detector source: the demo simulator when developer tools are on, else
        // the no-op. Either way detection is only armed by the bridge while a
        // ride is recording with consent, a label, and a reachable contact.
        let developerToolsOn = settingsStore.current().developerToolsEnabled
        let simulator: DebugCrashSimulator? = developerToolsOn ? DebugCrashSimulator(clock: clock) : nil
        let detector: CrashDetector = simulator ?? NoopCrashDetector()

        let crash = CrashResponseEnvironment(
            contactStore: contactStore,
            consentStore: UserDefaultsConsentStore(),
            settingsStore: settingsStore,
            repository: crashRepository,
            connectivity: NWPathConnectivityMonitor(),
            scheduler: UserNotificationsCrashNotificationScheduler(),
            notifier: NoopCrashNotifier(),           // Tier 0: no network (task 25 blocked)
            feedback: SystemCountdownFeedback(),
            footageBuffer: NoopFootageBuffer(),
            detector: detector,
            simulator: simulator,
            clock: clock
        )

        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            alertManager: StubAlertManager(),
            crash: crash,
            calendar: .current,
            defaults: .standard,
            storageNotice: storageNotice,
            makeHomeTracker: { CoreLocationTracker() },
            makeRideTracker: { CoreLocationTracker() }
        )
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
            makeHomeTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) },
            makeRideTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) }
        )
    }
}
