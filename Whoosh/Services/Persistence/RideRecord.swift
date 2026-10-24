import Foundation
import SwiftData

/// SwiftData persistence record for a ride (Requirement 7.1).
///
/// The route is stored as an encoded `[RoutePoint]` blob (`encodedPoints`,
/// JSON) rather than a child `@Model` per point: a ride can hold thousands of
/// points, and a blob avoids thousands of rows and relationship overhead. The
/// summary is denormalized onto the record so history/list rows render without
/// decoding the blob. Mapping between `Ride` and `RideRecord` happens only in
/// `SwiftDataRideRepository`.
@Model
final class RideRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    /// Denormalized summary fields for fast list rows.
    var distanceMeters: Double
    var activeDuration: TimeInterval
    var averageSpeed: Double
    /// Encoded `[RoutePoint]` (JSON). Decoded lazily by the repository, which
    /// skips (and logs) a record whose points fail to decode (Requirement 7.7).
    var encodedPoints: Data

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        distanceMeters: Double,
        activeDuration: TimeInterval,
        averageSpeed: Double,
        encodedPoints: Data
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.activeDuration = activeDuration
        self.averageSpeed = averageSpeed
        self.encodedPoints = encodedPoints
    }
}
