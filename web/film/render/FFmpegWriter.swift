import CoreGraphics
import Foundation

/// Pipes raw BGRA frames into ffmpeg (libx264), which writes the .mp4.
final class FFmpegWriter {
    private let process = Process()
    private let pipe = Pipe()
    private let width: Int
    private let height: Int

    init(ffmpeg: String, url: URL, width: Int, height: Int, fps: Int) throws {
        self.width = width
        self.height = height
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(width)x\(height)", "-r", "\(fps)", "-i", "-",
            "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
            "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
            "-movflags", "+faststart", url.path,
        ]
        process.standardInput = pipe
        try process.run()
    }

    func append(_ image: CGImage) {
        // Redraw into a tightly packed BGRA buffer, the layout ffmpeg was told to expect.
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        pipe.fileHandleForWriting.write(data)
    }

    func finish() -> Bool {
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

func findFFmpeg() -> String? {
    for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] where FileManager.default.isExecutableFile(atPath: p) {
        return p
    }
    return nil
}
