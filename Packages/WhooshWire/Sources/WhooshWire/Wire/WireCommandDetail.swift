import Foundation

/// The detail code on a command reply (watch-companion design
/// "`WireCommandReply`" `detail`; Requirement 7.5, 7.6). Distinguishes the
/// concrete result of save-clip, cancel, and start. Unknown values decode to
/// `.unknown`. (`rideId` for a start is carried in the reply's own field, not
/// here.)
public enum WireCommandDetail: String, Codable, Equatable, Sendable, CaseIterable {
    case saved
    case pending
    case nothingToSave
    case storageFull
    case cameraOff
    case cancelled
    case tooLate
    case notCancellable
    case started
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCommandDetail(rawValue: raw) ?? .unknown
    }
}
