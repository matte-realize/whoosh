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

    /// A calm, non-fatal notice to show the user when local storage had to fall
    /// back to a non-persistent store (Requirement 11.4). `nil` in the normal
    /// case. App-written copy only — never raw framework error text.
    let storageNotice: String?

    /// Persisted GPS-accuracy setting; fed into `RideTuning` for each new ride.
    let settingsViewModel: SettingsViewModel
    /// The Home hub view model (owns its own tracker for authorization).
    let homeViewModel: HomeViewModel

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
        calendar: Calendar,
        defaults: UserDefaults,
        storageNotice: String? = nil,
        supabaseProvider: SupabaseClientProvider?,
        appVersion: String,
        pendingDeletes: PendingRemoteDeleteStore,
        makeHomeTracker: () -> LocationTracking,
        makeRideTracker: @escaping () -> LocationTracking
    ) {
        self.repository = repository
        self.clock = clock
        self.detector = detector
        self.alertManager = alertManager
        self.storageNotice = storageNotice
        self.makeRideTracker = makeRideTracker
        let settings = SettingsViewModel(repository: repository, defaults: defaults)
        self.settingsViewModel = settings
        self.homeViewModel = HomeViewModel(
            repository: repository,
            clock: clock,
            calendar: calendar,
            tracker: makeHomeTracker()
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
    func makeRideSession() -> RideSessionViewModel {
        var tuning = RideTuning()
        tuning.accuracy = settingsViewModel.trackingAccuracy
        return RideSessionViewModel(
            tracker: makeRideTracker(),
            clock: clock,
            repository: repository,
            tuning: tuning
        )
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
        let (repository, storageNotice) = Self.makeLiveRepository()
        return AppEnvironment(
            repository: repository,
            clock: SystemClock(),
            detector: NoopDetector(),
            alertManager: StubAlertManager(),
            calendar: .current,
            defaults: .standard,
            storageNotice: storageNotice,
            supabaseProvider: SupabaseClientProvider(),
            appVersion: Self.appVersion(),
            pendingDeletes: UserDefaultsPendingRemoteDeleteStore(),
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

    private static func makeLiveRepository() -> (RideRepository, String?) {
        do {
            let container = try ModelContainer(for: RideRecord.self)
            return (SwiftDataRideRepository(context: container.mainContext), nil)
        } catch {
            // Degrade gracefully: an in-memory store keeps the app usable. Never
            // surface the raw framework error — a calm, app-written notice only
            // (Requirements 11.4 / design: SwiftData container failure is a
            // non-fatal notice, not a crash).
            let notice = "Saved rides are unavailable right now, so new rides won't be kept after you close the app. Everything else works."
            if let inMemory = try? ModelContainer(
                for: RideRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                return (SwiftDataRideRepository(context: inMemory.mainContext), notice)
            }
            return (InMemoryRideRepository(), notice)
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
        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            alertManager: StubAlertManager(),
            calendar: calendar,
            defaults: defaults,
            supabaseProvider: nil,
            appVersion: "preview",
            pendingDeletes: InMemoryPendingRemoteDeleteStore(),
            makeHomeTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) },
            makeRideTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) }
        )
    }
}
