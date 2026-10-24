import Foundation

/// Pure profile selector for the camera subsystem (rear-camera spec Requirement
/// 3.2 and 12, design "CaptureProfileSelector"). Resolves the profile actually
/// used from the requested profile intersected with the device's supported
/// formats and the thermal/battery adjustments, falling back to the nearest
/// supported profile and never failing the ride.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The caller
/// supplies the list of `CaptureProfile`s the device format list can satisfy
/// (resolved in `Services/Camera/` from the capture device's formats); this type
/// never touches AVFoundation.
///
/// ## Rules (design table)
/// - requested ∩ supported ∩ thermal step ∩ battery/LPM ⇒ the profile used.
/// - A requested profile the device cannot satisfy falls back to the nearest
///   supported profile (by pixel count, then frame rate), never failing.
/// - Thermal `.fps24`/`.fps15` lower the frame rate of the chosen profile;
///   `.resolutionReduced` selects the Reduced-class profile.
/// - Battery/LPM `.useEfficient` biases the request to Efficient; `.stop` ⇒
///   `.unavailable`.
/// - If no profile is supported at all ⇒ `.unavailable`.
enum CaptureProfileSelector {
    /// The result of selection.
    enum Selection: Equatable, Sendable {
        /// The profile the camera should run.
        case use(CaptureProfile)
        /// No profile can be satisfied; the camera cannot start/continue.
        case unavailable
    }

    /// The inputs to selection.
    struct Input: Equatable, Sendable {
        /// The profile the rider/coordinator asked for (e.g. `.standard`).
        let requested: CaptureProfile
        /// The profiles the device's format list can actually satisfy. If empty,
        /// the result is `.unavailable`.
        let supported: [CaptureProfile]
        /// The thermal quality step currently in effect.
        let thermalStep: ThermalPolicy.Step
        /// The battery recommendation currently in effect.
        let battery: BatteryPolicy.Recommendation

        init(
            requested: CaptureProfile,
            supported: [CaptureProfile],
            thermalStep: ThermalPolicy.Step = .full,
            battery: BatteryPolicy.Recommendation = .keep
        ) {
            self.requested = requested
            self.supported = supported
            self.thermalStep = thermalStep
            self.battery = battery
        }
    }

    /// Select the profile to use.
    static func select(_ input: Input) -> Selection {
        // Battery stop wins outright.
        if input.battery == .stop {
            return .unavailable
        }
        guard !input.supported.isEmpty else {
            return .unavailable
        }

        // 1. Bias the request by battery/LPM: Efficient instead of Standard.
        var target = input.requested
        if input.battery == .useEfficient, target.pixelCount > CaptureProfile.efficient.pixelCount {
            target = CaptureProfile.efficient
        }

        // 2. Apply the thermal step: resolution-reduced forces the Reduced class;
        //    the fps steps lower the frame rate.
        switch input.thermalStep {
        case .full:
            break
        case .fps24:
            target = target.withFrameRate(min(target.framesPerSecond, 24))
        case .fps15:
            target = target.withFrameRate(min(target.framesPerSecond, 15))
        case .resolutionReduced:
            // Prefer the smaller of the current target and the Reduced profile.
            if target.pixelCount > CaptureProfile.reduced.pixelCount {
                target = CaptureProfile.reduced
            } else {
                target = target.withFrameRate(min(target.framesPerSecond, CaptureProfile.reduced.framesPerSecond))
            }
        }

        // 3. Resolve against the supported list: exact match, else nearest.
        if input.supported.contains(where: { $0.matchesCapability(target) }) {
            // Use the target (carrying its adjusted fps/bitrate); the device
            // supports that resolution+codec, and fps is applied on top.
            return .use(target)
        }
        return .use(nearest(to: target, in: input.supported))
    }

    /// The nearest supported profile to `target` by pixel count, then by frame
    /// rate (closest wins; ties prefer the lower, calmer option).
    private static func nearest(to target: CaptureProfile, in supported: [CaptureProfile]) -> CaptureProfile {
        supported.min(by: { a, b in
            let da = abs(a.pixelCount - target.pixelCount)
            let db = abs(b.pixelCount - target.pixelCount)
            if da != db { return da < db }
            let fa = abs(a.framesPerSecond - target.framesPerSecond)
            let fb = abs(b.framesPerSecond - target.framesPerSecond)
            if fa != fb { return fa < fb }
            return a.pixelCount < b.pixelCount
        }) ?? target
    }
}

extension CaptureProfile {
    /// Total pixels per frame (width × height), used to compare profile "size".
    var pixelCount: Int { width * height }

    /// A copy of this profile with a different frame rate (bitrate unchanged;
    /// the recorder caps bitrate to what the profile declares).
    func withFrameRate(_ fps: Int) -> CaptureProfile {
        CaptureProfile(
            name: name,
            width: width,
            height: height,
            framesPerSecond: fps,
            codec: codec,
            averageBitrate: averageBitrate
        )
    }

    /// Whether this (device-supported) profile can satisfy `other`'s resolution
    /// and codec. Frame rate is applied on top, so it is not compared here.
    func matchesCapability(_ other: CaptureProfile) -> Bool {
        width == other.width && height == other.height && codec == other.codec
    }
}
