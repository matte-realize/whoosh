import Foundation
import Testing
@testable import Whoosh

/// Test UP-1 for the pure `NearMissUploadMapper` (rear-camera task 10,
/// Requirement 15.3, design "Detection events and near-miss records"). Written
/// test-first.
///
/// The mapper turns a local `NearMissEvent` into the exact `near_misses`
/// contract shape (`.kiro/team/supabase-contract.md`): ride id, occurred-at,
/// latitude, longitude, kind, confidence, position hint — and **nothing else**.
/// The local clip id and anything that could reference footage are dropped. A
/// unit test asserts that no footage-related field can survive the mapping
/// (Role C receives events only, never video).
struct NearMissUploadMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(localClipId: UUID?) -> NearMissEvent {
        NearMissEvent(
            id: UUID(),
            rideId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            occurredAt: now,
            latitude: 42.3601,
            longitude: -71.0589,
            kind: "vehicle",
            confidence: 0.82,
            positionHint: "left",
            localClipId: localClipId
        )
    }

    // UP-1: the mapped value carries only the contract fields; the local clip id
    // is dropped even when present, and no footage field exists on the mapped
    // type at all.
    @Test func mapsOnlyContractFieldsAndDropsClipId() {
        let source = event(localClipId: UUID())
        let mapped = NearMissUploadMapper.map(source)

        #expect(mapped.rideId == source.rideId)
        #expect(mapped.occurredAt == source.occurredAt)
        #expect(mapped.latitude == source.latitude)
        #expect(mapped.longitude == source.longitude)
        #expect(mapped.kind == source.kind)
        #expect(mapped.confidence == source.confidence)
        #expect(mapped.positionHint == source.positionHint)

        // The encoded JSON must not contain a clip id, video, thumbnail, or
        // footage reference — the whole point of "events only".
        let data = try! JSONEncoder().encode(mapped)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        #expect(!json.contains("clip"))
        #expect(!json.contains("video"))
        #expect(!json.contains("thumbnail"))
        #expect(!json.contains("footage"))
        #expect(!json.contains("segment"))
        // ...and the clip id value itself must not leak under any key.
        #expect(!json.contains(source.localClipId!.uuidString.lowercased()))
    }

    // An event inside the privacy-trim zone (no accepted coordinate) is dropped
    // from upload entirely: the mapper returns nil so a home/work-exposing event
    // never leaves the device.
    @Test func dropsEventWithoutCoordinate() {
        let trimmed = NearMissEvent(
            id: UUID(),
            rideId: UUID(),
            occurredAt: now,
            latitude: nil,
            longitude: nil,
            kind: "vehicle",
            confidence: 0.9,
            positionHint: nil,
            localClipId: nil
        )
        #expect(NearMissUploadMapper.mapIfUploadable(trimmed) == nil)
    }

    @Test func keepsEventWithCoordinate() {
        let mapped = NearMissUploadMapper.mapIfUploadable(event(localClipId: nil))
        #expect(mapped != nil)
    }

    // The contract field names match the agreed column names exactly, so the
    // JSON Role C ingests lines up with the migration/contract.
    @Test func usesContractColumnNames() {
        let data = try! JSONEncoder().encode(NearMissUploadMapper.map(event(localClipId: nil)))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("ride_id"))
        #expect(json.contains("occurred_at"))
        #expect(json.contains("latitude"))
        #expect(json.contains("longitude"))
        #expect(json.contains("kind"))
        #expect(json.contains("confidence"))
        #expect(json.contains("position_hint"))
    }
}
