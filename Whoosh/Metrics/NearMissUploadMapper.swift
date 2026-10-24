import Foundation

/// Pure mapper from a local `NearMissEvent` to the exact `near_misses` upload
/// contract shape (rear-camera spec task 10, Requirement 15.3; design
/// "Detection events and near-miss records"; contract in
/// `.kiro/team/supabase-contract.md`).
///
/// Role C's database receives **events only, never video**. The mapped value
/// has fields for ride id, occurred-at, latitude, longitude, kind, confidence,
/// and position hint — and **nothing** that could reference footage: the local
/// clip id is dropped, and there is no clip/video/thumbnail/segment field on the
/// mapped type at all. `UP-1` asserts this at the JSON level.
///
/// `id` and `user_id` are set by the backend (`default auth.uid()`), so they are
/// not part of the client payload. The `CodingKeys` match the agreed column
/// names (`ride_id`, `occurred_at`, `position_hint`).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only).
enum NearMissUploadMapper {

    /// The upload payload shape — exactly the `near_misses` contract fields.
    /// No footage-referencing field exists on this type by construction.
    struct Payload: Equatable, Codable, Sendable {
        let rideId: UUID
        let occurredAt: Date
        let latitude: Double?
        let longitude: Double?
        let kind: String
        let confidence: Double
        let positionHint: String?

        enum CodingKeys: String, CodingKey {
            case rideId = "ride_id"
            case occurredAt = "occurred_at"
            case latitude
            case longitude
            case kind
            case confidence
            case positionHint = "position_hint"
        }
    }

    /// Map an event to the contract shape, dropping the local clip id and
    /// everything else that is not a contract field.
    static func map(_ event: NearMissEvent) -> Payload {
        Payload(
            rideId: event.rideId,
            occurredAt: event.occurredAt,
            latitude: event.latitude,
            longitude: event.longitude,
            kind: event.kind,
            confidence: event.confidence,
            positionHint: event.positionHint
        )
    }

    /// Map only if the event is safe to upload: an event without an accepted
    /// coordinate (for example one that fell inside the route privacy-trim zone,
    /// so it has no nearest accepted route point) is **dropped** so a
    /// home/work-exposing event never leaves the device. Returns `nil` to drop.
    static func mapIfUploadable(_ event: NearMissEvent) -> Payload? {
        guard event.latitude != nil, event.longitude != nil else { return nil }
        return map(event)
    }
}
