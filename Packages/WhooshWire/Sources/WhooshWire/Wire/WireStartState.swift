import Foundation

/// The start-readiness object of `WireRideStatus.start` (watch-companion design;
/// Requirement 9). One of three shapes expressed as a `kind` plus the fields it
/// needs:
/// - `.notReady` with `reasons` (sorted codes rendered as short instructions),
/// - `.ready`,
/// - `.armed` with `untilMs` (relative time remaining in the armed window;
///   skew-free, design time rule L3).
///
/// The Start control on the watch is enabled only when `kind == .armed`
/// (Requirement 9.4).
public struct WireStartState: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
        case notReady
        case ready
        case armed
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public var kind: Kind
    /// Present (and sorted) only when `kind == .notReady`.
    public var reasons: [WireStartReasonCode]?
    /// Present only when `kind == .armed`: relative ms until the armed window
    /// expires.
    public var untilMs: Int?

    public init(
        kind: Kind,
        reasons: [WireStartReasonCode]? = nil,
        untilMs: Int? = nil
    ) {
        self.kind = kind
        self.reasons = reasons
        self.untilMs = untilMs
    }

    /// Convenience: not ready, with the given sorted reason codes.
    public nonisolated static func notReady(_ reasons: [WireStartReasonCode]) -> WireStartState {
        WireStartState(kind: .notReady, reasons: reasons.sorted())
    }

    /// Convenience: ready to arm (the rider must still tap Ready on the phone).
    public nonisolated static let ready = WireStartState(kind: .ready)

    /// Convenience: armed, expiring in `untilMs` milliseconds.
    public nonisolated static func armed(untilMs: Int) -> WireStartState {
        WireStartState(kind: .armed, untilMs: untilMs)
    }
}
