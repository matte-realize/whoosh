import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Task 10 — `WireMapper` (rear-camera `RideStatus` → allowlisted
/// `WireRideStatus`). Tests MAP-1…6 from the design acceptance criteria.
/// Written test-first.
struct WireMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let mapper = WireMapper()

    private func status(
        rideState: RideState = .recording,
        activeDuration: TimeInterval = 123.4,
        distanceMeters: Double = 5_432,
        speed: Double? = 5.76,
        cameraState: CameraRecordingState = .recording(.standard),
        cameraStopReason: CameraStopReason? = nil,
        storage: StorageStatus = .ok,
        thermal: ThermalLevel = .nominal,
        batteryFraction: Double = 0.734,
        charging: Bool = false,
        banner: String? = nil,
        crashDeadline: Date? = nil,
        lastClipSavedAt: Date? = nil
    ) -> RideStatus {
        RideStatus(
            rideState: rideState,
            activeDurationAnchor: activeDuration,
            anchorDate: now,
            distanceMeters: distanceMeters,
            speedMetersPerSecond: speed,
            cameraState: cameraState,
            cameraStopReason: cameraStopReason,
            storageStatus: storage,
            thermalLevel: thermal,
            phoneBatteryPercent: batteryFraction,
            isCharging: charging,
            banner: banner,
            crashCountdownDeadline: crashDeadline,
            lastClipSavedAt: lastClipSavedAt,
            lastDegradationNote: "secret internal note"
        )
    }

    private func map(_ s: RideStatus, clipCount: Int = 0, demo: Bool = false, watchEnabled: Bool = true) -> WireRideStatus {
        mapper.map(s, rideId: "ride-1", epoch: 3, seq: 9, clipCount: clipCount, demo: demo, watchEnabled: watchEnabled, now: now)
    }

    // MAP-1: SI units are rounded into wire units (10 m, 0.1 m/s, ms, percent).
    @Test func mapsUnitsWithRounding() {
        let w = map(status())
        #expect(w.distance10m == 543)         // 5432 / 10 = 543.2 → 543
        #expect(w.speedDms == 58)             // 5.76 * 10 = 57.6 → 58
        #expect(w.activeMs == 123_400)        // 123.4 s → 123400 ms
        #expect(w.phone.batteryPct == 73)     // 0.734 → 73
        #expect(w.rideId == "ride-1")
        #expect(w.epoch == 3)
        #expect(w.seq == 9)
    }

    // MAP-2: ride and camera states map to codes; nil speed stays nil.
    @Test func mapsStatesAndNilSpeed() {
        let w = map(status(rideState: .paused, speed: nil, cameraState: .preparing))
        #expect(w.state == .paused)
        #expect(w.speedDms == nil)
        #expect(w.camera.feature == .on)
        #expect(w.camera.state == .preparing)
        #expect(w.camera.reason == nil)
    }

    // MAP-3: camera stop/degrade/interrupt map to the right reason codes;
    // a normal ride-ended stop carries no trouble reason.
    @Test func mapsCameraReasons() {
        #expect(map(status(cameraState: .stopped(.thermal))).camera.reason == .thermal)
        #expect(map(status(cameraState: .stopped(.storage))).camera.reason == .storage)
        #expect(map(status(cameraState: .stopped(.permission))).camera.reason == .permission)
        #expect(map(status(cameraState: .stopped(.rideEnded))).camera.reason == nil)
        #expect(map(status(cameraState: .degraded(.standard, .battery))).camera.reason == .battery)
        #expect(map(status(cameraState: .interrupted(.audioOrVideoDeviceInUse))).camera.reason == .interrupted)
        #expect(map(status(cameraState: .off)).camera.feature == .off)
    }

    // MAP-4: banner is a fixed code derived from state, never the free-text
    // banner or degradation note (privacy allowlist).
    @Test func derivesBannerCodeAndDropsFreeText() {
        #expect(map(status(rideState: .signalLost, banner: "Searching for GPS…")).banner == .signalLost)
        #expect(map(status(cameraState: .failed(.writer), banner: "boom")).banner == .failed)
        #expect(map(status(cameraState: .stopped(.permission))).banner == .permissionRevoked)
        #expect(map(status(banner: "arbitrary phone text")).banner == .none)
        // The whole mapped value still passes the package allowlist (no free text).
        let w = map(status(banner: "home address leak attempt"))
        #expect(WireAllowlist.validate(w).isEmpty)
    }

    // MAP-5: transient flags derive from storage + thermal, sorted; clip count
    // and lastSavedAgo are relative.
    @Test func mapsFlagsAndClip() {
        let w = map(status(storage: .warn, thermal: .serious, lastClipSavedAt: now.addingTimeInterval(-4)), clipCount: 2)
        #expect(w.flags == [WireStatusFlag.phoneHot, .storageLow].sorted())
        #expect(w.clip.count == 2)
        #expect(w.clip.lastSavedAgoMs == 4_000)
        // No storage/thermal trouble → no flags.
        #expect(map(status()).flags.isEmpty)
    }

    // MAP-6: demo and watchEnabled flags pass through; crash is not mapped here
    // (attached by the remote); negative/garbage inputs clamp safely.
    @Test func passesFlagsAndClampsGarbage() {
        let w = map(status(crashDeadline: now.addingTimeInterval(10)), demo: true, watchEnabled: false)
        #expect(w.demo == true)
        #expect(w.watchEnabled == false)
        #expect(w.crash == nil)

        let bad = map(status(activeDuration: -5, distanceMeters: -100, speed: -3, batteryFraction: 2.0))
        #expect(bad.activeMs == 0)
        #expect(bad.distance10m == 0)
        #expect(bad.speedDms == nil)
        #expect(bad.phone.batteryPct == 100)
    }
}
