import Foundation
import Testing
@testable import Whoosh

/// Model-level tests for the rear-camera domain types (rear-camera spec task 2):
/// Codable round-trips, `RideCameraTuning` defaults/ranges/clamps from the design
/// table, `CaptureProfile` profile values, and the additive `AlertKind` cases.
struct CameraModelsTests {
    private static let epoch = Date(timeIntervalSince1970: 0)
    private static let rideID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private static let clipID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

    // MARK: - CaptureProfile defaults (design "RideCameraTuning" / O-CAM3)

    @Test func standardProfileMatchesSpec() {
        let p = CaptureProfile.standard
        #expect(p.name == "Standard")
        #expect(p.width == 1920)
        #expect(p.height == 1080)
        #expect(p.framesPerSecond == 30)
        #expect(p.codec == .hevc)
        #expect(p.averageBitrate == 5_000_000)
    }

    @Test func efficientProfileMatchesSpec() {
        let p = CaptureProfile.efficient
        #expect(p.width == 1280)
        #expect(p.height == 720)
        #expect(p.framesPerSecond == 30)
        #expect(p.codec == .hevc)
        #expect(p.averageBitrate == 2_500_000)
    }

    @Test func reducedProfileMatchesSpec() {
        let p = CaptureProfile.reduced
        #expect(p.width == 1280)
        #expect(p.height == 720)
        #expect(p.framesPerSecond == 15)
        #expect(p.codec == .hevc)
        #expect(p.averageBitrate == 1_200_000)
    }

    @Test func captureProfileCodableRoundTrip() throws {
        for p in [CaptureProfile.standard, .efficient, .reduced] {
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(CaptureProfile.self, from: data)
            #expect(decoded == p)
        }
    }

    // MARK: - RideCameraTuning defaults match the design table

    @Test func tuningDefaultsMatchSpec() {
        let t = RideCameraTuning()
        #expect(t.segmentLength == 15)
        #expect(t.movieFragmentInterval == 2)
        #expect(t.keyFrameInterval == 1)
        #expect(t.ringMaxDuration == 10 * 60)
        #expect(t.ringMaxBytes == 1_000_000_000)
        #expect(t.pinnedMaxBytes == 2_000_000_000)
        #expect(t.manualPinPre == 30)
        #expect(t.manualPinPost == 15)
        #expect(t.detectionPinPre == 15)
        #expect(t.detectionPinPost == 10)
        #expect(t.crashPinPre == 60)
        #expect(t.crashPinPost == 30)
        #expect(t.coalesceGap == 5)
        #expect(t.maxClipDuration == 180)
        #expect(t.autoPinCooldown == 20)
        #expect(t.maxAutoPinsPerRide == 10)
        #expect(t.manualSaveDebounce == 2)
        #expect(t.freeSpaceStart == 2_000_000_000)
        #expect(t.freeSpaceWarn == 1_000_000_000)
        #expect(t.freeSpaceStop == 500_000_000)
        #expect(t.batterySuggestEfficient == 0.20)
        #expect(t.batteryStopFloor == 0.08)
        #expect(t.interruptedNoticeThreshold == 5)
        #expect(t.resumeAttempts == 3)
        #expect(t.resumeAttemptWindow == 30)
        #expect(t.mountGrace == 20)
        #expect(t.unlockHoldDuration == 1.0)
        #expect(t.unlockInactivityWindow == 10)
        #expect(t.dimBrightness == 0.0)
        #expect(t.redDotShiftPeriod == 60)
        #expect(t.clipRetention == 30 * 24 * 60 * 60)
        #expect(t.testRecordingLength == 10)
        #expect(t.backgroundFinalizeBudget == 3)
        #expect(t.writerRestartDelay == 2)
    }

    @Test func tuningRangesMatchSpec() {
        let t = RideCameraTuning()
        #expect(t.segmentLengthRange == 10...30)
        #expect(t.ringMaxDurationRange == (2 * 60)...(30 * 60))
        #expect(t.ringMaxBytesRange == 256_000_000...4_000_000_000)
        #expect(t.mountGraceRange == 5...60)
    }

    // MARK: - RideCameraTuning clamps (ranges from the design table)

    @Test(arguments: [
        (5.0, 10.0), (10.0, 10.0), (15.0, 15.0), (30.0, 30.0), (45.0, 30.0),
    ])
    func segmentLengthClampsToRange(requested: TimeInterval, expected: TimeInterval) {
        #expect(RideCameraTuning().clampSegmentLength(requested) == expected)
    }

    @Test(arguments: [
        (60.0, 120.0), (120.0, 120.0), (600.0, 600.0), (1800.0, 1800.0), (3600.0, 1800.0),
    ])
    func ringDurationClampsToRange(requested: TimeInterval, expected: TimeInterval) {
        #expect(RideCameraTuning().clampRingMaxDuration(requested) == expected)
    }

    @Test(arguments: [
        (100_000_000, 256_000_000), (256_000_000, 256_000_000),
        (1_000_000_000, 1_000_000_000), (4_000_000_000, 4_000_000_000),
        (9_000_000_000, 4_000_000_000),
    ])
    func ringBytesClampsToRange(requested: Int64, expected: Int64) {
        #expect(RideCameraTuning().clampRingMaxBytes(requested) == expected)
    }

    @Test(arguments: [
        (1.0, 5.0), (5.0, 5.0), (20.0, 20.0), (60.0, 60.0), (120.0, 60.0),
    ])
    func mountGraceClampsToRange(requested: TimeInterval, expected: TimeInterval) {
        #expect(RideCameraTuning().clampMountGrace(requested) == expected)
    }

    @Test func tuningPinWindowBySource() {
        let t = RideCameraTuning()
        #expect(t.pinPrePost(for: .manual) == (30, 15))
        #expect(t.pinPrePost(for: .detection) == (15, 10))
        #expect(t.pinPrePost(for: .crash) == (60, 30))
        // demo mirrors manual windows
        #expect(t.pinPrePost(for: .demo) == (30, 15))
    }

    @Test func tuningCodableRoundTrip() throws {
        let t = RideCameraTuning()
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(RideCameraTuning.self, from: data)
        #expect(decoded == t)
    }

    // MARK: - Enum raw values and CaseIterable completeness

    @Test func clipReasonRawValues() {
        #expect(ClipReason.manual.rawValue == "manual")
        #expect(ClipReason.detection.rawValue == "detection")
        #expect(ClipReason.crash.rawValue == "crash")
        #expect(ClipReason.demo.rawValue == "demo")
        #expect(ClipReason.allCases.count == 4)
    }

    @Test func clipStateRawValues() {
        #expect(ClipState.pending.rawValue == "pending")
        #expect(ClipState.saved.rawValue == "saved")
        #expect(ClipState.endedEarly.rawValue == "ended_early")
        #expect(ClipState.allCases.count == 3)
    }

    @Test func thermalLevelOrdering() {
        #expect(ThermalLevel.nominal < ThermalLevel.fair)
        #expect(ThermalLevel.fair < ThermalLevel.serious)
        #expect(ThermalLevel.serious < ThermalLevel.critical)
        #expect(ThermalLevel.allCases.count == 4)
    }

    @Test func storageStatusCases() {
        #expect(StorageStatus.allCases.count == 3)
        #expect(StorageStatus.ok.rawValue == "ok")
        #expect(StorageStatus.warn.rawValue == "warn")
        #expect(StorageStatus.stop.rawValue == "stop")
    }

    @Test func cameraPermissionStatusCanStart() {
        #expect(CameraPermissionStatus.authorized.canStartCapture == true)
        #expect(CameraPermissionStatus.notDetermined.canStartCapture == false)
        #expect(CameraPermissionStatus.denied.canStartCapture == false)
        #expect(CameraPermissionStatus.restricted.canStartCapture == false)
    }

    // MARK: - Enums with associated values round-trip

    @Test func cameraStopReasonCodableRoundTrip() throws {
        for r in CameraStopReason.allCases {
            let data = try JSONEncoder().encode(r)
            let decoded = try JSONDecoder().decode(CameraStopReason.self, from: data)
            #expect(decoded == r)
        }
    }

    @Test func interruptionReasonKindCodableRoundTrip() throws {
        for r in InterruptionReasonKind.allCases {
            let data = try JSONEncoder().encode(r)
            let decoded = try JSONDecoder().decode(InterruptionReasonKind.self, from: data)
            #expect(decoded == r)
        }
    }

    @Test func cameraRecordingStateCodableRoundTrip() throws {
        let states: [CameraRecordingState] = [
            .off,
            .preparing,
            .recording(.standard),
            .degraded(.reduced, .thermal),
            .interrupted(.background),
            .stopped(.storage),
            .stopping,
            .failed(.writer),
        ]
        for s in states {
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(CameraRecordingState.self, from: data)
            #expect(decoded == s)
        }
    }

    @Test func cameraRecordingStateIsActive() {
        #expect(CameraRecordingState.recording(.standard).isRecording)
        #expect(CameraRecordingState.degraded(.reduced, .thermal).isRecording)
        #expect(!CameraRecordingState.off.isRecording)
        #expect(!CameraRecordingState.interrupted(.background).isRecording)
        #expect(!CameraRecordingState.stopped(.battery).isRecording)
    }

    @Test func screenModeCodableRoundTrip() throws {
        let deadline = Self.epoch.addingTimeInterval(20)
        let modes: [ScreenMode] = [
            .normal,
            .graceCountdown(until: deadline),
            .dimLocked,
            .unlockedTemporarily(until: deadline),
            .suspended,
        ]
        for m in modes {
            let data = try JSONEncoder().encode(m)
            let decoded = try JSONDecoder().decode(ScreenMode.self, from: data)
            #expect(decoded == m)
        }
    }

    @Test func rideRemoteCommandStopRequiresHold() {
        #expect(RideRemoteCommand.stop(confirmedByHold: true).isStopConfirmed == true)
        #expect(RideRemoteCommand.stop(confirmedByHold: false).isStopConfirmed == false)
        #expect(RideRemoteCommand.pause.isStopConfirmed == false)
    }

    @Test func rideRemoteCommandCodableRoundTrip() throws {
        let commands: [RideRemoteCommand] = [
            .pause, .resume, .saveClip, .stop(confirmedByHold: true), .cancelCrashCountdown,
        ]
        for c in commands {
            let data = try JSONEncoder().encode(c)
            let decoded = try JSONDecoder().decode(RideRemoteCommand.self, from: data)
            #expect(decoded == c)
        }
    }

    // MARK: - Entities

    @Test func segmentInfoCodableRoundTrip() throws {
        let seg = SegmentInfo(
            id: Self.clipID,
            rideId: Self.rideID,
            index: 3,
            start: Self.epoch,
            end: Self.epoch.addingTimeInterval(15),
            bytes: 500_000,
            profileName: "Standard",
            hasAudio: false,
            isPinned: false,
            hasGapBefore: true
        )
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(SegmentInfo.self, from: data)
        #expect(decoded == seg)
        #expect(seg.duration == 15)
    }

    @Test func clipRecordCodableRoundTrip() throws {
        let clip = ClipRecord(
            id: Self.clipID,
            rideId: Self.rideID,
            reasons: [.manual, .detection],
            createdAt: Self.epoch,
            start: Self.epoch,
            end: Self.epoch.addingTimeInterval(45),
            inOffset: 2,
            outOffset: 43,
            durationSeconds: 45,
            bytes: 28_000_000,
            thumbnailPath: "thumb.jpg",
            hasAudio: false,
            state: .saved,
            hasGap: false,
            eventRef: nil,
            expiresAt: Self.epoch.addingTimeInterval(30 * 24 * 60 * 60)
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(ClipRecord.self, from: data)
        #expect(decoded == clip)
    }

    @Test func clipRecordExpiry() {
        let clip = ClipRecord(
            id: Self.clipID, rideId: Self.rideID, reasons: [.manual],
            createdAt: Self.epoch, start: Self.epoch, end: Self.epoch.addingTimeInterval(45),
            inOffset: 0, outOffset: 45, durationSeconds: 45, bytes: 1,
            thumbnailPath: nil, hasAudio: false, state: .saved, hasGap: false,
            eventRef: nil, expiresAt: Self.epoch.addingTimeInterval(100)
        )
        #expect(clip.isExpired(at: Self.epoch.addingTimeInterval(99)) == false)
        #expect(clip.isExpired(at: Self.epoch.addingTimeInterval(100)) == true)
        #expect(clip.isExpired(at: Self.epoch.addingTimeInterval(101)) == true)
    }

    @Test func pinRequestAndWindowCodableRoundTrip() throws {
        let req = PinRequest(reason: .manual, eventTime: Self.epoch.addingTimeInterval(120), eventRef: nil)
        let reqData = try JSONEncoder().encode(req)
        #expect(try JSONDecoder().decode(PinRequest.self, from: reqData) == req)

        let window = PinWindow(
            segmentIds: [Self.clipID],
            inOffset: 5,
            outOffset: 50,
            pendingUntil: Self.epoch.addingTimeInterval(135),
            hasGap: false,
            truncatedAtRideStart: true
        )
        let winData = try JSONEncoder().encode(window)
        #expect(try JSONDecoder().decode(PinWindow.self, from: winData) == window)
    }

    @Test func nearMissEventCodableRoundTrip() throws {
        let event = NearMissEvent(
            id: Self.clipID,
            rideId: Self.rideID,
            occurredAt: Self.epoch.addingTimeInterval(300),
            latitude: 42.3601,
            longitude: -71.0589,
            kind: "approachingVehicle",
            confidence: 0.82,
            positionHint: "left",
            localClipId: nil
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NearMissEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test func rideStatusIsAnEquatableSnapshot() {
        let a = RideStatus(
            rideState: .recording,
            activeDurationAnchor: 0,
            anchorDate: Self.epoch,
            distanceMeters: 1234,
            speedMetersPerSecond: 5.5,
            cameraState: .recording(.standard),
            cameraStopReason: nil,
            storageStatus: .ok,
            thermalLevel: .nominal,
            phoneBatteryPercent: 0.75,
            isCharging: false,
            banner: nil,
            crashCountdownDeadline: nil,
            lastClipSavedAt: nil,
            lastDegradationNote: nil
        )
        var b = a
        #expect(a == b)
        b = RideStatus(
            rideState: .paused,
            activeDurationAnchor: a.activeDurationAnchor,
            anchorDate: a.anchorDate,
            distanceMeters: a.distanceMeters,
            speedMetersPerSecond: a.speedMetersPerSecond,
            cameraState: a.cameraState,
            cameraStopReason: a.cameraStopReason,
            storageStatus: a.storageStatus,
            thermalLevel: a.thermalLevel,
            phoneBatteryPercent: a.phoneBatteryPercent,
            isCharging: a.isCharging,
            banner: a.banner,
            crashCountdownDeadline: a.crashCountdownDeadline,
            lastClipSavedAt: a.lastClipSavedAt,
            lastDegradationNote: a.lastDegradationNote
        )
        #expect(a != b)
    }

    // MARK: - AlertKind additive cases (existing switches must still compile)

    @Test func alertKindAdditiveCasesEquatable() {
        #expect(AlertKind.cautionRearVehicle == .cautionRearVehicle)
        #expect(AlertKind.cameraInterrupted != .cameraResumed)
        #expect(AlertKind.cameraStopped(.thermal) == .cameraStopped(.thermal))
        #expect(AlertKind.cameraStopped(.thermal) != .cameraStopped(.storage))
        #expect(AlertKind.clipNotSaved(.storageFull) != .clipNotSaved(.nothingToSave))
        #expect(AlertKind.clipSaved == .clipSaved)
        #expect(AlertKind.phoneBatteryLow == .phoneBatteryLow)
    }
}
