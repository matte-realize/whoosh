import Foundation

/// Pure, framework-free client-side upload policy (task 28d, Requirements 12.5,
/// 12.18–12.21). Runs *before* any network request so a doomed ride never makes
/// one, and produces the exact `rides` row to upsert.
///
/// Order of operations (per the design):
/// 1. Never upload a demo ride.
/// 2. Trim the route (`RoutePrivacy.trim`, 160 m each end). The local copy is
///    untouched — the caller only hands the trimmed copy to the transport.
/// 3. Thin the trimmed route to ≤ 10,000 points, always keeping first and last.
/// 4. If < 2 points remain → keep the ride local only (a tiny ride legitimately
///    has nothing to map).
/// 5. Validate every contract limit; any violation → mark `.failed`, **no
///    request** (mirrors how the backend's `23514` check would reject it).
/// 6. Otherwise → build the full-column `RideUploadRow` to upsert.
///
/// Lives in the Metrics layer (Models + Foundation only), so it is trivially
/// unit-tested with golden-JSON fixtures.
nonisolated enum RideUploadPolicy {
    /// What the caller should do with a ride.
    enum Outcome: Equatable {
        /// Keep the ride local only; do not upload (empty/tiny route or demo).
        case skipLocalOnly
        /// Permanently rejected by a pre-checked limit; mark `.failed`, no request.
        case markFailed
        /// Upload this row (full-column upsert on `id`).
        case upload(RideUploadRow)
    }

    // Contract limits (from supabase-contract.md / the migrations).
    static let maxRoutePoints = 10_000
    static let maxDistanceMeters: Double = 1_000_000
    static let maxActiveDurationSeconds: Double = 172_800 // 48 h
    static let maxAvgSpeedMps: Double = 40
    static let maxElapsedSeconds: Double = 172_800        // ended_at ≤ started_at + 48 h
    static let maxAppVersionChars = 32

    /// Prepares a ride for upload. `appVersion` is the short build string;
    /// `isDemo` lets callers skip demo rides (the flag may not yet exist on the
    /// `Ride` model on this branch, so it is passed explicitly).
    static func prepare(
        _ ride: Ride,
        appVersion: String,
        isDemo: Bool = false,
        trimMeters: Double = RoutePrivacy.defaultTrimMeters
    ) -> Outcome {
        // 1. Demo rides never leave the device.
        if isDemo { return .skipLocalOnly }

        // 2. Trim for privacy (local copy stays complete elsewhere).
        let trimmed = RoutePrivacy.trim(points: ride.points, meters: trimMeters)

        // 3. Thin to ≤ maxRoutePoints, keeping endpoints.
        let thinned = thin(trimmed, to: maxRoutePoints)

        // 4. < 2 points → nothing worth mapping; keep local only.
        guard thinned.count >= 2 else { return .skipLocalOnly }

        // 5. Validate every contract limit → a violation is permanent.
        guard let endedAt = ride.endedAt else { return .markFailed }

        let elapsed = endedAt.timeIntervalSince(ride.startedAt)
        let distance = ride.summary.distanceMeters
        let active = ride.summary.activeDuration
        let avgSpeed = ride.summary.averageSpeedMetersPerSecond

        if endedAt < ride.startedAt { return .markFailed }
        if distance < 0 || distance > maxDistanceMeters { return .markFailed }
        if active < 0 || active > maxActiveDurationSeconds { return .markFailed }
        // active_duration_s ≤ (ended_at − started_at) + 1 s
        if active > elapsed + 1 { return .markFailed }
        if avgSpeed < 0 || avgSpeed > maxAvgSpeedMps { return .markFailed }
        if elapsed > maxElapsedSeconds { return .markFailed }
        if appVersion.count > maxAppVersionChars { return .markFailed }

        // Coordinate ranges on the (thinned) route that will actually ship.
        for point in thinned {
            if point.longitude < -180 || point.longitude > 180 { return .markFailed }
            if point.latitude < -90 || point.latitude > 90 { return .markFailed }
            if !point.longitude.isFinite || !point.latitude.isFinite { return .markFailed }
        }

        // 6. Build the full-column row (GeoJSON [lon, lat]).
        let coordinates = thinned.map { [$0.longitude, $0.latitude] }
        let row = RideUploadRow(
            id: ride.id,
            startedAt: ride.startedAt,
            endedAt: endedAt,
            distanceM: distance,
            activeDurationS: active,
            avgSpeedMps: avgSpeed,
            route: RouteGeoJSON(coordinates: coordinates),
            appVersion: appVersion,
            sharePublicly: ride.sharePublicly
        )
        return .upload(row)
    }

    /// Evenly downsamples `points` to at most `limit`, always keeping the first
    /// and last point. Returns the input unchanged when it already fits.
    static func thin(_ points: [RoutePoint], to limit: Int) -> [RoutePoint] {
        guard limit >= 2 else { return points }
        guard points.count > limit else { return points }

        var result: [RoutePoint] = []
        result.reserveCapacity(limit)
        // Pick `limit` indices spread across [0, count-1], endpoints included.
        let lastIndex = points.count - 1
        let step = Double(lastIndex) / Double(limit - 1)
        var lastPicked = -1
        for i in 0..<limit {
            let idx = Int((Double(i) * step).rounded())
            let clamped = min(idx, lastIndex)
            if clamped != lastPicked {
                result.append(points[clamped])
                lastPicked = clamped
            }
        }
        // Guarantee the final point is present.
        if result.last != points[lastIndex] {
            result.append(points[lastIndex])
        }
        return result
    }
}
