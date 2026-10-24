import Foundation

/// The pure crash-countdown model on the wrist (watch-companion design
/// "`ElapsedTimeProjector` and `CrashCountdownModel`"; Requirement 15). It
/// projects the relative remaining time with the watch's own monotonic clock
/// (no wall-clock subtraction), produces the displayed seconds, the VoiceOver
/// announcement schedule (start, every 10 s, last 5 s), the haptic repeat
/// schedule (every 3 s, then every 1.5 s in the last 10 s, at most 20 repeats),
/// and moves through the lifecycle based on replies and status.
public struct CrashCountdownModel: Sendable {
    public enum Phase: Equatable, Sendable {
        case hidden
        case countdown
        case cancelling(commandId: String)
        case cancelled
        case tooLate
        case sending
        case sent
        case queued
        case failed
    }

    public private(set) var phase: Phase = .hidden
    /// Remaining ms at the moment the status was received.
    private var remainingAtReceiptMs: Int = 0
    /// The watch monotonic time at receipt.
    private var receiptNowMs: Int = 0
    public private(set) var eventId: String?
    public private(set) var isDrill: Bool = false
    public private(set) var contactCount: Int = 0

    // Schedule bookkeeping.
    private var lastHapticMs: Int?
    private var hapticCount = 0
    private var lastAnnouncedSecond: Int?

    public static let maxHaptics = 20

    public init() {}

    /// Begin / refresh the countdown from a status's crash sub-object.
    public mutating func apply(_ crash: WireCrashStatus, nowMs: Int) {
        eventId = crash.eventId
        isDrill = crash.isDrill
        contactCount = crash.contactCount
        remainingAtReceiptMs = max(0, crash.remainingMs)
        receiptNowMs = nowMs
        switch crash.phase {
        case .countdown:
            // Keep a local cancelling state if we are mid-cancel for this event.
            if case .cancelling = phase { break }
            phase = .countdown
        case .cancelled:
            phase = .cancelled
        case .sending:
            phase = .sending
        case .sent:
            phase = .sent
        case .queuedOffline:
            phase = .queued
        case .failed, .stale:
            phase = .failed
        case .unknown:
            break
        }
    }

    /// No countdown present in the status — hide.
    public mutating func clear() {
        phase = .hidden
        eventId = nil
        lastHapticMs = nil
        hapticCount = 0
        lastAnnouncedSecond = nil
    }

    /// Remaining ms projected to monotonic `nowMs` (never negative).
    public func remainingMs(nowMs: Int) -> Int {
        max(0, remainingAtReceiptMs - (nowMs - receiptNowMs))
    }

    /// Whole seconds shown on the wrist (rounded up so "1" shows until 0).
    public func displayedSeconds(nowMs: Int) -> Int {
        let ms = remainingMs(nowMs: nowMs)
        return (ms + 999) / 1_000
    }

    /// The rider tapped Cancel. Moves to `cancelling` with the command id.
    public mutating func cancel(commandId: String) {
        guard phase == .countdown else { return }
        phase = .cancelling(commandId: commandId)
    }

    /// A reply to the cancel arrived with the concrete detail.
    public mutating func applyCancelReply(detail: WireCommandDetail) {
        guard case .cancelling = phase else { return }
        switch detail {
        case .cancelled:
            phase = .cancelled
        case .tooLate:
            phase = .tooLate
        case .notCancellable:
            phase = .failed
        default:
            break
        }
    }

    public var isActive: Bool {
        switch phase {
        case .countdown, .cancelling: return true
        default: return false
        }
    }

    /// Whether a VoiceOver announcement is due at `nowMs` (start, every 10 s,
    /// and each of the last 5 s). Returns the second to announce, or nil.
    public mutating func announcementDue(nowMs: Int) -> Int? {
        guard isActive else { return nil }
        let secs = displayedSeconds(nowMs: nowMs)
        if lastAnnouncedSecond == secs { return nil }
        let due = lastAnnouncedSecond == nil      // first show
            || secs % 10 == 0                      // every 10 s
            || secs <= 5                           // last 5 s
        if due {
            lastAnnouncedSecond = secs
            return secs
        }
        return nil
    }

    /// Whether a haptic repeat is due at `nowMs` (every 3 s; every 1.5 s in the
    /// last 10 s; at most `maxHaptics`). Mutates the schedule when it fires.
    public mutating func hapticDue(nowMs: Int) -> Bool {
        guard isActive, hapticCount < Self.maxHaptics else { return false }
        let remaining = remainingMs(nowMs: nowMs)
        let interval = remaining <= 10_000 ? 1_500 : 3_000
        guard let last = lastHapticMs else {
            // First haptic fires immediately on show.
            lastHapticMs = nowMs
            hapticCount += 1
            return true
        }
        if nowMs - last >= interval {
            lastHapticMs = nowMs
            hapticCount += 1
            return true
        }
        return false
    }
}
