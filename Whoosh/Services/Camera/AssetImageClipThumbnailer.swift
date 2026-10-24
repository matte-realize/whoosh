import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// `ClipThumbnailing` backed by `AVAssetImageGenerator` (rear-camera spec task
/// 16; Requirement 8.1). The only thumbnail generator; lives in
/// `Services/Camera/` where AVFoundation is allowed.
///
/// Builds an `AVComposition` from the clip's ordered segment files (so a
/// multi-segment clip still yields one image), copies a single frame near the
/// event instant, encodes it as JPEG, and writes it beside the clip's footage.
/// Any failure returns `nil` — a missing thumbnail never blocks saving a clip.
///
/// The real AVFoundation behaviour (decode of HEVC segments, exact frame timing)
/// is a device check (task 31); the logic that selects the source files and the
/// output path is covered by the pinner tests through the fake.
struct AssetImageClipThumbnailer: ClipThumbnailing {
    /// Target thumbnail width in pixels (height follows the aspect ratio).
    let maxPixelWidth: CGFloat
    private static let logger = Logger(subsystem: "com.whoosh.app", category: "ClipThumbnailer")

    init(maxPixelWidth: CGFloat = 320) {
        self.maxPixelWidth = maxPixelWidth
    }

    func generateThumbnail(
        sourceURLs: [URL],
        atOffset: TimeInterval,
        destinationURL: URL
    ) async -> URL? {
        guard !sourceURLs.isEmpty else { return nil }

        // Stitch the segment files into one composition so the requested offset
        // addresses the clip's own timeline.
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        var cursor = CMTime.zero
        for url in sourceURLs {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { continue }
                let range = CMTimeRange(start: .zero, duration: duration)
                try videoTrack.insertTimeRange(range, of: track, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
            } catch {
                Self.logger.error("Thumbnail: failed to read a segment; skipping it")
                continue
            }
        }

        guard cursor > .zero else { return nil }

        let generator = AVAssetImageGenerator(asset: composition)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelWidth, height: 0)
        // Tolerate a small seek error so a keyframe near the instant is used.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let clamped = max(0, min(atOffset, CMTimeGetSeconds(cursor)))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)

        do {
            let cgImage = try await generator.image(at: time).image
            return writeJPEG(cgImage, to: destinationURL)
        } catch {
            Self.logger.error("Thumbnail: image generation failed")
            return nil
        }
    }

    // MARK: - Private

    private func writeJPEG(_ cgImage: CGImage, to destinationURL: URL) -> URL? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try (data as Data).write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            Self.logger.error("Thumbnail: failed to write JPEG")
            return nil
        }
    }
}
