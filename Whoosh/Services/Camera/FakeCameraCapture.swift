import Foundation

/// Scriptable `CameraCapturing` for tests and SwiftUI previews: it drives the
/// capture state and events and feeds synthetic frames to both the `frameSink`
/// and the `recorder`, so the recorder/coordinator plumbing (task 18/19) can be
/// exercised before the real `CameraCaptureService` exists.
///
/// Lives under `Services/Camera/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Scripting:
/// - `start(profile:orientation:audioEnabled:)` records the request and (when
///   `autoRunning`, the default) emits `.running(profile)` immediately.
/// - `emitFrames(count:)` or `emitFrame(_:)` offer synthetic
///   `CameraCaptureFrame`s to the sink and `append` them to the recorder; the
///   sequence increments and `capturedAt` advances by the profile's frame
///   interval from a scripted anchor.
/// - `emit(_:)` delivers any `CameraCaptureEvent` through `onEvent`; `markNextFrameDiscontinuity()`
///   flags the next emitted frame (first frame after an interruption/restart).
/// Callbacks fire synchronously on the main actor so expectations are
/// deterministic. The fake never captures, stores, or transmits real media.
@MainActor
final class FakeCameraCapture: CameraCapturing {
    var frameSink: CameraFrameSink?
    var recorder: SegmentRecording?
    var onEvent: ((CameraCaptureEvent) -> Void)?

    private(set) var isRunning = false

    /// When `true` (default), `start` immediately emits `.running(profile)`.
    var autoRunning: Bool

    /// The wall-clock instant the next emitted frame is stamped with; advances by
    /// the active profile's frame interval per frame.
    var frameAnchor: Date

    // MARK: Recorded interactions (for test assertions)

    /// The `(profile, orientation, audioEnabled)` of the most recent `start`.
    private(set) var lastStart: (profile: CaptureProfile, orientation: CameraMountOrientation, audioEnabled: Bool)?
    /// Number of `start` calls.
    private(set) var startCount = 0
    /// Number of `stop` calls.
    private(set) var stopCount = 0
    /// Every profile step passed to `apply`, in order.
    private(set) var appliedSteps: [CaptureProfileStep] = []
    /// Every event delivered through `onEvent`, in order.
    private(set) var emittedEvents: [CameraCaptureEvent] = []
    /// Every frame offered to the sink / appended to the recorder, in order.
    private(set) var emittedFrames: [CameraCaptureFrame] = []

    private var activeProfile: CaptureProfile?
    private var nextSequence = 0
    private var nextPresentationTime: TimeInterval = 0
    private var pendingDiscontinuity = false

    init(
        autoRunning: Bool = true,
        frameAnchor: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.autoRunning = autoRunning
        self.frameAnchor = frameAnchor
    }

    // MARK: CameraCapturing

    func start(profile: CaptureProfile, orientation: CameraMountOrientation, audioEnabled: Bool) {
        startCount += 1
        lastStart = (profile, orientation, audioEnabled)
        activeProfile = profile
        recorder?.begin(profile: profile, orientation: orientation)
        if autoRunning {
            isRunning = true
            emit(.running(profile))
        }
    }

    func stop() {
        stopCount += 1
        isRunning = false
        recorder?.finish()
    }

    func apply(_ step: CaptureProfileStep) {
        appliedSteps.append(step)
        activeProfile = step.profile
    }

    // MARK: Scripting API (test/preview driven)

    /// Deliver an event through `onEvent` and record it. `.running` sets
    /// `isRunning`; `.interrupted` clears it.
    func emit(_ event: CameraCaptureEvent) {
        switch event {
        case .running:
            isRunning = true
        case .interrupted:
            isRunning = false
        case .interruptionEnded, .runtimeError, .systemPressureChanged:
            break
        }
        emittedEvents.append(event)
        onEvent?(event)
    }

    /// Flag the next emitted frame as a discontinuity (first frame after an
    /// interruption, restart, or format change).
    func markNextFrameDiscontinuity() {
        pendingDiscontinuity = true
    }

    /// Emit a single synthetic frame to the sink and the recorder, advancing the
    /// sequence and timestamps.
    @discardableResult
    func emitFrame() -> CameraCaptureFrame {
        let interval = frameInterval
        let frame = CameraCaptureFrame(
            presentationTime: nextPresentationTime,
            capturedAt: frameAnchor,
            sequence: nextSequence,
            isDiscontinuity: pendingDiscontinuity
        )
        nextSequence += 1
        nextPresentationTime += interval
        frameAnchor = frameAnchor.addingTimeInterval(interval)
        pendingDiscontinuity = false

        emittedFrames.append(frame)
        frameSink?.offer(frame)
        recorder?.append(frame)
        return frame
    }

    /// Emit `count` synthetic frames in order.
    func emitFrames(count: Int) {
        for _ in 0..<max(0, count) {
            emitFrame()
        }
    }

    /// The frame interval of the active profile (defaults to 30 fps when no
    /// profile has started yet).
    private var frameInterval: TimeInterval {
        let fps = activeProfile?.framesPerSecond ?? 30
        return fps > 0 ? 1.0 / Double(fps) : 1.0 / 30.0
    }
}
