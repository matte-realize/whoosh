import Testing
import Foundation
@testable import WhooshWire

/// Task 5 — golden fixtures and the privacy allowlist (PR-1).
///
/// Golden fixtures pin the canonical (deterministic, sorted-key) JSON of every
/// payload type so any change to the wire format is a **visible diff** in this
/// file (Requirement 21.6). If a field is added, these strings must be updated
/// in the same commit — that is the point.
///
/// PR-1 serializes every wire type and fails on any field outside the allowlist
/// or any string longer than a short code (Requirement 19.2).
@Suite("Wire golden fixtures and privacy allowlist")
struct WireGoldenAndAllowlistTests {

    private func det<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try! e.encode(v), encoding: .utf8)!
    }

    // MARK: Golden fixtures (G1–G9, plus crash-status and preview variants)

    @Test("G1: hello golden")
    func g1_hello() {
        #expect(det(WireSamples.hello) == #"{"appBuild":"100","capabilities":["crashCancel","haptics.v1","startFromWatch"],"maxVersion":1,"minVersion":1,"sessionNonce":"55555555-5555-5555-5555-555555555555"}"#)
    }

    @Test("G2: status golden")
    func g2_status() {
        #expect(det(WireSamples.status) == #"{"activeMs":123000,"banner":"none","camera":{"feature":"on","state":"recording"},"clip":{"count":2,"lastSavedAgoMs":4000},"demo":false,"distance10m":540,"epoch":2,"flags":["lowPowerMode","storageLow"],"phone":{"batteryPct":73,"charging":false},"rideId":"11111111-1111-1111-1111-111111111111","seq":7,"speedDms":58,"start":{"kind":"armed","untilMs":280000},"state":"recording","watchEnabled":true}"#)
    }

    @Test("G3: status-with-crash golden")
    func g3_statusCrash() {
        #expect(det(WireSamples.statusWithCrash) == #"{"activeMs":130000,"banner":"signalLost","camera":{"feature":"on","reason":"thermal","state":"degraded"},"clip":{"count":2},"crash":{"contactCount":3,"eventId":"22222222-2222-2222-2222-222222222222","isDrill":true,"phase":"countdown","remainingMs":9000},"demo":true,"distance10m":560,"epoch":2,"flags":[],"phone":{"batteryPct":40,"charging":false},"rideId":"11111111-1111-1111-1111-111111111111","seq":8,"speedDms":60,"start":{"kind":"ready"},"state":"recording","watchEnabled":true}"#)
    }

    @Test("G4: alert golden")
    func g4_alert() {
        #expect(det(WireSamples.alert) == #"{"alertId":"44444444-4444-4444-4444-444444444444","confidence":8,"createdAgoMs":120,"hint":"left","isDemo":false,"kind":"rearVehicleCaution","level":2,"replay":false,"tier":"caution","ttlMs":3000}"#)
    }

    @Test("G5: alert-preview golden")
    func g5_alertPreview() {
        #expect(det(WireSamples.alertPreview) == #"{"alertId":"44444444-4444-4444-4444-444444444444","createdAgoMs":0,"isDemo":false,"kind":"patternPreview","patternName":"clipSaved","replay":false,"tier":"confirm","ttlMs":5000}"#)
    }

    @Test("G6: command golden")
    func g6_command() {
        #expect(det(WireSamples.command) == #"{"attempt":1,"commandId":"33333333-3333-3333-3333-333333333333","holdConfirmed":true,"issuedAgoMs":50,"kind":"stop","rideId":"11111111-1111-1111-1111-111111111111"}"#)
    }

    @Test("G7: reply golden (embeds a status)")
    func g7_reply() {
        #expect(det(WireSamples.reply) == #"{"commandId":"33333333-3333-3333-3333-333333333333","outcome":"accepted","status":{"activeMs":123000,"banner":"none","camera":{"feature":"on","state":"recording"},"clip":{"count":2,"lastSavedAgoMs":4000},"demo":false,"distance10m":540,"epoch":2,"flags":["lowPowerMode","storageLow"],"phone":{"batteryPct":73,"charging":false},"rideId":"11111111-1111-1111-1111-111111111111","seq":7,"speedDms":58,"start":{"kind":"armed","untilMs":280000},"state":"recording","watchEnabled":true}}"#)
    }

    @Test("G8: watchState golden")
    func g8_watchState() {
        #expect(det(WireSamples.watchState) == #"{"anotherWorkout":false,"appActive":true,"batteryPct":66,"displayActive":false,"hapticsArmed":true,"healthAuthorized":true,"lowPowerMode":false,"session":"running","workoutSaved":"none"}"#)
    }

    @Test("G9: receipt and summary goldens")
    func g9_receiptSummary() {
        #expect(det(WireSamples.receipt) == #"{"alertId":"44444444-4444-4444-4444-444444444444","playedAfterMs":220,"result":"played","workoutActive":true}"#)
        #expect(det(WireSamples.summary) == #"{"avgSpeedDms":55,"cameraGapCount":1,"cueCount":4,"distance10m":1200,"durationMs":1800000,"noticeCount":2,"rideId":"11111111-1111-1111-1111-111111111111"}"#)
    }

    // MARK: PR-1 — the privacy allowlist

    @Test("PR-1: every wire payload passes the allowlist (no sensitive field, no free text)")
    func pr1_allPayloadsAllowed() {
        expectAllowed(WireSamples.hello)
        expectAllowed(WireSamples.status)
        expectAllowed(WireSamples.statusWithCrash)
        expectAllowed(WireSamples.alert)
        expectAllowed(WireSamples.alertPreview)
        expectAllowed(WireSamples.command)
        expectAllowed(WireSamples.reply)
        expectAllowed(WireSamples.watchState)
        expectAllowed(WireSamples.receipt)
        expectAllowed(WireSamples.summary)
    }

    private func expectAllowed<P: Encodable>(_ value: P) {
        let violations = WireAllowlist.validate(value)
        #expect(violations.isEmpty, "unexpected allowlist violations: \(violations)")
    }

    @Test("PR-1: the allowlist catches a forbidden key (a contact name)")
    func pr1_catchesForbiddenKey() {
        struct Leaky: Encodable { let contactName = "Jane Doe"; let ok = 1 }
        let violations = WireAllowlist.validate(Leaky())
        #expect(!violations.isEmpty)
    }

    @Test("PR-1: the allowlist catches a coordinate key")
    func pr1_catchesCoordinate() {
        struct Leaky: Encodable { let coordinate = [42.36, -71.06]; let ok = 1 }
        let violations = WireAllowlist.validate(Leaky())
        #expect(!violations.isEmpty)
    }

    @Test("PR-1: the allowlist catches free text (a string over the short-code limit)")
    func pr1_catchesFreeText() {
        struct Leaky: Encodable { let code = String(repeating: "word ", count: 20) }
        let violations = WireAllowlist.validate(Leaky())
        #expect(!violations.isEmpty)
    }

    @Test("PR-1: identifier-shaped strings (UUIDs, codes) are allowed")
    func pr1_identifiersAllowed() {
        struct OK: Encodable { let rideId = "11111111-1111-1111-1111-111111111111"; let build = "1.2.3" }
        #expect(WireAllowlist.validate(OK()).isEmpty)
    }
}
