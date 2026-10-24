import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `NearMissPolicy` (rear-camera task 10, Requirements 15.1,
/// 15.2, design "Detection events and near-miss records"). Written test-first.
///
/// The policy decides, for an incoming `HazardDetection`, whether it becomes a
/// near-miss **event** and whether a clip should be **pinned**, given:
/// - a confidence threshold (below ⇒ ignored entirely),
/// - a cooldown since the last accepted event (within ⇒ no new event/pin),
/// - a per-ride cap on auto-pins (reached ⇒ event recorded, no pin),
/// - the current storage status (`warn`/`stop` ⇒ event recorded, no pin),
/// - whether the camera is recording (not recording ⇒ event recorded, no pin).
///
/// Thresholds and cooldowns come from `RideCameraTuning`; the confidence
/// threshold is supplied by the caller (Teammate B's measured number) so the
/// policy stays pure and the default "off until measured" lives in the caller.
struct NearMissPolicyTests {
    private let tuning = RideCameraTuning()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func detection(
        confidence: Double,
        at offset: TimeInterval = 0,
        kind: String = "vehicle",
        hint: String? = "center"
    ) -> HazardDetection {
        HazardDetection(
            timestamp: now.addingTimeInterval(offset),
            kind: kind,
            confidence: confidence,
            relativePositionHint: hint
        )
    }

    private func context(
        lastAcceptedAt: Date? = nil,
        autoPinsThisRide: Int = 0,
        storage: StorageStatus = .ok,
        cameraRecording: Bool = true
    ) -> NearMissPolicy.Context {
        NearMissPolicy.Context(
            now: now,
            confidenceThreshold: 0.5,
            lastAcceptedEventAt: lastAcceptedAt,
            autoPinsThisRide: autoPinsThisRide,
            storageStatus: storage,
            cameraRecording: cameraRecording
        )
    }

    // NM-1: below the confidence threshold ⇒ ignored entirely (no event, no pin).
    @Test func belowThresholdIsIgnored() {
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.49),
            context: context(),
            tuning: tuning
        )
        #expect(decision == .ignore)
        #expect(decision.recordsEvent == false)
        #expect(decision.pinsClip == false)
    }

    // NM-2: exactly at the threshold is accepted (>= threshold).
    @Test func atThresholdIsAccepted() {
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.5),
            context: context(),
            tuning: tuning
        )
        #expect(decision.recordsEvent)
        #expect(decision.pinsClip)
    }

    // NM-3: eligible detection ⇒ record event AND pin a clip.
    @Test func eligibleRecordsEventAndPins() {
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(),
            tuning: tuning
        )
        #expect(decision == .recordAndPin)
    }

    // NM-4: within the cooldown since the last accepted event ⇒ ignored (same
    // event; no new event, no new pin).
    @Test func withinCooldownIsIgnored() {
        let last = now.addingTimeInterval(-(tuning.autoPinCooldown - 1))
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(lastAcceptedAt: last),
            tuning: tuning
        )
        #expect(decision == .ignore)
    }

    // NM-5: exactly at the cooldown boundary ⇒ accepted again (strictly-less is
    // "within", the boundary is elapsed).
    @Test func atCooldownBoundaryIsAccepted() {
        let last = now.addingTimeInterval(-tuning.autoPinCooldown)
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(lastAcceptedAt: last),
            tuning: tuning
        )
        #expect(decision == .recordAndPin)
    }

    // NM-6: per-ride auto-pin cap reached ⇒ record the event but do NOT pin.
    @Test func perRideCapRecordsEventNoPin() {
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(autoPinsThisRide: tuning.maxAutoPinsPerRide),
            tuning: tuning
        )
        #expect(decision == .recordNoPin)
        #expect(decision.recordsEvent)
        #expect(decision.pinsClip == false)
    }

    // NM-7: storage refusal (warn or stop) ⇒ record the event but do NOT pin.
    @Test func storageWarnRefusesPin() {
        let warn = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(storage: .warn),
            tuning: tuning
        )
        #expect(warn == .recordNoPin)

        let stop = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(storage: .stop),
            tuning: tuning
        )
        #expect(stop == .recordNoPin)
    }

    // NM-8: camera not recording ⇒ record the event with no clip (cannot pin).
    @Test func notRecordingRecordsEventNoPin() {
        let decision = NearMissPolicy.decide(
            detection: detection(confidence: 0.9),
            context: context(cameraRecording: false),
            tuning: tuning
        )
        #expect(decision == .recordNoPin)
    }

    // The event builder maps a detection + ride context into a NearMissEvent,
    // carrying the nearest route coordinate (may be absent) and NOT a clip id
    // (the clip id is linked later only when a pin succeeds).
    @Test func buildsEventFromDetection() {
        let rideId = UUID()
        let eventId = UUID()
        let event = NearMissPolicy.makeEvent(
            id: eventId,
            rideId: rideId,
            detection: detection(confidence: 0.8, kind: "vehicle", hint: "left"),
            latitude: 42.36,
            longitude: -71.06
        )
        #expect(event.id == eventId)
        #expect(event.rideId == rideId)
        #expect(event.occurredAt == now)
        #expect(event.kind == "vehicle")
        #expect(event.confidence == 0.8)
        #expect(event.positionHint == "left")
        #expect(event.latitude == 42.36)
        #expect(event.longitude == -71.06)
        #expect(event.localClipId == nil)
    }

    @Test func buildsEventWithAbsentCoordinate() {
        let event = NearMissPolicy.makeEvent(
            id: UUID(),
            rideId: UUID(),
            detection: detection(confidence: 0.8),
            latitude: nil,
            longitude: nil
        )
        #expect(event.latitude == nil)
        #expect(event.longitude == nil)
    }
}
