import AVFoundation
import CoreVideo
import Foundation
import QuartzCore

/// Demo-only rear feed: plays the bundled road clip (`DemoRearFeed.mp4`) as if it
/// were the rear camera and runs its frames through the **real**
/// `VisionVehicleConsumer`. While the model flags an approaching vehicle, the
/// feed dings: a phone tone plus `onDing` (routed to the alert fan-out, so the
/// watch buzzes too). The dings speed up as the flagged car's box grows, from
/// about 1.4 s apart when it is small to 0.25 s when it fills the frame.
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
    /// 0…1 closeness of the flagged car (0 when nothing is approaching).
    private(set) var proximity: Double = 0
    private(set) var modelState: VisionVehicleConsumer.ModelLoadState = .loading

    @ObservationIgnored private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    @ObservationIgnored private let consumer = VisionVehicleConsumer()
    @ObservationIgnored private let onDing: () -> Void
    @ObservationIgnored private let tone = AudioSessionTonePlayer()
    @ObservationIgnored private var dangerArea: Double = 0
    @ObservationIgnored private var lastApproachAt: Date?
    @ObservationIgnored private var mainAreaHistory: [(Date, Double)] = []
    @ObservationIgnored private var lastDingAt: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var pendingDiscontinuity = true

    init(onDing: @escaping () -> Void) {
        self.onDing = onDing
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
        consumer.onOverlayBoxes = { [weak self] boxes in
            MainActor.assumeIsolated { self?.updateBoxes(boxes) }
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
            MainActor.assumeIsolated {
                self?.pullFrame()
                self?.dingIfDue()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        consumer.stop()
        consumer.onOverlayBoxes = nil
        boxes = []
        proximity = 0
        lastApproachAt = nil
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

    /// Track only the **main** car: the largest vehicle box in the middle of
    /// the lane (centre x in 0.25…0.75, bottom edge in the near half of the
    /// frame). Parked cars at the edges and small cars far back are ignored.
    /// It counts as dangerous when it is close (area ≥ 0.12) or still growing
    /// (≥ 4% over the last ~0.6 s) at a meaningful size (area ≥ 0.03). Only the
    /// main box is highlighted in the alert colour.
    private func updateBoxes(_ boxes: [DetectionOverlayBox]) {
        let now = Date()
        let vehicles: Set<String> = ["car", "truck", "bus", "motorcycle"]
        let main = boxes
            .filter { vehicles.contains($0.label) && $0.confidence >= 0.5 }
            .filter { box in
                let centerX = box.x + box.width / 2
                return (0.25...0.75).contains(centerX) && box.y + box.height > 0.45
            }
            .max { $0.width * $0.height < $1.width * $1.height }

        var dangerous = false
        if let main {
            let area = main.width * main.height
            mainAreaHistory.append((now, area))
            mainAreaHistory.removeAll { now.timeIntervalSince($0.0) > 0.6 }
            let oldest = mainAreaHistory.first?.1 ?? area
            dangerous = area >= 0.12 || (area >= 0.03 && area >= oldest * 1.04)
            if dangerous {
                dangerArea = area
                lastApproachAt = now
            }
        } else {
            mainAreaHistory.removeAll()
        }

        self.boxes = boxes.map { box in
            DetectionOverlayBox(
                id: box.id,
                label: box.label,
                confidence: box.confidence,
                x: box.x,
                y: box.y,
                width: box.width,
                height: box.height,
                isApproaching: dangerous && box.id == main?.id
            )
        }
    }

    /// Ding when the interval for the current closeness has passed. The danger
    /// holds for 1 s after the last approaching frame so dings don't stutter.
    private func dingIfDue() {
        let now = Date()
        guard let lastApproachAt, now.timeIntervalSince(lastApproachAt) < 1.0 else {
            proximity = 0
            return
        }
        // Box area 0.02 (far) → 0, 0.22+ (filling the frame) → 1.
        let closeness = min(max((dangerArea - 0.02) / 0.2, 0), 1)
        proximity = closeness
        let interval = 1.4 - closeness * 1.15
        if let lastDingAt, now.timeIntervalSince(lastDingAt) < interval { return }
        lastDingAt = now
        alertCount += 1
        tone.playCautionTone()
        onDing()
    }
}
