import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage:
//   whoosh-film <engine.js> <out-base>                 renders the whole film
//   whoosh-film <engine.js> <out-dir> --stills 3,8.5   renders PNG stills at those times

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: whoosh-film <engine.js> <out-base> [--stills t1,t2,...] [--from s --to s]")
    exit(64)
}
let engineURL = URL(fileURLWithPath: args[1])
let outBase = args[2]
var stills: [Double]?
var startAt = 0.0
var endAt = Film.duration
var i = 3
while i < args.count {
    switch args[i] {
    case "--stills": stills = args[i + 1].split(separator: ",").compactMap { Double($0) }; i += 2
    case "--from": startAt = Double(args[i + 1]) ?? 0; i += 2
    case "--to": endAt = Double(args[i + 1]) ?? Film.duration; i += 2
    default: i += 1
    }
}

let engine = try Engine(engineFile: engineURL)
let film = FilmRenderer(engine: engine)
let fps = Double(Film.fps)
let frames = Int((Film.duration * fps).rounded())
let started = Date()

func savePNG(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

if let stills {
    try FileManager.default.createDirectory(atPath: outBase, withIntermediateDirectories: true)
    let wanted = Set(stills.map { Int(($0 * fps).rounded()) })
    let last = wanted.max() ?? 0
    for f in 0...last {
        let t = Double(f) / fps
        if let img = film.render(t, draw: wanted.contains(f)) {
            let name = String(format: "%@/still-%06.2f.png", outBase, t)
            savePNG(img, name)
            print("still", name)
        }
    }
    exit(0)
}

// Prefer ffmpeg (libx264), then the system H.264 encoder.
enum Output {
    case ffmpeg(FFmpegWriter)
    case h264(VideoWriter)
}
let output: Output
let outputPath: String
if let ff = findFFmpeg(), let w = try? FFmpegWriter(ffmpeg: ff, url: URL(fileURLWithPath: outBase + ".mp4"), width: Int(Film.width), height: Int(Film.height), fps: Film.fps) {
    output = .ffmpeg(w)
    outputPath = outBase + ".mp4"
} else if let w = try? VideoWriter(url: URL(fileURLWithPath: outBase + ".mp4"), width: Int(Film.width), height: Int(Film.height), fps: Int32(Film.fps), bitsPerSecond: 16_000_000) {
    output = .h264(w)
    outputPath = outBase + ".mp4"
} else {
    print("No H.264 encoder: install ffmpeg (brew install ffmpeg) and run again.")
    exit(1)
}

let first = Int((startAt * fps).rounded())
let lastFrame = min(frames, Int((endAt * fps).rounded()))
for f in 0..<lastFrame {
    let t = Double(f) / fps
    let draw = f >= first
    guard let img = film.render(t, draw: draw) else { continue }
    switch output {
    case .ffmpeg(let w): w.append(img)
    case .h264(let w): w.append(img)
    }
    if f % 60 == 0 {
        let el = Date().timeIntervalSince(started)
        print(String(format: "frame %d/%d  t=%.1fs  elapsed %.0fs", f, lastFrame, t, el))
    }
}
switch output {
case .ffmpeg(let w): if !w.finish() { print("ffmpeg failed"); exit(1) }
case .h264(let w): w.finish()
}
print("wrote", outputPath, String(format: "in %.0fs", Date().timeIntervalSince(started)))
