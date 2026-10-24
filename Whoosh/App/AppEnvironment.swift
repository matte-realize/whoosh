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

    /// Demo mode's controller (demo-mode tasks 8–9). Built **always** but inert
    /// while its toggle is off, so the off path is the exact normal path
    /// (Requirement 9.1). The only composition-root branch on demo state lives
    /// in `makeRideSession()`.
    let demo: DemoModeController

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
        makeHomeTracker: () -> LocationTracking,
        makeRideTracker: @escaping () -> LocationTracking
    ) {
        self.repository = repository
        self.clock = clock
        self.detector = detector
        self.alertManager = alertManager
        self.storageNotice = storageNotice
        self.makeRideTracker = makeRideTracker
        self.settingsViewModel = SettingsViewModel(repository: repository, defaults: defaults)
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
        let settings = self.settingsViewModel
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
    func makeRideSession() -> RideSessionViewModel {
        if let simulated = demo.simulatedSession {
            return simulated
        }
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
        let clock = SystemClock()
        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            // Ship the real alert manager app-wide (D-DM5): it is inert until
            // `fire(_:)` is called, so normal mode is unchanged (the rear-alert
            // gate won't call it until a real detector exists), and the demo's
            // forced-alert path produces real haptics/audio.
            alertManager: HapticAudioAlertManager(clock: clock),
            calendar: .current,
            defaults: .standard,
            storageNotice: storageNotice,
            makeHomeTracker: { CoreLocationTracker() },
            makeRideTracker: { CoreLocationTracker() }
        )
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
            makeHomeTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) },
            makeRideTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) }
        )
    }
}
