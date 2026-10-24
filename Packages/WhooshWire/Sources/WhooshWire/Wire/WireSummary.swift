import Foundation

/// The end-of-ride summary delivered phone → watch on the queue channel
/// (watch-companion design "`WireSummary`"; Requirement 16.1). Totals and counts
/// only — no route, location, or contact data (Requirement 16.7, 19.1).
public struct WireSummary: Equatable, Codable, Sendable {
    public var rideId: String
    public var durationMs: Int
    public var distance10m: Int
    public var avgSpeedDms: Int
    public var cueCount: Int
    public var noticeCount: Int
    public var cameraGapCount: Int

    public init(
        rideId: String,
        durationMs: Int,
        distance10m: Int,
        avgSpeedDms: Int,
        cueCount: Int,
        noticeCount: Int,
        cameraGapCount: Int
    ) {
        self.rideId = rideId
        self.durationMs = durationMs
        self.distance10m = distance10m
        self.avgSpeedDms = avgSpeedDms
        self.cueCount = cueCount
        self.noticeCount = noticeCount
        self.cameraGapCount = cameraGapCount
    }
}
