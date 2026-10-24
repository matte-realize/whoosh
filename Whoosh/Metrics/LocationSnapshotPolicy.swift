import Foundation

/// Pure policy that turns the freshest accepted route fix into a
/// `LocationSnapshot` for a crash alert (spec Requirements 7.2–7.4, 12.4;
/// design "Location snapshot policy").
///
/// Pure, framework-free (Metrics layer: Models + Foundation only), with static
/// functions like `RoutePrivacy`.
///
/// Rules:
/// - no fix ⇒ `.unavailable`
/// - age > `maxLocationAge` (30 min) ⇒ `.unavailable`
/// - age ≤ `currentFixMaxAge` (10 s) ⇒ `.current`
/// - otherwise ⇒ `.lastKnown` (with age + accuracy)
///
/// `snapshotForSend` re-reads the ride context at send time and uses the newer
/// fix if one exists, so the message carries age relative to the send instant
/// (Requirement 7.3). A one-shot location request is explicitly *not* made in
/// v1; we only use fixes the ride tracker already streamed.
enum LocationSnapshotPolicy {
    /// Build a snapshot from the freshest accepted fix (or `nil`) at `now`.
    static func snapshot(
        fromAcceptedFix fix: AcceptedFix?,
        now: Date,
        tuning: CrashResponseTuning
    ) -> LocationSnapshot {
        guard let fix else { return .unavailable }
        let age = now.timeIntervalSince(fix.time)
        // A fix from the future (clock skew) is treated as age 0 ⇒ current.
        let clampedAge = max(0, age)
        guard clampedAge <= tuning.maxLocationAge else { return .unavailable }
        let status: LocationFixStatus = clampedAge <= tuning.currentFixMaxAge ? .current : .lastKnown
        return LocationSnapshot(
            latitude: fix.latitude,
            longitude: fix.longitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            fixTime: fix.time,
            status: status
        )
    }

    /// Choose the snapshot to send: if a `latestAcceptedFix` exists at send time,
    /// re-evaluate it against `now`; otherwise keep the detection snapshot
    /// (Requirement 7.3). The newer fix is preferred because it is at least as
    /// fresh as the one captured at detection.
    static func snapshotForSend(
        detectionSnapshot: LocationSnapshot,
        latestAcceptedFix: AcceptedFix?,
        now: Date,
        tuning: CrashResponseTuning
    ) -> LocationSnapshot {
        guard latestAcceptedFix != nil else { return detectionSnapshot }
        return snapshot(fromAcceptedFix: latestAcceptedFix, now: now, tuning: tuning)
    }
}
