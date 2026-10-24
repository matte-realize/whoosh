import Foundation
@testable import WhooshWire

/// Deterministic sample values for every wire payload, used by the codec,
/// golden-fixture, and allowlist tests. Ids are fixed (not random) so golden
/// fixtures are stable.
enum WireSamples {
    static let rideId = "11111111-1111-1111-1111-111111111111"
    static let eventId = "22222222-2222-2222-2222-222222222222"
    static let commandId = "33333333-3333-3333-3333-333333333333"
    static let alertId = "44444444-4444-4444-4444-444444444444"
    static let nonce = "55555555-5555-5555-5555-555555555555"

    static let status = WireRideStatus(
        rideId: rideId,
        epoch: 2,
        seq: 7,
        state: .recording,
        activeMs: 123_000,
        distance10m: 540,
        speedDms: 58,
        camera: WireCameraStatus(feature: .on, state: .recording, reason: nil),
        flags: [.lowPowerMode, .storageLow],
        phone: WirePhoneState(batteryPct: 73, charging: false),
        banner: .none,
        crash: nil,
        clip: WireClipStatus(count: 2, lastSavedAgoMs: 4_000),
        start: .armed(untilMs: 280_000),
        demo: false,
        watchEnabled: true
    )

    static let statusWithCrash = WireRideStatus(
        rideId: rideId,
        epoch: 2,
        seq: 8,
        state: .recording,
        activeMs: 130_000,
        distance10m: 560,
        speedDms: 60,
        camera: WireCameraStatus(feature: .on, state: .degraded, reason: .thermal),
        flags: [],
        phone: WirePhoneState(batteryPct: 40, charging: false),
        banner: .signalLost,
        crash: WireCrashStatus(
            eventId: eventId,
            remainingMs: 9_000,
            isDrill: true,
            contactCount: 3,
            phase: .countdown
        ),
        clip: WireClipStatus(count: 2),
        start: .ready,
        demo: true,
        watchEnabled: true
    )

    static let alert = WireAlert(
        alertId: alertId,
        kind: .rearVehicleCaution,
        tier: .caution,
        level: 2,
        reason: nil,
        value: nil,
        isDemo: false,
        confidence: 8,
        hint: .left,
        patternName: nil,
        outcome: nil,
        createdAgoMs: 120,
        ttlMs: 3_000,
        replay: false
    )

    static let alertPreview = WireAlert(
        alertId: alertId,
        kind: .patternPreview,
        tier: .confirm,
        patternName: "clipSaved",
        createdAgoMs: 0,
        ttlMs: 5_000
    )

    static let command = WireCommand(
        commandId: commandId,
        kind: .stop,
        rideId: rideId,
        holdConfirmed: true,
        crashEventId: nil,
        issuedAgoMs: 50,
        attempt: 1
    )

    static let reply = WireCommandReply(
        commandId: commandId,
        outcome: .accepted,
        reason: nil,
        detail: nil,
        newRideId: nil,
        status: status
    )

    static let watchState = WireWatchState(
        session: .running,
        sessionReason: nil,
        healthAuthorized: true,
        appActive: true,
        displayActive: false,
        batteryPct: 66,
        lowPowerMode: false,
        hapticsArmed: true,
        anotherWorkout: false,
        workoutSaved: .none
    )

    static let receipt = WireAlertReceipt(
        alertId: alertId,
        result: .played,
        workoutActive: true,
        playedAfterMs: 220
    )

    static let hello = WireHello(
        minVersion: 1,
        maxVersion: 1,
        appBuild: "100",
        sessionNonce: nonce,
        capabilities: ["crashCancel", "haptics.v1", "startFromWatch"]
    )

    static let summary = WireSummary(
        rideId: rideId,
        durationMs: 1_800_000,
        distance10m: 1_200,
        avgSpeedDms: 55,
        cueCount: 4,
        noticeCount: 2,
        cameraGapCount: 1
    )

    /// A fixed send time for golden fixtures.
    static let sentAt = 1_700_000_000.0
}
