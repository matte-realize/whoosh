import Foundation

/// Pure mapper from a local `NearMissEvent` to the exact `near_misses` upload
/// contract shape (rear-camera spec task 10/28, Requirement 15.3; design
/// "Detection events and near-miss records"; contract in
/// `.kiro/team/supabase-contract.md`; schema in
/// `supabase/migrations/20261024120100_near_misses.sql` +
/// `20261024130000_incident_mapping_and_indexes.sql`).
///
/// Role C's database receives **events only, never video**. The mapped value
/// has fields for ride id, occurred-at, latitude, longitude, kind, confidence,
/// position hint, `source`, and `share_publicly` — and **nothing** that could
/// reference footage: the local clip id is dropped, and there is no
/// clip/video/thumbnail/segment field on the mapped type at all. `UP-1` asserts
/// this at the JSON level.
///
/// Column shape (the real migration, not the older draft):
/// - `confidence` is **nullable** and required only when `source = 'detected'`.
///   A `rider_reported` event may carry `nil` confidence (storing `1.0` would
///   misrepresent it, per the incident-mapping migration).
/// - `source` is `'detected'` or `'rider_reported'` (DB default `'detected'`).
/// - `share_publicly` is per incident, separate from the ride's flag, and is
///   set from the global "Share new rides on the Whoosh website" setting at
///   upload time (not stored on the local event; the local copy stays complete).
///
/// `id` and `user_id` are set by the backend (`default auth.uid()`), so they are
/// not part of the client payload. The `CodingKeys` match the agreed column
/// names (`ride_id`, `occurred_at`, `position_hint`, `share_publicly`).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only).
enum NearMissUploadMapper {

    /// The upload payload shape — exactly the `near_misses` contract fields.
    /// No footage-referencing field exists on this type by construction.
    struct Payload: Equatable, Codable, Sendable {
        let rideId: UUID
        let occurredAt: Date
        let latitude: Double
        let longitude: Double
        let kind: String
        /// Nullable in the DB; required only when `source == "detected"`. A
        /// rider-reported event may be `nil`. Encodes as JSON `null` when absent.
        let confidence: Double?
        let positionHint: String?
        /// `"detected"` or `"rider_reported"`.
        let source: String
        /// Per-incident public-sharing flag, stamped from the global setting.
        let sharePublicly: Bool

        enum CodingKeys: String, CodingKey {
            case rideId = "ride_id"
            case occurredAt = "occurred_at"
            case latitude
            case longitude
            case kind
            case confidence
            case positionHint = "position_hint"
            case source
            case sharePublicly = "share_publicly"
        }

        /// Synthesized `Codable` omits `nil` optionals; send them as explicit
        /// `null` so an upsert clears a stale value instead of keeping it.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rideId, forKey: .rideId)
            try container.encode(occurredAt, forKey: .occurredAt)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
            try container.encode(kind, forKey: .kind)
            try container.encode(confidence, forKey: .confidence)
            try container.encode(positionHint, forKey: .positionHint)
            try container.encode(source, forKey: .source)
            try container.encode(sharePublicly, forKey: .sharePublicly)
        }
    }

    /// Map an uploadable event to the contract shape, dropping the local clip id
    /// and everything else that is not a contract field. `sharePublicly` comes
    /// from the caller (the global sharing setting at upload time). Returns `nil`
    /// to **drop** an event that is not safe to upload — one without an accepted
    /// coordinate (for example one that fell inside the route privacy-trim zone),
    /// so a home/work-exposing event never leaves the device.
    static func mapIfUploadable(
        _ event: NearMissEvent,
        sharePublicly: Bool
    ) -> Payload? {
        guard let latitude = event.latitude, let longitude = event.longitude else {
            return nil
        }
        return Payload(
            rideId: event.rideId,
            occurredAt: event.occurredAt,
            latitude: latitude,
            longitude: longitude,
            kind: event.kind,
            // A detected event always has a score; a rider report has none.
            confidence: event.source == .detected ? event.confidence : nil,
            positionHint: event.positionHint,
            source: event.source.rawValue,
            sharePublicly: sharePublicly
        )
    }
}
