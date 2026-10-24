import Foundation

/// Scriptable `CrashDetector` for tests and SwiftUI previews.
///
/// Lives under `Services/Crash/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Tests drive it imperatively: call `emit(confidence:source:isDrill:)` (or the
/// convenience `emitDrill()`) to deliver a `CrashSignal` through `onSignal`. The
/// callback fires synchronously so test expectations are deterministic. Signals
/// are only delivered while the detector is "started" (matching real detectors
/// that observe nothing before `start()`); a signal emitted while stopped is
/// recorded but not delivered.
final class FakeCrashDetector: CrashDetector {
    var onSignal: ((CrashSignal) -> Void)?

    /// `true` between `start()` and `stop()`.
    private(set) var isMonitoring = false
    /// Number of times `start()` was called.
    private(set) var startCount = 0
    /// Number of times `stop()` was called.
    private(set) var stopCount = 0
    /// Every signal passed to `emit(...)`, whether or not it was delivered.
    private(set) var emitted: [CrashSignal] = []
    /// Every signal actually delivered through `onSignal` (monitoring only).
    private(set) var delivered: [CrashSignal] = []

    /// A fixed timestamp used when `emit` is called without one, so tests that
    /// do not inject a clock still get a deterministic value.
    private let defaultTimestamp: Date

    init(defaultTimestamp: Date = Date(timeIntervalSince1970: 0)) {
        self.defaultTimestamp = defaultTimestamp
    }

    // MARK: CrashDetector

    func start() {
        isMonitoring = true
        startCount += 1
    }

    func stop() {
        isMonitoring = false
        stopCount += 1
    }

    // MARK: Scripting API (test/preview driven)

    /// Deliver a probable-crash signal. Delivered through `onSignal` only while
    /// monitoring; always appended to `emitted` for assertions.
    @discardableResult
    func emit(
        timestamp: Date? = nil,
        confidence: Double = 1.0,
        source: String = "fake",
        isDrill: Bool = false
    ) -> CrashSignal {
        let signal = CrashSignal(
            timestamp: timestamp ?? defaultTimestamp,
            confidence: confidence,
            source: source,
            isDrill: isDrill
        )
        emitted.append(signal)
        if isMonitoring {
            delivered.append(signal)
            onSignal?(signal)
        }
        return signal
    }

    /// Convenience: emit a full-confidence drill signal.
    @discardableResult
    func emitDrill(timestamp: Date? = nil, source: String = "simulator") -> CrashSignal {
        emit(timestamp: timestamp, confidence: 1.0, source: source, isDrill: true)
    }
}
