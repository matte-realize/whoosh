import Foundation
@preconcurrency import HealthKit
import WhooshWire

/// Launches (or wakes) the Whoosh watch app from the phone so it can create its
/// keep-alive workout session (watch-companion spec task 16; design "Start from
/// the wrist" and the reconnect matrix; Requirement 10.3, 3.10). This is the
/// **only** phone file allowed to touch HealthKit (`HKHealthStore.startWatchApp`),
/// enforced by `scripts/privacy-check.sh` rule 20. It owns no workout session —
/// the session lives entirely on the watch (`WhooshWatch/Services/Workout/`); the
/// phone only asks the system to launch the watch app with a workout
/// configuration.
///
/// The system may take 30–60 s to wake a wrist-down watch (design feasibility
/// row 14), so `launch()` retries with a fixed backoff (3 tries, 15 s apart)
/// and reports the final outcome. A launch is used to *rescue* a watch the phone
/// sees as `installedUnreachable` during a ride, and to kick off the wrist-start
/// path; it is never required for a ride to run.
///
/// _Pending task 1 spike:_ task 1 (T10) must confirm whether the **iOS** target
/// needs the HealthKit capability/authorization for `startWatchApp`. The approved
/// O-W2 path assumes it does **not** (the watch target holds the capability), so
/// the iOS target does not declare HealthKit yet. If the spike shows the call
/// needs it, add the capability and an authorization step here and record it in
/// `spike-results.md`.
protocol WatchLaunching: Sendable {
    /// Ask the system to launch/wake the watch app for a cycling workout.
    /// Returns `true` once the launch call succeeds (the watch then creates the
    /// session itself); `false` after the retries are exhausted.
    func launch() async -> Bool
}

/// The real launcher over `HKHealthStore.startWatchApp(toHandle:)`.
///
/// `@unchecked Sendable`: `HKHealthStore` is not `Sendable`, but it is immutable
/// after init and used only through its own thread-safe API; `WatchLaunching`
/// requires `Sendable`, so the confinement is asserted here.
final class WatchLauncher: WatchLaunching, @unchecked Sendable {

    /// Retry schedule: 3 attempts, 15 s apart (design "retry backoff (3 × 15 s)").
    private let maxAttempts: Int
    private let retryDelay: Duration
    private let store: HKHealthStore?

    init(maxAttempts: Int = 3, retryDelay: Duration = .seconds(15)) {
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
        self.store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    func launch() async -> Bool {
        guard let store else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        for attempt in 1...maxAttempts {
            let launched = await Self.startWatchApp(store, configuration: configuration)
            if launched { return true }
            if attempt < maxAttempts {
                try? await Task.sleep(for: retryDelay)
            }
        }
        return false
    }

    /// One `startWatchApp` call bridged to async. The system then calls the
    /// watch's workout-configuration handler to create the session.
    private static func startWatchApp(
        _ store: HKHealthStore,
        configuration: HKWorkoutConfiguration
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            store.startWatchApp(with: configuration) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

/// The inert `WireLink` used when the Apple Watch setting is off or no watch is
/// usable (watch-companion design "`NoopWatchLink`"; Requirement 1.5). Every
/// send is a no-op success-free value, reachability is always false, and no
/// callback ever fires — so with the watch off the phone behaves exactly as
/// before (nothing is published, nothing is received).
final class NoopWatchLink: WireLink {
    init() {}

    func activate() async {}
    func onLiveMessage(_ handler: @escaping @Sendable (WireEnvelope) -> WireEnvelope?) async {}
    func onContext(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async {}
    func onQueued(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async {}
    func onReachabilityChange(_ handler: @escaping @Sendable (Bool) -> Void) async {}

    func send(_ envelope: WireEnvelope) async -> WireSendResult { .unreachable }
    func updateContext(_ envelope: WireEnvelope) async -> WireSendResult { .queued }
    func transfer(_ envelope: WireEnvelope) async -> WireSendResult { .queued }

    var isReachable: Bool { get async { false } }
}

/// A scriptable `WatchLaunching` for tests and previews: records every launch
/// attempt and returns a scripted result. An `actor` so the attempt count is
/// async-safe without a lock.
actor FakeWatchLauncher: WatchLaunching {
    private var _launchCount = 0
    private let result: Bool

    init(result: Bool = true) {
        self.result = result
    }

    /// How many times `launch()` was called.
    var launchCount: Int { _launchCount }

    func launch() async -> Bool {
        _launchCount += 1
        return result
    }
}
