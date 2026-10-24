import Foundation

/// The envelope wrapping every wire message (watch-companion design
/// "Envelope (every message)", Requirement 5.3).
///
/// Fields:
/// - `v`: protocol version used for this message.
/// - `t`: the message type tag.
/// - `id`: unique message id (UUID string); for a `command` it is the
///   `commandId`, for an `alert` the alert id.
/// - `s`: sender-session sequence number (increases per sender launch / within
///   a ride epoch for status).
/// - `at`: sender's wall-clock epoch seconds — **logs and a coarse age estimate
///   only**; never used for ordering or duration (design time rule L3).
/// - `ttl`: optional time-to-live in milliseconds.
/// - `p`: the payload as deterministic JSON `Data` (sorted keys) carrying
///   enums, numbers, booleans, and ids only (no free text; Requirement 19).
///
/// The envelope itself is property-list-safe: all fields are plist scalar types
/// and `p` is `Data`, so the whole dictionary round-trips through
/// WatchConnectivity unchanged and is golden-testable.
public struct WireEnvelope: Equatable, Codable, Sendable {
    public var v: Int
    public var t: WireMessageType
    public var id: String
    public var s: Int
    public var at: Double
    public var ttl: Int?
    public var p: Data

    public init(
        v: Int,
        t: WireMessageType,
        id: String,
        s: Int,
        at: Double,
        ttl: Int? = nil,
        p: Data
    ) {
        self.v = v
        self.t = t
        self.id = id
        self.s = s
        self.at = at
        self.ttl = ttl
        self.p = p
    }
}
