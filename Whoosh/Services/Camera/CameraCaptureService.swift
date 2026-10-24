import AVFoundation
import CoreVideo
import Foundation
import UIKit

/// The real AVFoundation capture service (rear-camera spec Requirement 3/4,
/// task 17). The **only** type in the app that owns an `AVCaptureSession`; it
/// lives in `Services/Camera/` so capture APIs stay confined there (privacy
/// rule 7).
///
/// ## Design
/// `CameraCaptureService` is the `@MainActor` seam type that conforms to
/// `CameraCapturing` and `CameraPreviewHost`. All AVFoundation ownership — the
/// session, device input, video output, sample-buffer delegate, and
/// notification observers — lives in a **nonisolated** `CaptureSessionBox` that
/// runs entirely **off the main actor** on dedicated serial queues
/// (`sessionQueue`, `videoQueue`). The service forwards intents to the box and
/// receives `CameraCaptureEvent`s back through a `Sendable` callback that hops to
/// the main actor. This keeps every capture operation off-main (design
/// "Concurrency") while the seam stays main-actor for view models.
///
/// ## What the box does
/// - Runs the **back wide camera by default**, with a **front-camera option**.
/// - Applies a `CaptureProfile` via the device `activeFormat` + frame-duration
///   (fps live; resolution at a boundary), enables stabilization when supported,
///   keeps continuous auto-exposure, prefers far-range continuous autofocus, and
///   locks orientation to the mount via the connection rotation angle.
/// - Observes thermal/system pressure, interruptions, and runtime errors.
/// - Feeds one `AVCaptureVideoDataOutput` (`alwaysDiscardsLateVideoFrames = true`)
///   to the `FramePipeline` (`VideoFrame`), the recorder (`CameraCaptureFrame`),
///   and the metadata `CameraFrameSink`.
///
/// Device-verified (task 31); the simulator has no camera.
@MainActor
final class CameraCaptureService: CameraCapturing, CameraPreviewHost {

    // MARK: CameraCapturing

    var frameSink: CameraFrameSink? {
        didSet { box.setMetadataSink(frameSink) }
    }
    var recorder: SegmentRecording?
    var onEvent: ((CameraCaptureEvent) -> Void)?

    private(set) var isRunning = false

    /// The real frame pipeline (`VideoFrame`, carrying the pixel buffer) fed in
    /// parallel with the recorder — the merge point of the metadata
    /// `CameraFrameSink` seam and the pixel-buffer `FrameSink` pipeline.
    var videoSink: FrameSink? {
        didSet { box.setVideoSink(videoSink) }
    }

    /// The camera to record with (back by default). Applied on the next `start`.
    var cameraPosition: CameraDevicePosition = .back

    private let box: CaptureSessionBox

    init() {
        self.box = CaptureSessionBox()
        // Route the box's events back to the main actor.
        box.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        // Route captured frames back to the main actor for the recorder seam
        // (the recorder is `@MainActor`; it dispatches writer work to its own
        // queue and never blocks capture). Capturing `self` (a main-actor class)
        // avoids sending the non-Sendable `SegmentRecording` across actors.
        box.setRecorderFrame { [weak self] frame in
            Task { @MainActor in self?.recorder?.append(frame) }
        }
    }

    // MARK: - CameraCapturing

    func start(profile: CaptureProfile, orientation: CameraMountOrientation, audioEnabled: Bool) {
        recorder?.begin(profile: profile, orientation: orientation)
        box.start(profile: profile, orientation: orientation, position: cameraPosition)
    }

    func stop() {
        box.stop()
        isRunning = false
        recorder?.finish()
    }

    func apply(_ step: CaptureProfileStep) {
        box.apply(step)
        if !step.appliesLive {
            // Resolution change reconfigured at a boundary: rotate the recorder.
            recorder?.rotate(at: Date())
        }
    }

    // MARK: - CameraPreviewHost

    func makePreviewView() -> UIView {
        let view = PreviewContainerView()
        box.attachPreview(view.previewLayer)
        return view
    }

    // MARK: - Private

    /// Track the running flag on the main actor from the box's events.
    private func handle(_ event: CameraCaptureEvent) {
        switch event {
        case .running:
            isRunning = true
        case .interrupted:
            isRunning = false
        case .interruptionEnded, .runtimeError, .systemPressureChanged:
            break
        }
        onEvent?(event)
    }
}

// MARK: - CaptureSessionBox (nonisolated; off-main)

/// Owns the `AVCaptureSession` and everything AVFoundation entirely off the main
/// actor. All session/device work runs on `sessionQueue`; sample buffers arrive
/// on `videoQueue`. Events are reported through `onEvent` (a `Sendable` closure
/// the service sets to hop to the main actor). Mutable fan-out state is
/// lock-protected.
private nonisolated final class CaptureSessionBox: NSObject, @unchecked Sendable {

    /// Delivered for every capture state change; set by the service.
    var onEvent: (@Sendable (CameraCaptureEvent) -> Void)? {
        get { lock.withLock { _onEvent } }
        set { lock.withLock { _onEvent = newValue } }
    }

    private let lock = NSLock()
    private var _onEvent: (@Sendable (CameraCaptureEvent) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "whoosh.camera.session")
    private let videoQueue = DispatchQueue(label: "whoosh.camera.video", qos: .userInitiated)

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()

    // Frame fan-out (video-queue + lock protected).
    private var metadataSink: CameraFrameSink?
    private var videoSink: FrameSink?
    private var recorderAppend: (@Sendable (CameraCaptureFrame) -> Void)?
    private var sequence = 0
    private var pendingDiscontinuity = false
    private var fps = 30
    private var displayOrientation: VideoFrame.DisplayOrientation = .up

    // Observers.
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
    }

    // MARK: Fan-out configuration

    func setMetadataSink(_ sink: CameraFrameSink?) { lock.withLock { metadataSink = sink } }
    func setVideoSink(_ sink: FrameSink?) { lock.withLock { videoSink = sink } }
    func setRecorderFrame(_ append: (@Sendable (CameraCaptureFrame) -> Void)?) {
        lock.withLock { recorderAppend = append }
    }

    // MARK: Intents

    func start(profile: CaptureProfile, orientation: CameraMountOrientation, position: CameraDevicePosition) {
        lock.withLock {
            fps = max(1, profile.framesPerSecond)
            displayOrientation = Self.displayOrientation(for: orientation)
            sequence = 0
            pendingDiscontinuity = false
        }
        sessionQueue.async { [weak self] in
            self?.configureAndStart(profile: profile, orientation: orientation, position: position)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.teardownObservers()
            if self.session.isRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
            self.videoDeviceInput = nil
        }
    }

    func apply(_ step: CaptureProfileStep) {
        let profile = step.profile
        let appliesLive = step.appliesLive
        lock.withLock { fps = max(1, profile.framesPerSecond) }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            if appliesLive {
                self.applyFrameDuration(profile.framesPerSecond, to: device)
            } else {
                self.session.beginConfiguration()
                self.selectFormat(for: profile, on: device)
                self.applyFrameDuration(profile.framesPerSecond, to: device)
                self.session.commitConfiguration()
            }
        }
    }

    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
        layer.videoGravity = .resizeAspectFill
    }

    // MARK: Session configuration (sessionQueue)

    private func configureAndStart(
        profile: CaptureProfile,
        orientation: CameraMountOrientation,
        position: CameraDevicePosition
    ) {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        guard let device = Self.captureDevice(for: position) else {
            session.commitConfiguration()
            emit(.runtimeError)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                emit(.runtimeError)
                return
            }
            session.addInput(input)
            videoDeviceInput = input
        } catch {
            session.commitConfiguration()
            emit(.runtimeError)
            return
        }

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            emit(.runtimeError)
            return
        }
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        selectFormat(for: profile, on: device)
        configureDevice(device, profile: profile)
        configureConnection(for: orientation)

        session.commitConfiguration()

        installObservers()
        session.startRunning()
        emit(.running(profile))
    }

    private func selectFormat(for profile: CaptureProfile, on device: AVCaptureDevice) {
        let best = device.formats.min(by: { a, b in
            score(a, for: profile) < score(b, for: profile)
        })
        guard let best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {}
    }

    private func score(_ format: AVCaptureDevice.Format, for profile: CaptureProfile) -> Int {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let pixels = Int(dims.width) * Int(dims.height)
        let target = profile.width * profile.height
        let pixelDelta = abs(pixels - target)
        let supportsFps = format.videoSupportedFrameRateRanges.contains {
            $0.maxFrameRate + 0.1 >= Double(profile.framesPerSecond)
        }
        return pixelDelta + (supportsFps ? 0 : 1_000_000_000)
    }

    private func configureDevice(_ device: AVCaptureDevice, profile: CaptureProfile) {
        do {
            try device.lockForConfiguration()
            applyFrameDuration(profile.framesPerSecond, to: device, alreadyLocked: true)
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .far
            }
            device.unlockForConfiguration()
        } catch {}
    }

    private func applyFrameDuration(_ fps: Int, to device: AVCaptureDevice, alreadyLocked: Bool = false) {
        guard fps > 0 else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= Double(fps) + 0.1 && $0.maxFrameRate + 0.1 >= Double(fps)
        }
        guard supported else { return }
        do {
            if !alreadyLocked { try device.lockForConfiguration() }
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            if !alreadyLocked { device.unlockForConfiguration() }
        } catch {}
    }

    private func configureConnection(for orientation: CameraMountOrientation) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        let angle = Self.rotationAngle(for: orientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: Observers

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
        ) { [weak self] _ in
            self?.emit(.runtimeError)
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil
        ) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil
        ) { [weak self] _ in
            self?.markDiscontinuity()
            self?.emit(.interruptionEnded)
        })
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.emitThermal()
        })
    }

    private func teardownObservers() {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func handleInterruption(_ note: Notification) {
        markDiscontinuity()
        emit(.interrupted(Self.interruptionKind(from: note)))
    }

    private func markDiscontinuity() {
        lock.withLock { pendingDiscontinuity = true }
    }

    private func emitThermal() {
        emit(.systemPressureChanged(Self.thermalLevel(from: ProcessInfo.processInfo.thermalState)))
    }

    private func emit(_ event: CameraCaptureEvent) {
        let callback = lock.withLock { _onEvent }
        callback?(event)
    }

    // MARK: Static mappers

    private static func captureDevice(for position: CameraDevicePosition) -> AVCaptureDevice? {
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: avPosition
        )
        return discovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition)
    }

    private static func rotationAngle(for orientation: CameraMountOrientation) -> CGFloat {
        switch orientation {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        }
    }

    private static func interruptionKind(from note: Notification) -> InterruptionReasonKind {
        guard
            let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
            let reason = AVCaptureSession.InterruptionReason(rawValue: raw)
        else { return .unknown }
        switch reason {
        case .videoDeviceNotAvailableInBackground: return .background
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient: return .audioOrVideoDeviceInUse
        case .videoDeviceNotAvailableDueToSystemPressure: return .systemPressure
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return .audioOrVideoDeviceInUse
        default: return .unknown
        }
    }

    private static func thermalLevel(from state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }

    private static func displayOrientation(for mount: CameraMountOrientation) -> VideoFrame.DisplayOrientation {
        switch mount {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        }
    }
}

// MARK: - Sample buffer delegate (videoQueue)

extension CaptureSessionBox: nonisolated AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard pts.isFinite else { return }

        lock.lock()
        let seq = sequence
        sequence += 1
        let discontinuity = pendingDiscontinuity
        pendingDiscontinuity = false
        let metadataSink = self.metadataSink
        let videoSink = self.videoSink
        let recorderAppend = self.recorderAppend
        let fps = self.fps
        let orientation = self.displayOrientation
        lock.unlock()

        let capturedAt = Date()
        let captureFrame = CameraCaptureFrame(
            presentationTime: pts,
            capturedAt: capturedAt,
            sequence: seq,
            isDiscontinuity: discontinuity
        )

        metadataSink?.offer(captureFrame)

        if let videoSink {
            let format = VideoFrame.Format(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
                framesPerSecond: fps
            )
            let videoFrame = VideoFrame(
                pixelBuffer: pixelBuffer,
                presentationTime: pts,
                capturedAt: capturedAt,
                orientation: orientation,
                sequence: seq,
                isDiscontinuity: discontinuity,
                format: format
            )
            videoSink.offer(videoFrame)
        }

        recorderAppend?(captureFrame)
    }
}

// MARK: - Preview container

/// A `UIView` whose backing layer is an `AVCaptureVideoPreviewLayer`, so the
/// preview sizes itself with Auto Layout / SwiftUI. Lives inside
/// `Services/Camera/` so the AVFoundation layer type never leaves the folder.
private final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("PreviewContainerView layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
