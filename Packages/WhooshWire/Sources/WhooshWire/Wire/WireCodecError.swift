import Foundation

/// A typed error from the wire codec (watch-companion design "Codec totality";
/// Requirement 5.5). Decoding is strict and total: bad input returns one of
/// these and is dropped — never a crash.
public enum WireCodecError: Error, Equatable, Sendable {
    /// The envelope itself could not be decoded (not a valid dictionary / JSON).
    case malformedEnvelope
    /// The payload JSON could not be decoded into the expected type.
    case malformedPayload
    /// A required field was missing.
    case missingField(String)
    /// A field had the wrong type.
    case wrongType(String)
    /// The envelope's type tag did not match the payload type being decoded.
    case typeMismatch(expected: WireMessageType, found: WireMessageType)
    /// The message's protocol version is not supported by this build.
    case unsupportedVersion(Int)
    /// The encoded message exceeded its size budget.
    case oversized(bytes: Int, limit: Int)
}
