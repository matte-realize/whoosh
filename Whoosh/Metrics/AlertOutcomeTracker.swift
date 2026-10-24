import Foundation

/// Tracks the per-alert delivery outcome so the fan-out can escalate a watch cue
/// to audio **at most once** and **never after the alert's TTL** (watch-companion
/// spec task 9; design "Fan-out, routing, and escalation": "The outcome tracker
/// (pure) per alert id"; Requirement 13.2, 13.6, 13.9).
///
/// Lifecycle per alert id: `pending → confirmed | escalated | expired`.
/// - `confirmed` when the watch reports the cue played (a `played` receipt).
/// - `escalated` once when the acknowledgement times out or the watch sink fails
///   and there is an audio channel to fall back to. A second escalation attempt
///   is refused.
/// - `expired` when the alert's TTL elapses before any acknowledgement; a stale
///   alert is never escalated.
///
/// Pure value type (Metrics layer: Models + Foundation only); the caller passes
/// `now` in, matching the other `Metrics/` policies. No `Clock` object, no
/// timers — the fan-out schedules the ack timeout and feeds events here.
struct AlertOutcomeTracker: Equatable, Sendable {

    /// The state of one tracked alert.
    enum Outcome: Equatable, Sendable {
        /// Delivered to the watch; waiting for an acknowledgement.
        case pending
        /// The watch acknowledged (played). Terminal.
        case confirmed
        /// Escalated to audio (no ack / failure, within TTL). Terminal.
        case escalated
        /// TTL elapsed before an ack; never escalated. Terminal.
        case expired
    }

    /// The decision the tracker returns when an ack timeout fires.
    enum EscalationDecision: Equatable, Sendable {
        /// Escalate now (first time, within TTL).
        case escalate
        /// Do nothing: already resolved, already escalated, or past TTL.
        case skip
    }

    private struct Entry: Equatable {
        var outcome: Outcome
        var firedAt: Date
        var ttl: TimeInterval
    }

    private var entries: [String: Entry] = [:]

    init() {}

    /// The current outcome for `id`, or `nil` if untracked.
    func outcome(for id: String) -> Outcome? { entries[id]?.outcome }

    /// Number of tracked alerts (after the last mutation).
    var count: Int { entries.count }

    /// Begin tracking an alert delivered to the watch at `now` with TTL `ttl`.
    /// Re-tracking the same id resets it to `pending` (a re-fired alert).
    mutating func track(id: String, firedAt now: Date, ttl: TimeInterval) {
        entries[id] = Entry(outcome: .pending, firedAt: now, ttl: ttl)
    }

    /// Record a watch acknowledgement (receipt `played`). Moves `pending →
    /// confirmed`; a no-op once terminal.
    mutating func confirm(id: String) {
        guard var entry = entries[id], entry.outcome == .pending else { return }
        entry.outcome = .confirmed
        entries[id] = entry
    }

    /// Decide whether the ack timeout should escalate `id` to audio, and record
    /// the result. Escalates only from `pending`, only within TTL, and only once.
    @discardableResult
    mutating func escalateOnTimeout(id: String, now: Date) -> EscalationDecision {
        guard var entry = entries[id], entry.outcome == .pending else { return .skip }
        // Past TTL → expire, never escalate.
        if now.timeIntervalSince(entry.firedAt) > entry.ttl {
            entry.outcome = .expired
            entries[id] = entry
            return .skip
        }
        entry.outcome = .escalated
        entries[id] = entry
        return .escalate
    }

    /// Mark a still-pending alert expired because its TTL elapsed. A no-op once
    /// terminal. Returns true when it transitioned to `expired`.
    @discardableResult
    mutating func expireIfStale(id: String, now: Date) -> Bool {
        guard var entry = entries[id], entry.outcome == .pending else { return false }
        guard now.timeIntervalSince(entry.firedAt) > entry.ttl else { return false }
        entry.outcome = .expired
        entries[id] = entry
        return true
    }

    /// Drop terminal (or stale) entries so the map stays bounded. Pending
    /// entries whose TTL has elapsed are first expired, then pruned.
    mutating func prune(now: Date) {
        for (id, entry) in entries where entry.outcome == .pending {
            if now.timeIntervalSince(entry.firedAt) > entry.ttl {
                entries[id]?.outcome = .expired
            }
        }
        entries = entries.filter { $0.value.outcome == .pending }
    }
}
