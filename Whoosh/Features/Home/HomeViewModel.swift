import Foundation
import Observation

/// View model for the Home hub (Requirements 13, 2.2–2.4, 1.1).
///
/// Loads finished rides via `RideRepository`, computes the current week's
/// dashboard numbers with `WeeklyStatsCalculator` using an injected `Clock` and
/// `Calendar` (so the result is deterministic and testable), and maps the
/// location authorization status to a `HomeState` that the view renders. It
/// observes authorization changes through `LocationTracking.onAuthorizationChange`
/// so the UI reflects a change (including returning from Settings) without a
/// restart (Requirement 2.4).
///
/// UI-framework-free (no SwiftUI import), per the layering table; it depends only
/// on model types, the Metrics layer, and service protocols.
@Observable
final class HomeViewModel {
    /// What the Home screen should show: the normal dashboard, or the
    /// non-blocking location-denied state (Requirement 13.8 / 2.2).
    enum HomeState: Equatable {
        /// Location is available (or not yet determined) — show the dashboard
        /// with a "GPS ready" chip once authorized. `notDetermined` still shows
        /// the dashboard; the first Start Ride triggers the permission prompt.
        case ready
        /// `notDetermined`: show the dashboard but the first start will prompt.
        case needsPermission
        /// Permission denied or restricted — show the denied help state.
        case denied
        /// Location services are off device-wide — same non-blocking path.
        case servicesDisabled
    }

    @ObservationIgnored private let repository: RideRepository
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let tracker: LocationTracking

    /// The maximum number of rides shown in the "Recent rides" list (mockup 1).
    static let recentRidesLimit = 3

    /// All finished rides, most-recent-first (drives Recent + weekly stats).
    private(set) var rides: [Ride] = []
    /// Current location authorization, mirrored from the tracker and updated on
    /// change so the UI reacts live.
    private(set) var authorizationStatus: LocationAuthorizationStatus

    init(
        repository: RideRepository,
        clock: Clock,
        calendar: Calendar = .current,
        tracker: LocationTracking
    ) {
        self.repository = repository
        self.clock = clock
        self.calendar = calendar
        self.tracker = tracker
        self.authorizationStatus = tracker.authorizationStatus
        wireAuthorizationObservation()
        load()
    }

    // MARK: - Derived state

    /// Which top-level Home state to render, derived from authorization.
    var state: HomeState {
        switch authorizationStatus {
        case .notDetermined:
            return .needsPermission
        case .denied:
            return .denied
        case .restricted:
            return .denied
        case .authorizedWhenInUse, .authorizedAlways:
            return .ready
        }
    }

    /// `true` when the dashboard (rather than the denied state) should show.
    var showsDashboard: Bool {
        switch state {
        case .ready, .needsPermission: return true
        case .denied, .servicesDisabled: return false
        }
    }

    /// The weekly stats for the week containing "now", computed from finished
    /// rides (Requirement 13.2/13.4). Empty week yields zeros (Requirement 13.6).
    /// Demo rides are excluded so the This-Week numbers stay honest (demo-mode
    /// spec O-DM2); the pure `WeeklyStatsCalculator` stays demo-unaware and the
    /// caller does the filtering here.
    var weeklyStats: WeeklyStats {
        WeeklyStatsCalculator.compute(
            rides: rides.filter { !$0.isDemo },
            now: clock.now(),
            calendar: calendar
        )
    }

    /// The latest finished rides, capped at `recentRidesLimit`, most-recent-first.
    var recentRides: [Ride] {
        Array(rides.prefix(Self.recentRidesLimit))
    }

    /// `true` when there are no finished rides at all — drives the friendly
    /// empty state on the Recent list (Requirement 1.2 / 13.6).
    var hasNoRides: Bool { rides.isEmpty }

    // MARK: - Intents

    /// (Re)load finished rides from the repository, most-recent-first. Corrupt
    /// records are skipped by the repository (Requirement 7.7). Called on init
    /// and whenever Home reappears (e.g. after a ride or a delete).
    func load() {
        let all = (try? repository.allRides()) ?? []
        rides = all.filter { $0.endedAt != nil }
    }

    /// Request location authorization when the user taps Start Ride and status
    /// is still `notDetermined` (Requirement 2.1). The actual ride lifecycle is
    /// owned by `RideSessionViewModel`; Home only nudges the prompt.
    func requestLocationIfNeeded() {
        if authorizationStatus == .notDetermined {
            tracker.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Authorization observation

    private func wireAuthorizationObservation() {
        tracker.onAuthorizationChange = { [weak self] status in
            self?.authorizationStatus = status
        }
    }
}
