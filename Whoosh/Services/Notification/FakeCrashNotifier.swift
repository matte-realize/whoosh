import Foundation

/// Scriptable `CrashNotifier` for tests and previews. It performs **no network
/// work**; it returns scripted results or throws scripted typed errors so the
/// coordinator's send/retry/status logic can be driven deterministically.
///
/// `@MainActor` so its mutable call log is race-free (it conforms to the
/// `Sendable` `CrashNotifier` protocol by being main-actor isolated); the
/// coordinator under test is also main-actor isolated. Tests reach it via
/// `@testable import`.
///
/// ## Scripting
/// - `sendBehavior` decides what the next `send` does: succeed with scripted
///   recipient results, throw a typed error, or time out (throw `timeout`).
/// - `statusResults` maps a `crashEventId` to the result returned by `status`;
///   `defaultStatusBehavior` covers unmapped ids.
/// - `sendBehaviors` (a queue) lets a test script a sequence (e.g. a retryable
///   failure then a success) — consumed before `sendBehavior`.
@MainActor
final class FakeCrashNotifier: CrashNotifier {
    /// A scripted outcome for a `send` call.
    enum Behavior {
        /// Succeed, returning these per-recipient results (and `deduplicated`).
        case success(recipients: [CrashRecipientResult], deduplicated: Bool)
        /// Throw a typed request-level error.
        case failure(CrashNotifierError)
        /// Throw a `timeout` error (unknown outcome).
        case timeout

        /// Convenience: succeed with every recipient `queued`, one segment.
        static func allQueued(_ recipients: [CrashNotificationRecipient], at date: Date) -> Behavior {
            .success(
                recipients: recipients.map {
                    CrashRecipientResult(
                        recipientRef: $0.recipientRef,
                        status: .queued,
                        segments: 1,
                        updatedAt: date
                    )
                },
                deduplicated: false
            )
        }
    }

    /// A queue of scripted send behaviours, consumed first (front to back).
    var sendBehaviors: [Behavior] = []
    /// The fallback behaviour when `sendBehaviors` is empty.
    var sendBehavior: Behavior
    /// Per-event status results returned by `status`.
    var statusResults: [UUID: CrashNotificationResult] = [:]
    /// Behaviour for a `status` call with no mapped result.
    var defaultStatusBehavior: Behavior

    // MARK: Recorded interactions (for test assertions)

    /// Every request passed to `send`, in call order.
    private(set) var sendRequests: [CrashNotificationRequest] = []
    /// Number of `send` calls (call-count assertion: ≤ 1 per event initial send).
    var sendCallCount: Int { sendRequests.count }
    /// Every `(crashEventId, kind)` passed to `status`, in call order.
    private(set) var statusQueries: [(crashEventId: UUID, kind: CrashMessageKind)] = []
    /// Number of `status` calls.
    var statusCallCount: Int { statusQueries.count }

    init(
        sendBehavior: Behavior = .failure(CrashNotifierError(.serviceDisabled)),
        defaultStatusBehavior: Behavior = .failure(CrashNotifierError(.unknown))
    ) {
        self.sendBehavior = sendBehavior
        self.defaultStatusBehavior = defaultStatusBehavior
    }

    // MARK: CrashNotifier

    func send(_ request: CrashNotificationRequest) async throws -> CrashNotificationResult {
        sendRequests.append(request)
        let behavior = sendBehaviors.isEmpty ? sendBehavior : sendBehaviors.removeFirst()
        return try apply(behavior, crashEventId: request.crashEventId, kind: request.kind)
    }

    func status(crashEventId: UUID, kind: CrashMessageKind) async throws -> CrashNotificationResult {
        statusQueries.append((crashEventId, kind))
        if let mapped = statusResults[crashEventId] {
            return mapped
        }
        return try apply(defaultStatusBehavior, crashEventId: crashEventId, kind: kind)
    }

    // MARK: Helpers

    private func apply(
        _ behavior: Behavior,
        crashEventId: UUID,
        kind: CrashMessageKind
    ) throws -> CrashNotificationResult {
        switch behavior {
        case let .success(recipients, deduplicated):
            return CrashNotificationResult(
                crashEventId: crashEventId,
                kind: kind,
                deduplicated: deduplicated,
                recipients: recipients
            )
        case let .failure(error):
            throw error
        case .timeout:
            throw CrashNotifierError(.timeout)
        }
    }
}
