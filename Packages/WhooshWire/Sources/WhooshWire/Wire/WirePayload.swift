import Foundation

/// A typed wire payload: a `Codable` value that knows its envelope type tag and
/// its payload size budget in bytes (watch-companion design "Size and rate
/// budgets"; Requirement 5.6). The codec uses these to tag the envelope and to
/// enforce the budget on encode.
public protocol WirePayload: Codable, Equatable, Sendable {
    /// The envelope type tag for this payload.
    static var messageType: WireMessageType { get }
    /// The maximum encoded payload size in bytes (JSON `Data` in the envelope).
    static var payloadByteBudget: Int { get }
}

extension WireHello: WirePayload {
    public static var messageType: WireMessageType { .hello }
    public static var payloadByteBudget: Int { 400 }
}

extension WireRideStatus: WirePayload {
    public static var messageType: WireMessageType { .status }
    public static var payloadByteBudget: Int { 600 }
}

extension WireAlert: WirePayload {
    public static var messageType: WireMessageType { .alert }
    public static var payloadByteBudget: Int { 300 }
}

extension WireCommand: WirePayload {
    public static var messageType: WireMessageType { .command }
    public static var payloadByteBudget: Int { 300 }
}

extension WireCommandReply: WirePayload {
    public static var messageType: WireMessageType { .reply }
    // The reply embeds a full status, so its budget is the status budget plus
    // reply overhead (design: reply ≤ 900).
    public static var payloadByteBudget: Int { 900 }
}

extension WireWatchState: WirePayload {
    public static var messageType: WireMessageType { .watchState }
    public static var payloadByteBudget: Int { 300 }
}

extension WireAlertReceipt: WirePayload {
    public static var messageType: WireMessageType { .receipt }
    public static var payloadByteBudget: Int { 200 }
}

extension WireSummary: WirePayload {
    public static var messageType: WireMessageType { .summary }
    public static var payloadByteBudget: Int { 300 }
}
