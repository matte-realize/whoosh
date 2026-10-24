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
    /// Raw `SyncStatus` value (Requirement 12). Stored as the enum's raw
    /// `String` with a default so existing stores migrate without a schema
    /// change: any record written before sync shipped reads back as
    /// `.localOnly`. An unrecognized value also maps to `.localOnly` at the
    /// repository boundary.
    var syncStatusRaw: String = SyncStatus.localOnly.rawValue
    /// Whether this ride was produced by demo mode (demo-mode spec, task 3).
    /// Stored with a default of `false` so existing stores migrate without a
    /// schema change: any record written before demo mode shipped reads back as
    /// a normal (non-demo) ride. Demo rides are excluded from sync and from the
    /// Home This-Week stats (O-DM2).
    var isDemo: Bool = false

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        distanceMeters: Double,
        activeDuration: TimeInterval,
        averageSpeed: Double,
        encodedPoints: Data,
        syncStatusRaw: String = SyncStatus.localOnly.rawValue,
        isDemo: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.activeDuration = activeDuration
        self.averageSpeed = averageSpeed
        self.encodedPoints = encodedPoints
        self.syncStatusRaw = syncStatusRaw
        self.isDemo = isDemo
    }
}
