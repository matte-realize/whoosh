import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Writes frames drawn into a CGContext to an H.264 .mp4 with AVAssetWriter.
final class VideoWriter {
    let width: Int
    let height: Int
    let fps: Int32
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var frameIndex: Int64 = 0

    init(url: URL, width: Int, height: Int, fps: Int32, bitsPerSecond: Int) throws {
        self.width = width
        self.height = height
        self.fps = fps
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: Int(fps),
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "VideoWriter", code: 1) }
        writer.startSession(atSourceTime: .zero)
    }

    /// Appends a rendered frame.
    func append(_ image: CGImage) {
        append(flipped: false) { ctx in ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
    }

    /// Appends one frame. With `flipped`, `draw` gets a context with the origin at the top-left.
    func append(flipped: Bool = true, _ draw: (CGContext) -> Void) {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard let pb = buffer else { fatalError("no pixel buffer: \(String(describing: writer.error))") }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        if flipped {
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
        }
        draw(ctx)
        CVPixelBufferUnlockBaseAddress(pb, [])
        if !adaptor.append(pb, withPresentationTime: CMTime(value: frameIndex, timescale: fps)) {
            fatalError("append failed: \(String(describing: writer.error))")
        }
        frameIndex += 1
    }

    func finish() {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { print("writer error:", String(describing: writer.error)) }
    }
}
