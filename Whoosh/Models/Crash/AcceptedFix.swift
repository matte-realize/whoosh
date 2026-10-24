import Foundation

/// The freshest **accepted** route fix, as read from a read-only `RideContext`
/// (spec design "Location snapshot policy", step 1). The ride engine already
/// filters points by accuracy (≤ 30 m) and plausibility; this is just the
/// coordinates, horizontal accuracy, and fix time of that latest accepted point.
///
/// Foundation-only value type (Models layer); `Equatable`, `Codable`,
/// `Sendable`. Turned into a `LocationSnapshot` by `LocationSnapshotPolicy`.
struct AcceptedFix: Equatable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let time: Date

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double, time: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.time = time
    }
}
