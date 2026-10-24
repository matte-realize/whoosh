import Foundation

/// The GeoJSON `LineString` payload for the `rides.route` column.
///
/// Coordinates are `[longitude, latitude]` pairs (GeoJSON order — the opposite
/// of `CLLocationCoordinate2D`'s `(lat, lon)`). Pure value type so the golden
/// row-mapping test can pin the shape without any framework dependency.
nonisolated struct RouteGeoJSON: Codable, Equatable, Sendable {
    let type: String
    /// `[[lon, lat], …]`.
    let coordinates: [[Double]]?

    init(coordinates: [[Double]]) {
        self.type = "LineString"
        self.coordinates = coordinates
    }
}

/// A single row of the Supabase `rides` table (Requirement 12.18–12.21).
///
/// Column names match `supabase/migrations/20261024120000_rides.sql` exactly
/// (`id`, `started_at`, `ended_at`, `distance_m`, `active_duration_s`,
/// `avg_speed_mps`, `route`, `app_version`, `share_publicly`). `user_id` and
/// `created_at` are deliberately omitted so the DB defaults (`auth.uid()` /
/// `now()`) set them; a golden-JSON test guards both the names and the
/// `[lon, lat]` coordinate order.
///
/// Values are SI; timestamps encode as ISO-8601 (`timestamptz`) when the
/// encoder uses `.iso8601`. Every column the app owns is present so the upsert
/// is always a full-column write (never a partial update that could trip the
/// backend's `rides_active_within_elapsed` check).
///
/// Named `RideUploadRow` (not `RideRow`) to avoid colliding with the `RideRow`
/// history/recent UI component in `Support/Components`.
nonisolated struct RideUploadRow: Codable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceM: Double
    let activeDurationS: Double
    let avgSpeedMps: Double
    let route: RouteGeoJSON
    let appVersion: String
    let sharePublicly: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case distanceM = "distance_m"
        case activeDurationS = "active_duration_s"
        case avgSpeedMps = "avg_speed_mps"
        case route
        case appVersion = "app_version"
        case sharePublicly = "share_publicly"
    }
}
