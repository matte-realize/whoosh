import Foundation

/// The type tag carried in a wire envelope's `t` field (watch-companion design
/// "Envelope"). Decodes unknown values to `.unknown` so a newer sender never
/// crashes an older receiver (Requirement 5.4).
public enum WireMessageType: String, Codable, Equatable, Sendable, CaseIterable {
    case hello
    case status
    case alert
    case command
    case reply
    case watchState
    case receipt
    case summary
    /// A type this build does not recognize; handled, never fatal.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireMessageType(rawValue: raw) ?? .unknown
    }
}
