import Testing
import Foundation
@testable import WhooshWire

/// Task 5 — codec and versioning. Deterministic encode/decode, strict total
/// decoding (typed errors, never a crash), type-tag checks, version handling,
/// unknown-field/enum tolerance, and size budgets.
@Suite("Wire codec and versioning")
struct WireCodecTests {

    // MARK: MC — codec

    @Test("MC-1: every payload type round-trips through the envelope")
    func mc1_roundTripEveryType() throws {
        try roundTripThroughEnvelope(WireSamples.hello, id: WireSamples.nonce)
        try roundTripThroughEnvelope(WireSamples.status, id: WireSamples.rideId)
        try roundTripThroughEnvelope(WireSamples.statusWithCrash, id: WireSamples.rideId)
        try roundTripThroughEnvelope(WireSamples.alert, id: WireSamples.alertId)
        try roundTripThroughEnvelope(WireSamples.command, id: WireSamples.commandId)
        try roundTripThroughEnvelope(WireSamples.reply, id: WireSamples.commandId)
        try roundTripThroughEnvelope(WireSamples.watchState, id: WireSamples.rideId)
        try roundTripThroughEnvelope(WireSamples.receipt, id: WireSamples.alertId)
        try roundTripThroughEnvelope(WireSamples.summary, id: WireSamples.rideId)
    }

    private func roundTripThroughEnvelope<P: WirePayload>(_ payload: P, id: String) throws {
        let envelope = try WireCodec.encode(payload, id: id, seq: 1, sentAt: WireSamples.sentAt)
        #expect(envelope.t == P.messageType)
        let data = try WireCodec.encodeToData(envelope)
        let decoded = try WireCodec.decode(P.self, from: data)
        #expect(decoded == payload)
    }

    @Test("MC-2: encoding is deterministic (sorted keys; identical bytes)")
    func mc2_deterministicEncoding() throws {
        let a = try WireCodec.encode(WireSamples.status, id: WireSamples.rideId, seq: 1, sentAt: WireSamples.sentAt)
        let b = try WireCodec.encode(WireSamples.status, id: WireSamples.rideId, seq: 1, sentAt: WireSamples.sentAt)
        #expect(try WireCodec.encodeToData(a) == WireCodec.encodeToData(b))
    }

    @Test("MC-3: output is property-list-safe (JSONSerialization accepts it)")
    func mc3_plistSafe() throws {
        let envelope = try WireCodec.encode(WireSamples.status, id: WireSamples.rideId, seq: 1, sentAt: WireSamples.sentAt)
        let data = try WireCodec.encodeToData(envelope)
        let object = try JSONSerialization.jsonObject(with: data)
        #expect(object is [String: Any])
    }

    @Test("MC-4: an unknown payload field is ignored on decode")
    func mc4_unknownFieldIgnored() throws {
        // Hand-craft a status payload JSON with an extra unknown field.
        let payloadJSON = """
        {"rideId":"\(WireSamples.rideId)","epoch":1,"seq":1,"state":"recording",\
        "activeMs":1000,"distance10m":10,"camera":{"feature":"on","state":"recording"},\
        "flags":[],"phone":{"batteryPct":50,"charging":false},"banner":"none",\
        "clip":{"count":0},"start":{"kind":"ready"},"demo":false,"watchEnabled":true,\
        "somethingNew":"ignored"}
        """
        let payloadData = Data(payloadJSON.utf8)
        let envelope = WireEnvelope(v: 1, t: .status, id: WireSamples.rideId, s: 1, at: 0, p: payloadData)
        let decoded = try WireCodec.decodePayload(WireRideStatus.self, from: envelope)
        #expect(decoded.state == .recording)
        #expect(decoded.rideId == WireSamples.rideId)
    }

    @Test("MC-5: an unknown enum value decodes to .unknown through the codec")
    func mc5_unknownEnumThroughCodec() throws {
        let payloadJSON = """
        {"rideId":"\(WireSamples.rideId)","epoch":1,"seq":1,"state":"hyperspace",\
        "activeMs":1000,"distance10m":10,"camera":{"feature":"on","state":"recording"},\
        "flags":[],"phone":{"batteryPct":50,"charging":false},"banner":"none",\
        "clip":{"count":0},"start":{"kind":"ready"},"demo":false,"watchEnabled":true}
        """
        let envelope = WireEnvelope(v: 1, t: .status, id: WireSamples.rideId, s: 1, at: 0, p: Data(payloadJSON.utf8))
        let decoded = try WireCodec.decodePayload(WireRideStatus.self, from: envelope)
        #expect(decoded.state == .unknown)
    }

    @Test("MC-6: a missing required field yields a typed error, not a crash")
    func mc6_missingField() throws {
        let payloadJSON = #"{"kind":"pause"}"#   // WireCommand missing commandId
        let envelope = WireEnvelope(v: 1, t: .command, id: WireSamples.commandId, s: 1, at: 0, p: Data(payloadJSON.utf8))
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decodePayload(WireCommand.self, from: envelope)
        }
    }

    @Test("MC-7: a wrong-typed field yields a typed error")
    func mc7_wrongType() throws {
        let payloadJSON = #"{"commandId":"\#(WireSamples.commandId)","kind":"pause","attempt":"notANumber","holdConfirmed":false,"issuedAgoMs":0}"#
        let envelope = WireEnvelope(v: 1, t: .command, id: WireSamples.commandId, s: 1, at: 0, p: Data(payloadJSON.utf8))
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decodePayload(WireCommand.self, from: envelope)
        }
    }

    @Test("MC-8: a type-tag mismatch is rejected")
    func mc8_typeMismatch() throws {
        let envelope = try WireCodec.encode(WireSamples.command, id: WireSamples.commandId, seq: 1, sentAt: 0)
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decodePayload(WireRideStatus.self, from: envelope)
        }
    }

    @Test("MC-9: random bytes never crash the decoder; they error")
    func mc9_randomBytes() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let count = Int.random(in: 0...64, using: &generator)
            var bytes = [UInt8]()
            for _ in 0..<count { bytes.append(UInt8.random(in: 0...255, using: &generator)) }
            let data = Data(bytes)
            // Either it fails to decode the envelope, or the payload — never crashes.
            #expect(throws: WireCodecError.self) {
                let envelope = try WireCodec.decodeEnvelope(data)
                _ = try WireCodec.decodePayload(WireRideStatus.self, from: envelope)
            }
        }
    }

    @Test("MC-10: size budgets are enforced on encode")
    func mc10_sizeBudgets() throws {
        // All samples are within budget.
        _ = try WireCodec.encode(WireSamples.status, id: WireSamples.rideId, seq: 1, sentAt: 0)
        _ = try WireCodec.encode(WireSamples.reply, id: WireSamples.commandId, seq: 1, sentAt: 0)

        // A pattern name far over the short-code size blows the alert budget.
        let huge = WireAlert(
            alertId: WireSamples.alertId,
            kind: .patternPreview,
            tier: .confirm,
            patternName: String(repeating: "x", count: 2_000),
            createdAgoMs: 0,
            ttlMs: 5_000
        )
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.encode(huge, id: WireSamples.alertId, seq: 1, sentAt: 0)
        }
    }

    // MARK: CV — versions

    @Test("CV-1: negotiation picks the highest common version")
    func cv1_highestCommon() {
        #expect(WireVersion.negotiate(local: 1...3, remote: 2...5) == 3)
    }

    @Test("CV-2: disjoint ranges do not negotiate (incompatible)")
    func cv2_disjoint() {
        #expect(WireVersion.negotiate(local: 1...1, remote: 3...4) == nil)
    }

    @Test("CV-3: the previous wire version is still accepted on decode")
    func cv3_previousVersionAccepted() throws {
        // Build an envelope stamped at minSupported and decode it.
        let envelope = try WireCodec.encode(
            WireSamples.status, id: WireSamples.rideId, seq: 1, sentAt: 0,
            version: WireVersion.minSupported
        )
        let decoded = try WireCodec.decode(WireRideStatus.self, from: try WireCodec.encodeToData(envelope))
        #expect(decoded == WireSamples.status)
    }

    @Test("CV-4: an unsupported (too-old) version yields a typed rejection")
    func cv4_unsupportedVersion() throws {
        let payloadData = try WireCodec.encodeToData(
            try WireCodec.encode(WireSamples.status, id: WireSamples.rideId, seq: 1, sentAt: 0)
        )
        var envelope = try WireCodec.decodeEnvelope(payloadData)
        envelope.v = WireVersion.minSupported - 1
        #expect(throws: WireCodecError.self) {
            _ = try WireCodec.decodePayload(WireRideStatus.self, from: envelope)
        }
    }

    @Test("CV-5: a new minor field added by a newer sender is ignored by this reader")
    func cv5_newMinorFieldIgnored() throws {
        // Same as MC-4 but framed as a version-compat case.
        let payloadJSON = """
        {"alertId":"\(WireSamples.alertId)","kind":"clipSaved","tier":"confirm",\
        "isDemo":false,"createdAgoMs":0,"ttlMs":10000,"replay":false,"futureField":42}
        """
        let envelope = WireEnvelope(v: WireVersion.current, t: .alert, id: WireSamples.alertId, s: 1, at: 0, p: Data(payloadJSON.utf8))
        let decoded = try WireCodec.decodePayload(WireAlert.self, from: envelope)
        #expect(decoded.kind == .clipSaved)
    }

    @Test("CV-6: hello carries a version range and capabilities that negotiate")
    func cv6_helloCapabilities() throws {
        let phone = WireHello(minVersion: 1, maxVersion: 2, appBuild: "100", sessionNonce: WireSamples.nonce, capabilities: ["startFromWatch"])
        let watch = WireHello(minVersion: 1, maxVersion: 1, appBuild: "7", sessionNonce: "abc", capabilities: ["haptics.v1"])
        let negotiated = WireVersion.negotiate(local: phone.versionRange, remote: watch.versionRange)
        #expect(negotiated == 1)
        // Round-trips through the codec.
        let envelope = try WireCodec.encode(phone, id: WireSamples.nonce, seq: 1, sentAt: 0)
        let decoded = try WireCodec.decode(WireHello.self, from: try WireCodec.encodeToData(envelope))
        #expect(decoded == phone)
    }
}
