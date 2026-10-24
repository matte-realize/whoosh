import Foundation

/// The in-memory log of the last few notices for the current ride
/// (watch-companion design "`WatchNoticeLog`"; Requirement 14.3). Memory only,
/// current ride only — discarded on a new ride, never persisted (privacy
/// steering: "Notice log … Discarded at the next ride; never persisted").
///
/// Keeps at most `capacity` entries (default `WatchTuning.noticeLogSize`, 10),
/// newest last; a replay/reconnect fill-in is logged without re-buzzing (the
/// buzz decision belongs to `WristHapticLimiter`). Tracks an unread count for
/// the Notices badge.
public struct WatchNoticeLog: Equatable, Sendable {
    /// One logged notice: kind, time-into-ride (ms), an optional camera reason,
    /// and whether it is still unread. No free text (Requirement 19.1).
    public struct Entry: Equatable, Sendable {
        public var alertId: String
        public var kind: WireAlertKind
        public var tier: WireAlertTier
        public var timeIntoRideMs: Int
        public var reason: WireCameraReason?
        public var unread: Bool

        public init(
            alertId: String,
            kind: WireAlertKind,
            tier: WireAlertTier,
            timeIntoRideMs: Int,
            reason: WireCameraReason? = nil,
            unread: Bool = true
        ) {
            self.alertId = alertId
            self.kind = kind
            self.tier = tier
            self.timeIntoRideMs = timeIntoRideMs
            self.reason = reason
            self.unread = unread
        }
    }

    public let capacity: Int
    public private(set) var entries: [Entry] = []

    public init(capacity: Int = WatchTuning().noticeLogSize) {
        self.capacity = max(1, capacity)
    }

    /// Number of unread entries (for the badge).
    public var unreadCount: Int { entries.lazy.filter(\.unread).count }

    /// Record a notice from an alert. A `replay` alert is logged already-read
    /// so it never contributes to the unread badge or implies a fresh buzz.
    public mutating func record(_ alert: WireAlert, timeIntoRideMs: Int) {
        // Do not log a duplicate id twice.
        guard !entries.contains(where: { $0.alertId == alert.alertId }) else { return }
        let entry = Entry(
            alertId: alert.alertId,
            kind: alert.kind,
            tier: alert.tier,
            timeIntoRideMs: max(0, timeIntoRideMs),
            reason: alert.reason,
            unread: !alert.replay
        )
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Mark every entry read (the rider opened the Notices page).
    public mutating func markAllRead() {
        for i in entries.indices { entries[i].unread = false }
    }

    /// Clear the log for a new ride.
    public mutating func reset() {
        entries.removeAll(keepingCapacity: true)
    }
}
