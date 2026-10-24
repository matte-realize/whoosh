import Foundation
import Testing
@testable import Whoosh

/// Tests for the rear-camera seam fakes (rear-camera spec task 12). Each fake's
/// scripting API is covered: permission grant/denial/change, capture
/// state/events and frame feeding, segment recording, the in-memory segment
/// store and clip repository, the screen controller, and the mount-level sensor.
/// All fakes are main-actor isolated, so the suite is `@MainActor`.
@MainActor
struct CameraSeamFakesTests {

    // MARK: FakeCameraPermission

    @Test func permissionRequestFromNotDeterminedResolvesToGrant() async {
        let permission = FakeCameraPermission(status: .notDetermined, grantResult: .authorized)
        var observed: [CameraPermissionStatus] = []
        permission.onChange = { observed.append($0) }

        let result = await permission.request()

        #expect(result == .authorized)
        #expect(permission.status == .authorized)
        #expect(permission.requestCount == 1)
        #expect(observed == [.authorized])
    }

    @Test func permissionRequestCanResolveToDenied() async {
        let permission = FakeCameraPermission(status: .notDetermined, grantResult: .denied)

        let result = await permission.request()

        #expect(result == .denied)
        #expect(permission.status == .denied)
    }

    @Test func permissionRequestFromResolvedStateDoesNotChangeOrNotify() async {
        let permission = FakeCameraPermission(status: .denied)
        var changes = 0
        permission.onChange = { _ in changes += 1 }

        let result = await permission.request()

        #expect(result == .denied)
        #expect(changes == 0)
        #expect(permission.requestCount == 1)
    }

    @Test func permissionChangeStatusNotifies() {
        let permission = FakeCameraPermission(status: .authorized)
        var observed: [CameraPermissionStatus] = []
        permission.onChange = { observed.append($0) }

        permission.changeStatus(.denied)

        #expect(permission.status == .denied)
        #expect(observed == [.denied])
    }

    // MARK: FakeCameraCapture

    @Test func captureStartAutoRunsAndBeginsRecorder() {
        let capture = FakeCameraCapture()
        let recorder = FakeSegmentRecorder()
        capture.recorder = recorder
        var events: [CameraCaptureEvent] = []
        capture.onEvent = { events.append($0) }

        capture.start(profile: .standard, orientation: .landscapeLeft, audioEnabled: false)

        #expect(capture.isRunning)
        #expect(capture.startCount == 1)
        #expect(capture.lastStart?.profile == .standard)
        #expect(capture.lastStart?.orientation == .landscapeLeft)
        #expect(capture.lastStart?.audioEnabled == false)
        #expect(events == [.running(.standard)])
        #expect(recorder.beginCount == 1)
    }

    @Test func captureWithoutAutoRunningStaysIdleUntilEventEmitted() {
        let capture = FakeCameraCapture(autoRunning: false)
        capture.start(profile: .efficient, orientation: .portrait, audioEnabled: false)
        #expect(!capture.isRunning)

        capture.emit(.running(.efficient))
        #expect(capture.isRunning)
        #expect(capture.emittedEvents == [.running(.efficient)])
    }

    @Test func captureFeedsFramesToSinkAndRecorderInOrder() {
        let capture = FakeCameraCapture(frameAnchor: Date(timeIntervalSince1970: 100))
        let sink = CollectingFrameSink()
        let recorder = FakeSegmentRecorder()
        capture.frameSink = sink
        capture.recorder = recorder
        capture.start(profile: .standard, orientation: .portrait, audioEnabled: false)

        capture.emitFrames(count: 3)

        #expect(capture.emittedFrames.count == 3)
        #expect(sink.frames.count == 3)
        #expect(recorder.appendedFrames.count == 3)
        // Sequence increments and timestamps advance by the 30 fps interval.
        #expect(capture.emittedFrames.map(\.sequence) == [0, 1, 2])
        let times = capture.emittedFrames.map(\.presentationTime)
        #expect(abs(times[1] - times[0] - 1.0 / 30.0) < 1e-9)
        #expect(sink.frames == capture.emittedFrames)
        #expect(recorder.appendedFrames == capture.emittedFrames)
    }

    @Test func captureDiscontinuityFlagAppliesToNextFrameOnly() {
        let capture = FakeCameraCapture()
        capture.start(profile: .standard, orientation: .portrait, audioEnabled: false)

        capture.emitFrame()
        capture.markNextFrameDiscontinuity()
        let flagged = capture.emitFrame()
        let after = capture.emitFrame()

        #expect(flagged.isDiscontinuity)
        #expect(!after.isDiscontinuity)
    }

    @Test func captureStopFinishesRecorderAndClearsRunning() {
        let capture = FakeCameraCapture()
        let recorder = FakeSegmentRecorder()
        capture.recorder = recorder
        capture.start(profile: .standard, orientation: .portrait, audioEnabled: false)

        capture.stop()

        #expect(!capture.isRunning)
        #expect(capture.stopCount == 1)
        #expect(recorder.finishCount == 1)
    }

    @Test func captureApplyRecordsSteps() {
        let capture = FakeCameraCapture()
        let step = CaptureProfileStep(profile: .reduced, reason: .thermal, appliesLive: false)

        capture.apply(step)

        #expect(capture.appliedSteps == [step])
    }

    @Test func captureInterruptedEventClearsRunning() {
        let capture = FakeCameraCapture()
        capture.start(profile: .standard, orientation: .portrait, audioEnabled: false)
        #expect(capture.isRunning)

        capture.emit(.interrupted(.background))

        #expect(!capture.isRunning)
        #expect(capture.emittedEvents.contains(.interrupted(.background)))
    }

    // MARK: FakeSegmentRecorder

    @Test func recorderBuildsSegmentFromFramesOnRotate() {
        let rideId = UUID()
        let recorder = FakeSegmentRecorder(rideId: rideId, bytesPerSegment: 1_000)
        var finished: [SegmentInfo] = []
        recorder.onSegmentFinished = { finished.append($0) }
        recorder.begin(profile: .standard, orientation: .landscapeRight)

        let start = Date(timeIntervalSince1970: 0)
        recorder.append(frame(at: start, seq: 0))
        recorder.append(frame(at: start.addingTimeInterval(1), seq: 1))
        recorder.rotate(at: start.addingTimeInterval(15))

        #expect(recorder.rotateCount == 1)
        #expect(finished.count == 1)
        #expect(finished[0].rideId == rideId)
        #expect(finished[0].index == 0)
        #expect(finished[0].start == start)
        #expect(finished[0].end == start.addingTimeInterval(15))
        #expect(finished[0].bytes == 1_000)
        #expect(finished[0].profileName == CaptureProfile.standard.name)
        #expect(!finished[0].isPinned)
    }

    @Test func recorderFinishClosesOpenSegment() {
        let recorder = FakeSegmentRecorder()
        var finished: [SegmentInfo] = []
        recorder.onSegmentFinished = { finished.append($0) }
        recorder.begin(profile: .efficient, orientation: .portrait)

        let start = Date(timeIntervalSince1970: 10)
        recorder.append(frame(at: start, seq: 0))
        recorder.finish()

        #expect(recorder.finishCount == 1)
        #expect(finished.count == 1)
        #expect(finished[0].profileName == CaptureProfile.efficient.name)
    }

    @Test func recorderExplicitSegmentAndFailureAreScriptable() {
        let recorder = FakeSegmentRecorder()
        var finished: [SegmentInfo] = []
        var failures: [SegmentRecorderError] = []
        recorder.onSegmentFinished = { finished.append($0) }
        recorder.onFailure = { failures.append($0) }

        let segment = SegmentInfo(
            id: UUID(), rideId: UUID(), index: 7,
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 15),
            bytes: 42, profileName: "Standard", hasAudio: false,
            isPinned: false, hasGapBefore: false
        )
        recorder.finishSegment(segment)
        recorder.fail(.writerFailed)

        #expect(finished == [segment])
        #expect(failures == [.writerFailed])
    }

    @Test func recorderFlagsGapAfterDiscontinuityWithinSegment() {
        let recorder = FakeSegmentRecorder()
        var finished: [SegmentInfo] = []
        recorder.onSegmentFinished = { finished.append($0) }
        recorder.begin(profile: .standard, orientation: .portrait)

        let start = Date(timeIntervalSince1970: 0)
        recorder.append(frame(at: start, seq: 0))
        recorder.append(frame(at: start.addingTimeInterval(1), seq: 1, discontinuity: true))
        recorder.finish()

        #expect(finished.count == 1)
        #expect(finished[0].hasGapBefore)
    }

    // MARK: InMemorySegmentStore

    @Test func segmentStoreRegistersSortsAndReportsBytes() {
        let rideId = UUID()
        let store = InMemorySegmentStore()
        let early = segment(rideId: rideId, index: 0, end: 10, bytes: 100)
        let late = segment(rideId: rideId, index: 1, end: 20, bytes: 200)
        store.register(late)
        store.register(early)

        let listed = store.segments(rideId: rideId)

        #expect(listed.map(\.id) == [early.id, late.id])
        #expect(store.bytesUsed() == 300)
    }

    @Test func segmentStoreLinkMarksPinned() {
        let rideId = UUID()
        let seg = segment(rideId: rideId, index: 0, end: 10, bytes: 100)
        let store = InMemorySegmentStore(segments: [seg])
        let clipId = UUID()

        store.link(segmentIds: [seg.id], toClip: clipId)

        #expect(store.isPinned(seg.id) == true)
        #expect(store.clipLinks[clipId] == [seg.id])
    }

    @Test func segmentStoreDeleteAndPurgeOrphans() {
        let keepRide = UUID()
        let orphanRide = UUID()
        let kept = segment(rideId: keepRide, index: 0, end: 10, bytes: 100)
        let orphan = segment(rideId: orphanRide, index: 0, end: 10, bytes: 100)
        let store = InMemorySegmentStore(segments: [kept, orphan])

        store.purgeOrphans(keepingRides: [keepRide])

        #expect(store.segments(rideId: keepRide).count == 1)
        #expect(store.segments(rideId: orphanRide).isEmpty)
        #expect(store.lastPurgeKeptRides == [keepRide])

        store.delete(ids: [kept.id])
        #expect(store.segments(rideId: keepRide).isEmpty)
    }

    @Test func segmentStoreFreeSpaceIsScriptable() {
        let store = InMemorySegmentStore(freeSpaceBytes: 123)
        #expect(store.freeSpace() == 123)
        store.freeSpaceBytes = 456
        #expect(store.freeSpace() == 456)
    }

    // MARK: InMemoryClipRepository

    @Test func clipRepositoryUpsertsAndSortsByCreatedAt() throws {
        let rideId = UUID()
        let repo = InMemoryClipRepository()
        let older = clip(rideId: rideId, createdAt: 10)
        let newer = clip(rideId: rideId, createdAt: 20)
        try repo.save(older)
        try repo.save(newer)

        let listed = try repo.clips(rideId: rideId)

        #expect(listed.map(\.id) == [newer.id, older.id])
        #expect(try repo.clip(id: older.id) == older)
    }

    @Test func clipRepositoryDeletePaths() throws {
        let rideA = UUID()
        let rideB = UUID()
        let a1 = clip(rideId: rideA, createdAt: 1)
        let a2 = clip(rideId: rideA, createdAt: 2)
        let b1 = clip(rideId: rideB, createdAt: 3)
        let repo = InMemoryClipRepository(clips: [a1, a2, b1])

        try repo.delete(id: a1.id)
        #expect(try repo.clips(rideId: rideA).map(\.id) == [a2.id])

        try repo.deleteAll(rideId: rideA)
        #expect(try repo.clips(rideId: rideA).isEmpty)
        #expect(try repo.clips(rideId: rideB).count == 1)

        try repo.deleteAll()
        #expect(try repo.clips(rideId: rideB).isEmpty)
    }

    @Test func clipRepositoryExpiredAndTotalBytes() throws {
        let rideId = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let expired = clip(rideId: rideId, createdAt: 0, expiresAt: 500, bytes: 10)
        let live = clip(rideId: rideId, createdAt: 0, expiresAt: 2_000, bytes: 20)
        let repo = InMemoryClipRepository(clips: [expired, live])

        #expect(try repo.expired(now: now).map(\.id) == [expired.id])
        #expect(try repo.totalBytes() == 30)
    }

    // MARK: FakeScreenController

    @Test func screenControllerSetBrightnessClampsAndRecords() {
        let screen = FakeScreenController(brightness: 0.5)
        screen.setBrightness(0.0)
        screen.setBrightness(2.0) // clamps to 1
        screen.setBrightness(-1.0) // clamps to 0

        #expect(screen.setBrightnessHistory == [0.0, 1.0, 0.0])
        #expect(screen.brightness == 0.0)
    }

    @Test func screenControllerIdleTimerRecorded() {
        let screen = FakeScreenController()
        screen.setIdleTimerDisabled(true)
        screen.setIdleTimerDisabled(false)

        #expect(screen.setIdleTimerCount == 2)
        #expect(screen.idleTimerDisabled == false)
    }

    @Test func screenControllerSystemBrightnessChangeNotifiesWithoutRecordingAsOurWrite() {
        let screen = FakeScreenController(brightness: 0.5)
        var observed: [Double] = []
        screen.onSystemBrightnessChange = { observed.append($0) }

        screen.simulateSystemBrightnessChange(0.8)

        #expect(observed == [0.8])
        #expect(screen.brightness == 0.8)
        #expect(screen.setBrightnessHistory.isEmpty)
    }

    // MARK: FakeMountLevelSensor

    @Test func mountSensorDeliversGravityOnlyWhileSensing() {
        let sensor = FakeMountLevelSensor()
        var samples: [GravityVector] = []
        sensor.onGravity = { samples.append($0) }

        sensor.emit(GravityVector(x: 0, y: -1, z: 0)) // ignored: not sensing
        #expect(samples.isEmpty)

        sensor.start()
        #expect(sensor.isSensing)
        let scripted = [
            GravityVector(x: 0, y: -1, z: 0),
            GravityVector(x: 0.1, y: -0.99, z: 0),
        ]
        sensor.emitGravity(scripted)
        #expect(samples == scripted)

        sensor.stop()
        #expect(!sensor.isSensing)
        sensor.emit(GravityVector(x: 1, y: 0, z: 0)) // ignored again
        #expect(samples == scripted)
        #expect(sensor.startCount == 1)
        #expect(sensor.stopCount == 1)
    }

    // MARK: Helpers

    private func frame(at date: Date, seq: Int, discontinuity: Bool = false) -> CameraCaptureFrame {
        CameraCaptureFrame(
            presentationTime: Double(seq) / 30.0,
            capturedAt: date,
            sequence: seq,
            isDiscontinuity: discontinuity
        )
    }

    private func segment(rideId: UUID, index: Int, end: TimeInterval, bytes: Int64) -> SegmentInfo {
        SegmentInfo(
            id: UUID(),
            rideId: rideId,
            index: index,
            start: Date(timeIntervalSince1970: end - 15),
            end: Date(timeIntervalSince1970: end),
            bytes: bytes,
            profileName: "Standard",
            hasAudio: false,
            isPinned: false,
            hasGapBefore: false
        )
    }

    private func clip(
        rideId: UUID,
        createdAt: TimeInterval,
        expiresAt: TimeInterval = 30 * 24 * 60 * 60,
        bytes: Int64 = 0
    ) -> ClipRecord {
        let created = Date(timeIntervalSince1970: createdAt)
        return ClipRecord(
            id: UUID(),
            rideId: rideId,
            reasons: [.manual],
            createdAt: created,
            start: created,
            end: created.addingTimeInterval(45),
            inOffset: 0,
            outOffset: 45,
            durationSeconds: 45,
            bytes: bytes,
            thumbnailPath: nil,
            hasAudio: false,
            state: .saved,
            hasGap: false,
            eventRef: nil,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }
}

/// A trivial `CameraFrameSink` that collects offered frames, used to assert the
/// capture fake feeds its sink in order.
private final class CollectingFrameSink: CameraFrameSink, @unchecked Sendable {
    private(set) var frames: [CameraCaptureFrame] = []
    func offer(_ frame: CameraCaptureFrame) { frames.append(frame) }
}
