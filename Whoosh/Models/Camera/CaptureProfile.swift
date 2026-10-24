import Foundation

/// A capture configuration the camera service can run (rear-camera spec
/// Requirement 3.2, design "RideCameraTuning" / O-CAM3). Resolution, frame rate,
/// codec, and average bitrate in one value type. The three named profiles are
/// the *(verify)* hypotheses to be measured on the iPhone 14 (task 31).
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct CaptureProfile: Equatable, Codable, Sendable {
    /// A short display name ("Standard", "Efficient", "Reduced").
    let name: String
    /// Frame width in pixels.
    let width: Int
    /// Frame height in pixels.
    let height: Int
    /// Target capture frame rate.
    let framesPerSecond: Int
    /// The video codec (HEVC, H.264 fallback).
    let codec: VideoCodecKind
    /// Target average bitrate in bits per second.
    let averageBitrate: Int

    init(
        name: String,
        width: Int,
        height: Int,
        framesPerSecond: Int,
        codec: VideoCodecKind,
        averageBitrate: Int
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.codec = codec
        self.averageBitrate = averageBitrate
    }

    /// 1080p30 HEVC at ~5 Mbps — the default for demo clarity (O-CAM3).
    static let standard = CaptureProfile(
        name: "Standard",
        width: 1920,
        height: 1080,
        framesPerSecond: 30,
        codec: .hevc,
        averageBitrate: 5_000_000
    )

    /// 720p30 HEVC at ~2.5 Mbps — the default in Low Power Mode.
    static let efficient = CaptureProfile(
        name: "Efficient",
        width: 1280,
        height: 720,
        framesPerSecond: 30,
        codec: .hevc,
        averageBitrate: 2_500_000
    )

    /// 720p15 HEVC at ~1.2 Mbps — the thermal/battery step.
    static let reduced = CaptureProfile(
        name: "Reduced",
        width: 1280,
        height: 720,
        framesPerSecond: 15,
        codec: .hevc,
        averageBitrate: 1_200_000
    )
}
