import Foundation

/// Deterministic, total encode/decode of wire payloads inside a `WireEnvelope`
/// (watch-companion design "The wire contract"; Requirement 5.3–5.6, 21.6).
///
/// - Encoding is **deterministic**: JSON with sorted keys and without escaping
///   slashes, so the same value always produces identical bytes — golden-
///   testable and identical on both devices.
/// - Encoding enforces the payload's byte budget and the overall 1 KB envelope
///   budget; over-budget encodes throw `WireCodecError.oversized`.
/// - Decoding is **strict and total**: any malformed input returns a typed
///   `WireCodecError` and is dropped, never a crash (design "Codec totality").
/// - Unknown payload fields are ignored; unknown enum values decode to their
///   `.unknown` case (handled by each enum's custom `init(from:)`).
public enum WireCodec {
    /// The overall envelope size budget in bytes (design: every message ≤ 1 KB).
    public static let envelopeByteBudget = 1_024

    // MARK: Encoding

    /// Encode a typed payload into an envelope, enforcing size budgets.
    ///
    /// - Parameters:
    ///   - payload: the typed payload (its `messageType` tags the envelope).
    ///   - id: the message id (UUID string; the commandId / alertId where used).
    ///   - seq: the sender sequence number.
    ///   - sentAt: the sender wall-clock epoch seconds (logs / age only).
    ///   - ttlMs: optional time-to-live.
    ///   - version: the protocol version to stamp (defaults to `current`).
    public nonisolated static func encode<P: WirePayload>(
        _ payload: P,
        id: String,
        seq: Int,
        sentAt: Double,
        ttlMs: Int? = nil,
        version: Int = WireVersion.current
    ) throws -> WireEnvelope {
        let payloadData = try deterministicData(from: payload)
        if payloadData.count > P.payloadByteBudget {
            throw WireCodecError.oversized(bytes: payloadData.count, limit: P.payloadByteBudget)
        }
        let envelope = WireEnvelope(
            v: version,
            t: P.messageType,
            id: id,
            s: seq,
            at: sentAt,
            ttl: ttlMs,
            p: payloadData
        )
        let envelopeData = try deterministicData(from: envelope)
        if envelopeData.count > envelopeByteBudget {
            throw WireCodecError.oversized(bytes: envelopeData.count, limit: envelopeByteBudget)
        }
        return envelope
    }

    /// Serialize an envelope to its canonical (deterministic) bytes for
    /// transport and for golden fixtures.
    public nonisolated static func encodeToData(_ envelope: WireEnvelope) throws -> Data {
        try deterministicData(from: envelope)
    }

    // MARK: Decoding

    /// Decode an envelope from canonical bytes, returning a typed error on any
    /// malformed input (never a crash).
    public nonisolated static func decodeEnvelope(_ data: Data) throws -> WireEnvelope {
        do {
            return try JSONDecoder().decode(WireEnvelope.self, from: data)
        } catch {
            throw WireCodecError.malformedEnvelope
        }
    }

    /// Decode a typed payload from an envelope. Verifies the envelope's type tag
    /// matches the requested payload type and that the version is supported.
    public nonisolated static func decodePayload<P: WirePayload>(
        _ type: P.Type,
        from envelope: WireEnvelope
    ) throws -> P {
        guard envelope.v >= WireVersion.minSupported else {
            throw WireCodecError.unsupportedVersion(envelope.v)
        }
        guard envelope.t == P.messageType else {
            throw WireCodecError.typeMismatch(expected: P.messageType, found: envelope.t)
        }
        do {
            return try JSONDecoder().decode(P.self, from: envelope.p)
        } catch let decodingError as DecodingError {
            throw Self.map(decodingError)
        } catch {
            throw WireCodecError.malformedPayload
        }
    }

    /// Convenience: decode a typed payload directly from envelope bytes.
    public nonisolated static func decode<P: WirePayload>(
        _ type: P.Type,
        from data: Data
    ) throws -> P {
        let envelope = try decodeEnvelope(data)
        return try decodePayload(type, from: envelope)
    }

    // MARK: Helpers

    private nonisolated static func deterministicData<T: Encodable>(from value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private nonisolated static func map(_ error: DecodingError) -> WireCodecError {
        switch error {
        case let .keyNotFound(key, _):
            return .missingField(key.stringValue)
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context):
            return .wrongType(context.codingPath.last?.stringValue ?? "")
        case .dataCorrupted:
            return .malformedPayload
        @unknown default:
            return .malformedPayload
        }
    }
}
