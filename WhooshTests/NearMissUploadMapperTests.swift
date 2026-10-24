import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `NearMissUploadMapper` (rear-camera task 10/28,
/// Requirement 15.3; schema `20261024120100_near_misses.sql` +
/// `20261024130000_incident_mapping_and_indexes.sql`). Golden-JSON based so the
/// exact `near_misses` contract shape (column names, nullable confidence,
/// `source`, `share_publicly`) is pinned and drift is caught.
///
/// Role C receives events only, never video: the mapped value carries no
/// footage-referencing field by construction, and the local clip id is dropped.
struct NearMissUploadMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        localClipId: UUID? = nil,
        source: NearMissSource = .detected,
        latitude: Double? = 42.3601,
        longitude: Double? = -71.0589,
        isDemo: Bool = false
    ) -> NearMissEvent {
        NearMissEvent(
            id: UUID(),
            rideId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            occurredAt: now,
            latitude: latitude,
            longitude: longitude,
            kind: "vehicle",
            confidence: 0.82,
            positionHint: "left",
            source: source,
            isDemo: isDemo,
            localClipId: localClipId
        )
    }

    // UP-1: the mapped value carries only the contract fields; the local clip id
    // is dropped even when present, and no footage field exists on the type.
    @Test func mapsOnlyContractFieldsAndDropsClipId() throws {
        let source = event(localClipId: UUID())
        let mapped = try #require(
            NearMissUploadMapper.mapIfUploadable(source, sharePublicly: true)
        )

        #expect(mapped.rideId == source.rideId)
        #expect(mapped.occurredAt == source.occurredAt)
        #expect(mapped.latitude == source.latitude)
        #expect(mapped.longitude == source.longitude)
        #expect(mapped.kind == source.kind)
        #expect(mapped.confidence == source.confidence)
        #expect(mapped.positionHint == source.positionHint)
        #expect(mapped.source == "detected")
        #expect(mapped.sharePublicly == true)

        // The encoded JSON must not contain a clip id, video, thumbnail, or
        // footage reference — the whole point of "events only".
        let data = try JSONEncoder().encode(mapped)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        #expect(!json.contains("clip"))
        #expect(!json.contains("video"))
        #expect(!json.contains("thumbnail"))
        #expect(!json.contains("footage"))
        #expect(!json.contains("segment"))
        #expect(!json.contains("isdemo"))
        #expect(!json.contains(source.localClipId!.uuidString.lowercased()))
    }

    // Golden JSON: pins the exact contract column names, `[lat]/[lon]` values,
    // ISO-8601 time, `source`, and `share_publicly`.
    @Test func goldenJSON() throws {
        let mapped = try #require(
            NearMissUploadMapper.mapIfUploadable(event(), sharePublicly: false)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(mapped)
        let json = String(decoding: data, as: UTF8.self)

        let expected = """
        {"confidence":0.82,"kind":"vehicle","latitude":42.3601,"longitude":-71.0589,\
        "occurred_at":"2023-11-14T22:13:20Z","position_hint":"left","ride_id":\
        "11111111-1111-1111-1111-111111111111","share_publicly":false,"source":"detected"}
        """
        #expect(json == expected)
    }

    // A rider-reported event has no score: confidence maps to JSON null, and
    // `source` is the contract value `rider_reported`.
    @Test func riderReportedDropsConfidenceToNull() throws {
        let mapped = try #require(
            NearMissUploadMapper.mapIfUploadable(event(source: .riderReported), sharePublicly: false)
        )
        #expect(mapped.source == "rider_reported")
        #expect(mapped.confidence == nil)

        let data = try JSONEncoder().encode(mapped)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"confidence\":null"))
    }

    // An event inside the privacy-trim zone (no accepted coordinate) is dropped
    // from upload entirely: the mapper returns nil so a home/work-exposing event
    // never leaves the device.
    @Test func dropsEventWithoutCoordinate() {
        let trimmed = event(latitude: nil, longitude: nil)
        #expect(NearMissUploadMapper.mapIfUploadable(trimmed, sharePublicly: true) == nil)
    }

    @Test func keepsEventWithCoordinate() {
        #expect(NearMissUploadMapper.mapIfUploadable(event(), sharePublicly: false) != nil)
    }

    // The contract field names match the agreed column names exactly.
    @Test func usesContractColumnNames() throws {
        let mapped = try #require(
            NearMissUploadMapper.mapIfUploadable(event(), sharePublicly: false)
        )
        let data = try JSONEncoder().encode(mapped)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("ride_id"))
        #expect(json.contains("occurred_at"))
        #expect(json.contains("latitude"))
        #expect(json.contains("longitude"))
        #expect(json.contains("kind"))
        #expect(json.contains("confidence"))
        #expect(json.contains("position_hint"))
        #expect(json.contains("source"))
        #expect(json.contains("share_publicly"))
    }
}
