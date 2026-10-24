import Foundation

/// Pure helper that drops near-miss events whose coordinate falls inside the
/// route privacy-trim zone before upload (rear-camera spec task 28; privacy
/// steering "Privacy zones"). The route's first and last ~160 m are trimmed so
/// the rider's home or work isn't exposed; a near miss near either end must be
/// dropped too, never uploaded, so it can't re-expose a trimmed endpoint.
///
/// The event stores the **nearest accepted route point** coordinate (copied
/// verbatim by the recorder). An event is kept only when that exact coordinate
/// still exists in the trimmed route — i.e. it did not fall in a trimmed zone.
/// Events without a coordinate (already absent) are also dropped. The local copy
/// of the events is never mutated; this only filters the upload set.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only).
nonisolated enum NearMissTrimFilter {
    /// Returns the subset of `events` whose coordinate survives trimming
    /// `points` by `meters` from each end. An event with no coordinate, or whose
    /// coordinate was trimmed away, is dropped.
    static func uploadable(
        events: [NearMissEvent],
        points: [RoutePoint],
        meters: Double = RoutePrivacy.defaultTrimMeters
    ) -> [NearMissEvent] {
        let kept = RoutePrivacy.trim(points: points, meters: meters)
        guard !kept.isEmpty else { return [] }
        // A set of kept coordinates (rounded to avoid float jitter from the
        // verbatim copy; route points are stored, not recomputed, so an exact
        // match is expected, but rounding is a safe guard).
        let keptKeys = Set(kept.map(Self.key))
        return events.filter { event in
            guard let lat = event.latitude, let lon = event.longitude else { return false }
            return keptKeys.contains(Self.key(latitude: lat, longitude: lon))
        }
    }

    private static func key(_ point: RoutePoint) -> String {
        key(latitude: point.latitude, longitude: point.longitude)
    }

    /// A stable string key for a coordinate at ~1e-6° (about 0.1 m) precision.
    private static func key(latitude: Double, longitude: Double) -> String {
        "\(Int((latitude * 1_000_000).rounded())):\(Int((longitude * 1_000_000).rounded()))"
    }
}
