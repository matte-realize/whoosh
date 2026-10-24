import Foundation

/// One probable-crash occurrence (spec design "Entities", Requirement 6.2).
/// Identified by `id` (= the `crashEventId` idempotency key), generated once at
/// detection and persisted with its state so a relaunch cannot restart it.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
/// - `detectedAt` / `utcOffsetMinutes`: detection time and the rider's UTC
///   offset (Requirement 7.1).
/// - `isDrill`: a simulated crash uses the `drill` template and does not consume
///   the per-ride cap.
/// - `source` / `confidence`: a short detector source label and a 0...1 score.
/// - `rideId`: optional read-only ride id, when available.
/// - `state`: the current `CrashEventState`.
/// - `countdown`: the absolute-deadline countdown while in `countdown` state.
/// - `suppressedUntil`: the end of the suppression window after a cancel/send.
/// - `locationAtDetection`: the snapshot captured at detection.
/// - `footageRef`: a local-only footage reference, or `nil` ("no footage").
/// - `outcome`: how the countdown ended, when known.
struct CrashEvent: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    let detectedAt: Date
    let utcOffsetMinutes: Int
    let isDrill: Bool
    let source: String
    let confidence: Double
    let rideId: UUID?
    var state: CrashEventState
    var countdown: CountdownState?
    var suppressedUntil: Date?
    var locationAtDetection: LocationSnapshot
    var footageRef: String?
    var outcome: CountdownOutcome?

    init(
        id: UUID,
        detectedAt: Date,
        utcOffsetMinutes: Int,
        isDrill: Bool,
        source: String,
        confidence: Double,
        rideId: UUID?,
        state: CrashEventState,
        countdown: CountdownState?,
        suppressedUntil: Date?,
        locationAtDetection: LocationSnapshot,
        footageRef: String?,
        outcome: CountdownOutcome?
    ) {
        self.id = id
        self.detectedAt = detectedAt
        self.utcOffsetMinutes = utcOffsetMinutes
        self.isDrill = isDrill
        self.source = source
        self.confidence = confidence
        self.rideId = rideId
        self.state = state
        self.countdown = countdown
        self.suppressedUntil = suppressedUntil
        self.locationAtDetection = locationAtDetection
        self.footageRef = footageRef
        self.outcome = outcome
    }
}
