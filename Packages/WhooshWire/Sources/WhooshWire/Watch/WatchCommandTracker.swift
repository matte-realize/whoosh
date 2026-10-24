import Foundation

/// Tracks the lifecycle of a wrist command (watch-companion design
/// "`WatchCommandTracker`"; Requirement 6.5–6.9, 20.5). Pure and skew-free: the
/// caller supplies the monotonic watch time (`nowMs`); the tracker decides when
/// to send, retry (same id), give up, and what the controls show.
///
/// A command goes `idle → pending(attempt, deadline) → confirmed | notConfirmed`.
/// Retries reuse the **same `commandId`** at 0 / 2.5 / 5 s (so the phone dedupes
/// a duplicate rather than acting twice). On TTL expiry the command is
/// `notConfirmed` and the watch reconciles from the next status — it never
/// auto re-issues. Link loss fails every pending command immediately so the
/// controls disable within 1 s. The crash-cancel command is the exception: it
/// retries every 1 s until its deadline and also goes out as a queue copy.
public struct WatchCommandTracker: Sendable {
    public let tuning: WatchTuning

    public enum Status: Equatable, Sendable {
        case idle
        case pending
        case confirmed
        case notConfirmed
    }

    /// A tracked command.
    public struct Pending: Equatable, Sendable {
        public var commandId: String
        public var kind: WireCommandKind
        public var attempt: Int
        public var firstSentMs: Int
        public var lastSentMs: Int
        public var deadlineMs: Int
        public var isCrashCancel: Bool
    }

    /// What the tracker asks the caller to do.
    public enum Effect: Equatable, Sendable {
        /// Send (or re-send) this command now.
        case send(commandId: String, kind: WireCommandKind, attempt: Int, queueCopy: Bool)
        /// The command gave up; show "Not confirmed" and reconcile from status.
        case notConfirmed(commandId: String, kind: WireCommandKind)
        /// A reply confirmed the command.
        case confirmed(commandId: String, kind: WireCommandKind)
        /// A tap was rejected locally (spacing or already pending).
        case rejectedLocally(kind: WireCommandKind)
    }

    private var pending: [String: Pending] = [:]
    private var lastTapMs: Int?

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    /// Current controls-disabling status for a kind (pending disables the tap).
    public var hasPending: Bool { !pending.isEmpty }

    public func status(forCommandId id: String) -> Status {
        pending[id] == nil ? .idle : .pending
    }

    /// Retry offsets (ms) for a normal command's attempts 1, 2, 3.
    public static let retryOffsetsMs = [0, 2_500, 5_000]

    /// The rider tapped a control. Enforces the 500 ms spacing and "already
    /// pending" (one of this kind at a time). Returns the effect to perform.
    public mutating func tap(
        commandId: String,
        kind: WireCommandKind,
        nowMs: Int,
        isCrashCancel: Bool = false
    ) -> Effect {
        // Spacing between distinct commands.
        if let last = lastTapMs, nowMs - last < tuning.commandMinSpacingMs {
            return .rejectedLocally(kind: kind)
        }
        // Already a pending command of this kind.
        if pending.values.contains(where: { $0.kind == kind }) {
            return .rejectedLocally(kind: kind)
        }
        lastTapMs = nowMs
        let p = Pending(
            commandId: commandId,
            kind: kind,
            attempt: 1,
            firstSentMs: nowMs,
            lastSentMs: nowMs,
            deadlineMs: nowMs + tuning.commandTtlMs,
            isCrashCancel: isCrashCancel
        )
        pending[commandId] = p
        return .send(commandId: commandId, kind: kind, attempt: 1, queueCopy: isCrashCancel)
    }

    /// A reply arrived for `commandId`. Clears it and reports confirmed.
    public mutating func reply(commandId: String) -> Effect? {
        guard let p = pending.removeValue(forKey: commandId) else { return nil }
        return .confirmed(commandId: p.commandId, kind: p.kind)
    }

    /// The retry/TTL timer fired at `nowMs`. Returns any resends or give-ups.
    public mutating func tick(nowMs: Int) -> [Effect] {
        var effects: [Effect] = []
        for (id, var p) in pending {
            // TTL expiry → not confirmed; reconcile from status (no re-issue).
            if nowMs >= p.deadlineMs {
                pending.removeValue(forKey: id)
                effects.append(.notConfirmed(commandId: id, kind: p.kind))
                continue
            }
            let sinceLast = nowMs - p.lastSentMs
            if p.isCrashCancel {
                // Crash cancel: retry every 1 s until the deadline, with a queue copy.
                if sinceLast >= 1_000 {
                    p.attempt += 1
                    p.lastSentMs = nowMs
                    pending[id] = p
                    effects.append(.send(commandId: id, kind: p.kind,
                                         attempt: p.attempt, queueCopy: true))
                }
            } else {
                // Normal command: attempts at 0 / 2.5 / 5 s (same id).
                let nextAttempt = p.attempt + 1
                guard nextAttempt <= Self.retryOffsetsMs.count,
                      nextAttempt <= tuning.commandMaxAttempts else { continue }
                let dueAt = p.firstSentMs + Self.retryOffsetsMs[nextAttempt - 1]
                if nowMs >= dueAt {
                    p.attempt = nextAttempt
                    p.lastSentMs = nowMs
                    pending[id] = p
                    effects.append(.send(commandId: id, kind: p.kind,
                                         attempt: nextAttempt, queueCopy: false))
                }
            }
        }
        return effects
    }

    /// The link was lost. Every pending command fails immediately (controls
    /// disable within 1 s).
    public mutating func linkLost() -> [Effect] {
        let effects = pending.values.map {
            Effect.notConfirmed(commandId: $0.commandId, kind: $0.kind)
        }
        pending.removeAll()
        return effects
    }
}
