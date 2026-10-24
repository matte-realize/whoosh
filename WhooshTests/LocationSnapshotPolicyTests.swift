import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `LocationSnapshotPolicy` (crash-response task 5,
/// Requirements 7.2–7.4, 12.4; design "Location snapshot policy"). Written
/// test-first.
///
/// The policy turns the freshest **accepted** route fix into a
/// `LocationSnapshot`:
/// - age ≤ `currentFixMaxAge` (10 s)  ⇒ `.current`
/// - older, but ≤ `maxLocationAge` (30 min) ⇒ `.lastKnown` with age + accuracy
/// - no fix, or older than `maxLocationAge` ⇒ `.unavailable`
/// The send-time refresh picks the newer fix.
struct LocationSnapshotPolicyTests {
    private let tuning = CrashResponseTuning()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func fix(ageSeconds: TimeInterval, accuracy: Double = 12) -> AcceptedFix {
        AcceptedFix(
            latitude: 42.3601,
            longitude: -71.0589,
            horizontalAccuracy: accuracy,
            time: now.addingTimeInterval(-ageSeconds)
        )
    }

    // MARK: no fix

    @Test func noFixIsUnavailable() {
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: nil, now: now, tuning: tuning)
        #expect(snap.status == .unavailable)
        #expect(snap.latitude == nil)
        #expect(snap.longitude == nil)
        #expect(snap == .unavailable)
    }

    // MARK: current

    @Test func freshFixIsCurrent() {
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 3), now: now, tuning: tuning)
        #expect(snap.status == .current)
        #expect(snap.latitude == 42.3601)
        #expect(snap.longitude == -71.0589)
        #expect(snap.horizontalAccuracy == 12)
        #expect(snap.age(at: now) == 3)
    }

    @Test func fixAtExactlyCurrentBoundaryIsCurrent() {
        // age == 10 s (currentFixMaxAge) is still "current".
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 10), now: now, tuning: tuning)
        #expect(snap.status == .current)
    }

    // MARK: last known

    @Test func olderFixIsLastKnown() {
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 45), now: now, tuning: tuning)
        #expect(snap.status == .lastKnown)
        #expect(snap.age(at: now) == 45)
        #expect(snap.horizontalAccuracy == 12)
    }

    @Test func fixJustOverCurrentBoundaryIsLastKnown() {
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 11), now: now, tuning: tuning)
        #expect(snap.status == .lastKnown)
    }

    @Test func fixAtMaxLocationAgeBoundaryIsLastKnown() {
        // age == 30 min (maxLocationAge) is still usable as last-known.
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 30 * 60), now: now, tuning: tuning)
        #expect(snap.status == .lastKnown)
    }

    // MARK: stale / unavailable

    @Test func fixOlderThanMaxAgeIsUnavailable() {
        let snap = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 30 * 60 + 1), now: now, tuning: tuning)
        #expect(snap.status == .unavailable)
        // An unavailable snapshot carries no coordinates (Requirement 7.2).
        #expect(snap.latitude == nil)
        #expect(snap.longitude == nil)
    }

    // MARK: send-time refresh (Requirement 7.3)

    @Test func refreshPicksNewerFix() {
        let detection = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 60), now: now, tuning: tuning)
        let sendNow = now.addingTimeInterval(30)
        // A brand-new fix exists at send time.
        let newer = AcceptedFix(
            latitude: 42.0, longitude: -71.0, horizontalAccuracy: 8,
            time: sendNow.addingTimeInterval(-2)
        )
        let chosen = LocationSnapshotPolicy.snapshotForSend(
            detectionSnapshot: detection,
            latestAcceptedFix: newer,
            now: sendNow,
            tuning: tuning
        )
        #expect(chosen.status == .current)
        #expect(chosen.latitude == 42.0)
    }

    @Test func refreshKeepsDetectionWhenNoNewerFix() {
        let detection = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 5), now: now, tuning: tuning)
        let sendNow = now.addingTimeInterval(20)
        // The same fix is still the latest at send time (now 25 s old).
        let same = fix(ageSeconds: 5)
        let chosen = LocationSnapshotPolicy.snapshotForSend(
            detectionSnapshot: detection,
            latestAcceptedFix: same,
            now: sendNow,
            tuning: tuning
        )
        // 25 s old ⇒ last known (the newer computed snapshot is used when the fix
        // is at least as fresh; here it is the same fix re-evaluated at send time).
        #expect(chosen.status == .lastKnown)
        #expect(chosen.age(at: sendNow) == 25)
    }

    @Test func refreshWithNoLatestFixKeepsDetectionSnapshot() {
        let detection = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 5), now: now, tuning: tuning)
        let sendNow = now.addingTimeInterval(20)
        let chosen = LocationSnapshotPolicy.snapshotForSend(
            detectionSnapshot: detection,
            latestAcceptedFix: nil,
            now: sendNow,
            tuning: tuning
        )
        #expect(chosen == detection)
    }

    @Test func refreshPrefersNewerFixEvenIfDetectionWasCurrent() {
        // detection was current; a strictly newer fix at send still wins (uses the
        // newest coordinates and the age relative to send time).
        let detection = LocationSnapshotPolicy.snapshot(fromAcceptedFix: fix(ageSeconds: 2), now: now, tuning: tuning)
        let sendNow = now.addingTimeInterval(40)
        let newer = AcceptedFix(
            latitude: 10, longitude: 20, horizontalAccuracy: 5,
            time: sendNow.addingTimeInterval(-1)
        )
        let chosen = LocationSnapshotPolicy.snapshotForSend(
            detectionSnapshot: detection,
            latestAcceptedFix: newer,
            now: sendNow,
            tuning: tuning
        )
        #expect(chosen.latitude == 10)
        #expect(chosen.status == .current)
    }
}
