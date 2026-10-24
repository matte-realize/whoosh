import Foundation
import Network

/// The system `ConnectivityMonitor`: wraps `NWPathMonitor` to report
/// reachability as a **retry trigger** for queued crash alerts (spec Requirement
/// 12.1, 16.2, design iOS capability investigation #11).
///
/// - **Makes no network requests.** `NWPathMonitor` observes the system network
///   path only; it never generates traffic. (It is not a request API, so the
///   privacy script's network rule does not apply to it.)
/// - **Main-actor delivery.** `NWPathMonitor` calls its update handler on a
///   background queue; this type hops to the main actor before updating
///   `isOnline` and invoking `onChange`, so the coordinator reacts without
///   hopping actors. Changes are de-duplicated (only actual transitions fire).
/// - **Trigger, not truth.** A satisfied path does not prove the backend is
///   reachable; real request outcomes remain ground truth.
///
/// Main-actor isolated (default isolation): mutable state and callbacks live on
/// the main actor; the underlying monitor runs on its own queue.
final class NWPathConnectivityMonitor: ConnectivityMonitor {
    private(set) var isOnline: Bool = false
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.whoosh.connectivity-monitor")
    private var isObserving = false

    init() {}

    func start() {
        guard !isObserving else { return }
        isObserving = true

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            // NWPathMonitor delivers on a background queue; hop to the main
            // actor before touching state or invoking the callback.
            Task { @MainActor [weak self] in
                self?.apply(online: online)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        monitor.cancel()
    }

    private func apply(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        onChange?(online)
    }
}
