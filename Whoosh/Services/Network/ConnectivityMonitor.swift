import Foundation

/// Reports network path reachability as a **retry trigger**, not a guarantee
/// (spec Requirement 12.1, design iOS capability investigation #11). A
/// "satisfied" path does not prove the backend is reachable; real request
/// outcomes remain ground truth. The coordinator uses `isOnline` / `onChange`
/// only to retry a queued alert sooner.
///
/// The concrete `NWPathConnectivityMonitor` wraps `NWPathMonitor` and makes no
/// network requests; `FakeConnectivityMonitor` backs the tests.
///
/// ## Contract
/// - **No requests.** An implementation observes path status only; it never
///   generates traffic. (`NWPathMonitor` is not a request API.)
/// - **Main-actor delivery.** `onChange` is invoked on the main actor so the
///   coordinator reacts without hopping actors.
/// - **Trigger, not truth.** `isOnline == true` is a hint to retry, not proof
///   of reachability.
///
/// `AnyObject` because the real monitor is a long-lived reference type owning a
/// system path monitor.
protocol ConnectivityMonitor: AnyObject {
    /// Whether the current network path is satisfied (a retry hint only).
    var isOnline: Bool { get }

    /// Invoked on the main actor whenever reachability changes, with the new
    /// `isOnline` value.
    var onChange: ((Bool) -> Void)? { get set }

    /// Begin observing path changes. Idempotent.
    func start()

    /// Stop observing and release the system monitor. Idempotent.
    func stop()
}
