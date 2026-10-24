import Testing
import Foundation
@testable import WhooshWire

/// Task 4 — wire models and tuning. Value types are Equatable/Codable/Sendable;
/// enums decode unknown values safely; `WatchTuning` clamps every range.
@Suite("Wire models and tuning")
struct WireModelsTests {

    // MARK: Codable round-trips (direct, not through the envelope)

    @Test("every payload round-trips through JSONEncoder/Decoder unchanged")
    func payloadRoundTrips() throws {
        try roundTrip(WireSamples.status)
        try roundTrip(WireSamples.statusWithCrash)
        try roundTrip(WireSamples.alert)
        try roundTrip(WireSamples.alertPreview)
        try roundTrip(WireSamples.command)
        try roundTrip(WireSamples.reply)
        try roundTrip(WireSamples.watchState)
        try roundTrip(WireSamples.receipt)
        try roundTrip(WireSamples.hello)
        try roundTrip(WireSamples.summary)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        #expect(decoded == value)
    }

    // MARK: Unknown-enum safety

    @Test("unknown raw enum values decode to .unknown, never a throw")
    func unknownEnumsDecodeSafely() throws {
        #expect(decodeRaw(WireMessageType.self, "\"brandNew\"") == .unknown)
        #expect(decodeRaw(WireRideState.self, "\"teleporting\"") == .unknown)
        #expect(decodeRaw(WireCameraState.self, "\"melting\"") == .unknown)
        #expect(decodeRaw(WireCameraReason.self, "\"cosmic\"") == .unknown)
        #expect(decodeRaw(WireBanner.self, "\"party\"") == .unknown)
        #expect(decodeRaw(WireStatusFlag.self, "\"gremlins\"") == .unknown)
        #expect(decodeRaw(WireCrashPhase.self, "\"vibing\"") == .unknown)
        #expect(decodeRaw(WireAlertKind.self, "\"newKind\"") == .unknown)
        #expect(decodeRaw(WireAlertTier.self, "\"ultra\"") == .unknown)
        #expect(decodeRaw(WirePositionHint.self, "\"up\"") == .unknown)
        #expect(decodeRaw(WireCommandKind.self, "\"teleport\"") == .unknown)
        #expect(decodeRaw(WireCommandOutcome.self, "\"maybe\"") == .unknown)
        #expect(decodeRaw(WireCommandReason.self, "\"because\"") == .unknown)
        #expect(decodeRaw(WireCommandDetail.self, "\"meh\"") == .unknown)
        #expect(decodeRaw(WireWorkoutSessionPhase.self, "\"napping\"") == .unknown)
        #expect(decodeRaw(WireSessionReason.self, "\"shrug\"") == .unknown)
        #expect(decodeRaw(WireWorkoutSaveState.self, "\"later\"") == .unknown)
        #expect(decodeRaw(WireAlertReceiptResult.self, "\"ok\"") == .unknown)
        #expect(decodeRaw(WireStartReasonCode.self, "\"nope\"") == .unknown)
        #expect(decodeRaw(WireStartState.Kind.self, "\"halfArmed\"") == .unknown)
    }

    private func decodeRaw<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: WatchTuning clamping and ranges

    @Test("WatchTuning uses the documented defaults")
    func tuningDefaults() {
        let t = WatchTuning()
        #expect(t.statusHeartbeatActiveMs == 5_000)
        #expect(t.statusStaleMs == 15_000)
        #expect(t.commandTtlMs == 8_000)
        #expect(t.commandMinSpacingMs == 500)
        #expect(t.armedExpiryMs == 300_000)
        #expect(t.startHoldMs == 800)
        #expect(t.stopHoldMs == 1_000)
        #expect(t.watchAckTimeoutMs == 1_500)
        #expect(t.hapticMinGapMs == 1_000)
        #expect(t.watchBatteryWarnPct == 40)
        #expect(t.watchBatteryLowPct == 15)
        #expect(t.watchBatteryEndPct == 5)
        #expect(t.dedupeMaxEntries == 128)
        #expect(t.noticeLogSize == 10)
    }

    @Test("WatchTuning clamps below-range and above-range inputs to the bounds")
    func tuningClampsRanges() {
        // Far below every lower bound.
        let low = WatchTuning(
            statusHeartbeatActiveMs: -1,
            statusHeartbeatIdleMs: 0,
            statusMinLiveIntervalMs: 0,
            statusStaleMs: 0,
            linkLostAnnounceMs: 0,
            phoneSilentWarnMs: 0,
            orphanTimeoutMs: 0,
            commandTtlMs: 0,
            commandMinSpacingMs: 0,
            commandMaxAttempts: -5,
            saveClipDebounceMs: 0,
            dedupeWindowMs: 0,
            dedupeMaxEntries: 0,
            armedExpiryMs: 0,
            startHoldMs: 0,
            stopHoldMs: 0,
            watchAckTimeoutMs: 0,
            hapticMinGapMs: 0,
            hapticMinCueSpacingMs: 0,
            rearCueCooldownMs: 0,
            cameraNoticeCooldownMs: 0,
            stormResetMs: 0,
            ttlRearVehicleMs: 0,
            ttlClipNoticeMs: 0,
            ttlCameraBatteryMs: 0,
            ttlLinkNoticeMs: 0,
            watchBatteryWarnPct: -10,
            watchBatteryLowPct: -10,
            watchBatteryEndPct: -10,
            healthChoiceTimeoutMs: 0,
            maxOutstandingTransfers: 0,
            startWatchAppRetries: -1,
            startWatchAppBackoffMs: 0,
            noticeLogSize: 0
        )
        #expect(low.statusHeartbeatActiveMs == WatchTuning.statusHeartbeatActiveRange.lowerBound)
        #expect(low.commandMaxAttempts == WatchTuning.commandMaxAttemptsRange.lowerBound)
        #expect(low.watchBatteryWarnPct == WatchTuning.pctRange.lowerBound)
        #expect(low.armedExpiryMs == WatchTuning.armedExpiryRange.lowerBound)
        #expect(low.noticeLogSize == WatchTuning.noticeLogSizeRange.lowerBound)
        #expect(low.startWatchAppRetries == WatchTuning.startWatchAppRetriesRange.lowerBound)

        // Far above every upper bound.
        let high = WatchTuning(
            statusHeartbeatActiveMs: .max,
            statusHeartbeatIdleMs: .max,
            statusMinLiveIntervalMs: .max,
            statusStaleMs: .max,
            linkLostAnnounceMs: .max,
            phoneSilentWarnMs: .max,
            orphanTimeoutMs: .max,
            commandTtlMs: .max,
            commandMinSpacingMs: .max,
            commandMaxAttempts: .max,
            saveClipDebounceMs: .max,
            dedupeWindowMs: .max,
            dedupeMaxEntries: .max,
            armedExpiryMs: .max,
            startHoldMs: .max,
            stopHoldMs: .max,
            watchAckTimeoutMs: .max,
            hapticMinGapMs: .max,
            hapticMinCueSpacingMs: .max,
            rearCueCooldownMs: .max,
            cameraNoticeCooldownMs: .max,
            stormResetMs: .max,
            ttlRearVehicleMs: .max,
            ttlClipNoticeMs: .max,
            ttlCameraBatteryMs: .max,
            ttlLinkNoticeMs: .max,
            watchBatteryWarnPct: .max,
            watchBatteryLowPct: .max,
            watchBatteryEndPct: .max,
            healthChoiceTimeoutMs: .max,
            maxOutstandingTransfers: .max,
            startWatchAppRetries: .max,
            startWatchAppBackoffMs: .max,
            noticeLogSize: .max
        )
        #expect(high.commandMaxAttempts == WatchTuning.commandMaxAttemptsRange.upperBound)
        #expect(high.watchBatteryWarnPct == WatchTuning.pctRange.upperBound)
        #expect(high.armedExpiryMs == WatchTuning.armedExpiryRange.upperBound)
        #expect(high.dedupeMaxEntries == WatchTuning.dedupeMaxEntriesRange.upperBound)
        #expect(high.maxOutstandingTransfers == WatchTuning.maxOutstandingTransfersRange.upperBound)
    }

    @Test("WireVersion negotiates the highest common version or nil")
    func versionNegotiation() {
        #expect(WireVersion.negotiate(local: 1...1, remote: 1...1) == 1)
        #expect(WireVersion.negotiate(local: 1...2, remote: 1...3) == 2)
        #expect(WireVersion.negotiate(local: 1...1, remote: 2...3) == nil)
        #expect(WireVersion.negotiate(local: 2...4, remote: 1...2) == 2)
    }
}
