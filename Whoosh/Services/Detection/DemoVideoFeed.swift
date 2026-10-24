import AVFoundation
import CoreVideo
import Foundation
import QuartzCore

/// Demo-only rear feed: plays the bundled road clip (`DemoRearFeed.mp4`) as if it
/// were the rear camera and runs its frames through the **real**
/// `VisionVehicleConsumer`. When the model flags an approaching vehicle,
/// `onVehicle` fires, which the demo controller routes to the normal alert
/// fan-out (phone cue + watch), exactly as a live detection would during a ride.
///
/// Frames are pulled from an `AVPlayerItemVideoOutput` at ~10 Hz (the consumer's
/// own cap) and one inference runs at a time; a frame that arrives while the
/// model is busy is skipped. The clip loops; the first frame after a loop is
/// marked as a discontinuity so the approach estimator resets.
///
/// Nothing is recorded or uploaded: the clip is a bundled asset, and no
/// `HazardDetection` is persisted. Experimental cue — cannot guarantee detection
/// or delivery.
@MainActor
@Observable
final class DemoVideoFeed {
    let player: AVPlayer?
    /// The clip's display size, for laying out the overlay over the video.
    let videoSize = CGSize(width: 1280, height: 592)
    private(set) var boxes: [DetectionOverlayBox] = []
    private(set) var alertCount = 0
    private(set) var modelState: VisionVehicleConsumer.ModelLoadState = .loading

    @ObservationIgnored private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    @ObservationIgnored private let consumer = VisionVehicleConsumer()
    @ObservationIgnored private let onVehicle: () -> Void
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var pendingDiscontinuity = true

    init(onVehicle: @escaping () -> Void) {
        self.onVehicle = onVehicle
        if let url = Bundle.main.url(forResource: "DemoRearFeed", withExtension: "mp4") {
            let item = AVPlayerItem(url: url)
            item.add(output)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            self.player = player
        } else {
            self.player = nil
        }
    }

    func start() {
        guard let player, timer == nil else { return }
        consumer.onDetection = { [weak self] _ in
            MainActor.assumeIsolated { self?.vehicleDetected() }
        }
        consumer.onOverlayBoxes = { [weak self] boxes in
            MainActor.assumeIsolated { self?.boxes = boxes }
        }
        consumer.onModelStateChange = { [weak self] state in
            Task { @MainActor in self?.modelState = state }
        }
        consumer.start()

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pendingDiscontinuity = true
                self?.player?.seek(to: .zero)
                self?.player?.play()
            }
        }
        player.play()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFrame() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        consumer.stop()
        consumer.onDetection = nil
        consumer.onOverlayBoxes = nil
        boxes = []
    }

    private func pullFrame() {
        guard !busy else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        else { return }

        sequence += 1
        let frame = VideoFrame(
            pixelBuffer: buffer,
            presentationTime: time.seconds,
            capturedAt: Date(),
            orientation: .up,
            sequence: sequence,
            isDiscontinuity: pendingDiscontinuity,
            format: .init(
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer),
                pixelFormat: CVPixelBufferGetPixelFormatType(buffer),
                framesPerSecond: 10
            )
        )
        pendingDiscontinuity = false
        busy = true
        let consumer = self.consumer
        Task {
            await consumer.consume(frame)
            self.busy = false
        }
    }

    private func vehicleDetected() {
        alertCount += 1
        onVehicle()
    }
}
