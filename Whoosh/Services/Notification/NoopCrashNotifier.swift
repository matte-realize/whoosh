import Foundation

/// The Tier 0 default `CrashNotifier`: no backend is wired, so every call throws
/// a non-retryable `serviceDisabled` error (spec design "Service protocols").
/// The coordinator treats this as "cannot send automatically" and goes straight
/// to the rider-initiated composer fallback — the full Tier 0 safety workflow
/// still demonstrates end to end, offline.
///
/// Contains **no network code**; it exists so the composition root always has a
/// non-optional notifier when crash alerts are off or the backend is not wired.
struct NoopCrashNotifier: CrashNotifier {
    init() {}

    func send(_ request: CrashNotificationRequest) async throws -> CrashNotificationResult {
        throw CrashNotifierError(.serviceDisabled)
    }

    func status(crashEventId: UUID, kind: CrashMessageKind) async throws -> CrashNotificationResult {
        throw CrashNotifierError(.serviceDisabled)
    }
}
