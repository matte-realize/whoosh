import Foundation

/// Scriptable `AlertSink` for tests and previews (rear-camera spec task 13).
///
/// Lives under `Services/Alerts/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`. It
/// records delivered alerts, can be marked unavailable, and can be scripted to
/// throw so the fan-out's isolation is exercised.
///
/// `@MainActor` so its mutable log is race-free; the fan-out that drives it is
/// also main-actor isolated.
@MainActor
final class FakeAlertSink: AlertSink {
    let channel: AlertChannel
    var isAvailable: Bool
    /// When true, `deliver` throws (modelling a local sink failure).
    var shouldThrow = false

    /// Every alert delivered through this sink, in order.
    private(set) var delivered: [(kind: AlertKind, context: AlertDeliveryContext)] = []

    init(channel: AlertChannel, isAvailable: Bool = true) {
        self.channel = channel
        self.isAvailable = isAvailable
    }

    struct SinkError: Error {}

    func deliver(_ kind: AlertKind, context: AlertDeliveryContext) throws {
        if shouldThrow { throw SinkError() }
        delivered.append((kind, context))
    }
}
