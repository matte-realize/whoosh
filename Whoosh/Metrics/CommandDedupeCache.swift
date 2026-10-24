import Foundation
import WhooshWire

/// A pure, bounded cache of completed wrist-command replies keyed by
/// `commandId` (watch-companion task 6, design "`RemoteCommandReducer`"; the
/// `CommandDedupeCache` box in the command pipeline; Requirement 6.2, 7.2–7.7).
///
/// WatchConnectivity can deliver the same `sendMessage` more than once, and the
/// watch retries the same `commandId` at 0 / 2.5 / 5 s when a reply is lost. The
/// phone must apply a command **at most once** and answer a repeat with the
/// identical reply it already computed, so a retried pause never double-pauses
/// and a retried `requestStart` never starts two rides.
///
/// The cache is a value type (no class, no actor): `RemoteCommandReducer`
/// consults it first (row 1) and the caller stores the computed reply back with
/// `recording(_:at:)`. Entries expire after `windowMs` (default 5 min) and the
/// cache is capped at `maxEntries` (default 128); inserting past the cap evicts
/// the oldest entry (by recorded time). Pure and framework-free beyond the
/// Foundation-only `WhooshWire` reply shape — no `Clock` object; `now` is passed
/// in, matching the other `Metrics/` policies.
struct CommandDedupeCache: Equatable, Sendable {
    /// A cached reply and when it was recorded.
    struct Entry: Equatable, Sendable {
        /// The concrete reply fields to replay on a duplicate (the reducer
        /// re-embeds a fresh status around these, so the status is not cached).
        var reply: CachedReply
        /// When the reply was recorded (used for expiry and LRU-ish eviction).
        var recordedAt: Date
    }

    /// The replay-able part of a reply: everything except the live status, which
    /// the reducer attaches fresh on every answer so the watch reconciles from
    /// current state.
    struct CachedReply: Equatable, Sendable {
        var outcome: WireCommandOutcome
        var reason: WireCommandReason?
        var detail: WireCommandDetail?
        var newRideId: String?

        init(
            outcome: WireCommandOutcome,
            reason: WireCommandReason? = nil,
            detail: WireCommandDetail? = nil,
            newRideId: String? = nil
        ) {
            self.outcome = outcome
            self.reason = reason
            self.detail = detail
            self.newRideId = newRideId
        }
    }

    /// Expiry window in milliseconds (default 5 min; clamped by `WatchTuning`).
    let windowMs: Int
    /// Maximum retained entries (default 128; clamped by `WatchTuning`).
    let maxEntries: Int

    private var entries: [String: Entry]

    init(windowMs: Int = WatchTuning().dedupeWindowMs,
         maxEntries: Int = WatchTuning().dedupeMaxEntries) {
        self.windowMs = windowMs
        self.maxEntries = maxEntries
        self.entries = [:]
    }

    /// Convenience initializer from a `WatchTuning` (keeps the two values in one
    /// place).
    init(tuning: WatchTuning) {
        self.init(windowMs: tuning.dedupeWindowMs, maxEntries: tuning.dedupeMaxEntries)
    }

    /// Number of currently retained entries (after the last mutation).
    var count: Int { entries.count }

    /// The cached reply for `commandId` if present and not expired at `now`.
    /// An expired entry returns `nil` (it is pruned on the next mutation).
    func cachedReply(for commandId: String, at now: Date) -> CachedReply? {
        guard let entry = entries[commandId] else { return nil }
        if isExpired(entry, at: now) { return nil }
        return entry.reply
    }

    /// Whether a live, non-expired reply exists for `commandId`.
    func contains(_ commandId: String, at now: Date) -> Bool {
        cachedReply(for: commandId, at: now) != nil
    }

    /// Record `reply` for `commandId` at `now`, pruning expired entries and
    /// evicting the oldest if the cache would exceed `maxEntries`.
    ///
    /// Recording the same id again (an out-of-order duplicate) overwrites the
    /// entry and refreshes its timestamp; the reply content is expected to be
    /// identical because the reducer is deterministic.
    mutating func recording(_ commandId: String, reply: CachedReply, at now: Date) {
        pruneExpired(at: now)
        entries[commandId] = Entry(reply: reply, recordedAt: now)
        evictOverflow()
    }

    /// Drop every entry older than the window at `now`.
    mutating func pruneExpired(at now: Date) {
        entries = entries.filter { !isExpired($0.value, at: now) }
    }

    // MARK: - Private

    private func isExpired(_ entry: Entry, at now: Date) -> Bool {
        let ageMs = now.timeIntervalSince(entry.recordedAt) * 1_000
        return ageMs >= Double(windowMs)
    }

    private mutating func evictOverflow() {
        guard entries.count > maxEntries else { return }
        // Evict the oldest entries by `recordedAt` until within the cap.
        let sorted = entries.sorted { lhs, rhs in
            if lhs.value.recordedAt == rhs.value.recordedAt {
                return lhs.key < rhs.key // deterministic tie-break
            }
            return lhs.value.recordedAt < rhs.value.recordedAt
        }
        let overflow = entries.count - maxEntries
        for (key, _) in sorted.prefix(overflow) {
            entries.removeValue(forKey: key)
        }
    }
}
