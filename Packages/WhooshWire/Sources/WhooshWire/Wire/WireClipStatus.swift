import Foundation

/// The clip sub-object of `WireRideStatus.clip` (watch-companion design).
/// Counts only — a saved-clip count and, optionally, how long ago the last clip
/// was saved. **No clip ids, thumbnails, or footage references** (Req 19.1).
public struct WireClipStatus: Equatable, Codable, Sendable {
    public var count: Int
    public var lastSavedAgoMs: Int?

    public init(count: Int, lastSavedAgoMs: Int? = nil) {
        self.count = count
        self.lastSavedAgoMs = lastSavedAgoMs
    }
}
