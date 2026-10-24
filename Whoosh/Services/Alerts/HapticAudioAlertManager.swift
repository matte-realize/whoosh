import Foundation
import AVFoundation
import CoreHaptics
import UIKit

/// A real `AlertManager` that raises an **experimental** rear-vehicle cue using
/// a short haptic pattern plus a brief distinct tone. It is a cue to help a
/// rider notice something behind them; it is not a reliable detector and cannot
/// guarantee detection or delivery of anything.
///
/// Design (see demo-mode design "The real alert manager"):
/// - **Haptics:** a short Core Haptics transient pattern when supported, with a
///   `UINotificationFeedbackGenerator` (`.warning`) fallback on devices without
///   Core Haptics. The engine/generator is prepared ahead to cut latency.
/// - **Audio:** a short tone played with the `.playback` category and ducking so
///   it is audible over other audio and is not silenced by the ring/silent
///   switch; the session is activated only for the tone and released afterward.
/// - **Debounce:** repeated fires inside a short window collapse to one cue via
///   the pure `AlertCooldown` rule, consulted through the injected `Clock`.
///
/// Contract (from `AlertManager`): `fire(_:)` returns immediately, never blocks
/// or slows ride recording, and degrades silently if haptics or audio are
/// unavailable. All `AVAudioSession` use in the app outside the crash feedback
/// lives here, which the privacy layering allows for `Services/Alerts/`. It
/// touches no network and no camera.
final class HapticAudioAlertManager: AlertManager {
    private let clock: Clock
    private let cooldown: TimeInterval
    private var lastFiredAt: Date?

    private let haptics: HapticPlaying
    private let tone: TonePlaying

    /// - Parameters:
    ///   - clock: time source for the debounce window (injected so tests and
    ///     the app share one seam).
    ///   - cooldown: minimum gap between surfaced cues (default from `AlertCooldown`).
    init(
        clock: Clock,
        cooldown: TimeInterval = AlertCooldown.defaultCooldownSeconds,
        haptics: HapticPlaying? = nil,
        tone: TonePlaying? = nil
    ) {
        self.clock = clock
        self.cooldown = cooldown
        self.haptics = haptics ?? CoreHapticsPlayer()
        self.tone = tone ?? AudioSessionTonePlayer()
        // Prepare ahead so the first real cue isn't delayed by warm-up.
        self.haptics.prepare()
    }

    /// Fire an experimental cue. Returns immediately; debounced so a burst of
    /// fires inside the cooldown window surfaces at most one cue. Any haptic or
    /// audio failure is swallowed so recording is never affected.
    func fire(_ kind: AlertKind) {
        switch kind {
        case .cautionRearVehicle:
            break
        case .cameraInterrupted, .cameraResumed, .cameraStopped, .clipSaved, .clipNotSaved, .phoneBatteryLow:
            // Camera status notices go to the eyes-free surfaces (rear-camera
            // AlertSink fan-out). A rear-mounted phone buzzing helps no one, and
            // a notice must not use up the rear-vehicle cooldown.
            return
        }

        let now = clock.now()
        guard AlertCooldown.shouldFire(lastFiredAt: lastFiredAt, now: now, cooldown: cooldown) else {
            return
        }
        lastFiredAt = now
        haptics.playCaution()
        tone.playCautionTone()
    }
}

// MARK: - Haptics

/// Abstraction over the haptic layer so the manager can be unit-tested with a
/// recording fake and so the Core Haptics / fallback choice is isolated.
protocol HapticPlaying {
    /// Warm up the haptic engine/generator to reduce first-fire latency.
    func prepare()
    /// Play the short cautionary haptic (transient pattern or fallback).
    func playCaution()
}

/// Core Haptics implementation with a `UINotificationFeedbackGenerator` fallback.
///
/// Fails silently: if Core Haptics is unsupported or the engine can't start, it
/// falls back to the notification generator; if that is unavailable too, it does
/// nothing. Never throws out of `playCaution()`.
final class CoreHapticsPlayer: HapticPlaying {
    private var engine: CHHapticEngine?
    private let supportsHaptics: Bool
    private let fallback = UINotificationFeedbackGenerator()

    init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func prepare() {
        fallback.prepare()
        guard supportsHaptics, engine == nil else { return }
        engine = try? makeEngine()
    }

    func playCaution() {
        if supportsHaptics, playCoreHaptics() {
            return
        }
        // Fallback: a single warning notification haptic.
        fallback.notificationOccurred(.warning)
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        // Restart quietly if the engine is reset or stopped by the system.
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        engine.stoppedHandler = { _ in }
        try engine.start()
        return engine
    }

    /// Plays a two-tap transient pattern. Returns `false` if it could not play,
    /// so the caller can fall back.
    private func playCoreHaptics() -> Bool {
        if engine == nil { engine = try? makeEngine() }
        guard let engine else { return false }
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ],
                relativeTime: 0.12
            ),
        ]
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Tone

/// Abstraction over the short-tone layer so the manager can be unit-tested with
/// a recording fake and so all `AVAudioSession` use stays behind this seam.
protocol TonePlaying {
    /// Play the short cautionary tone. Must return quickly and fail silently.
    func playCautionTone()
}

/// Plays a short distinct tone through an `AVAudioSession` configured for
/// `.playback` with ducking, then releases the session.
///
/// The tone is a brief synthesized beep generated once into a temporary WAV so
/// no audio asset needs to ship. Session activation, playback, and deactivation
/// run on a background queue so `fire(_:)` never blocks the ride loop. Every
/// step fails silently.
nonisolated final class AudioSessionTonePlayer: NSObject, TonePlaying, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.whoosh.alerts.tone", qos: .userInitiated)
    /// Retains the player for the life of the (short) playback. Only ever
    /// touched on `queue`, so the `@unchecked Sendable` marking is sound.
    private var player: AVAudioPlayer?
    private let toneURL: URL?

    override init() {
        toneURL = Self.makeToneFileIfNeeded()
        super.init()
    }

    func playCautionTone() {
        guard let toneURL else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let session = AVAudioSession.sharedInstance()
            do {
                // `.playback` so the silent switch doesn't mute the cue; duck
                // others so it's audible over music/navigation.
                try session.setCategory(.playback, options: [.duckOthers])
                try session.setActive(true)
            } catch {
                return
            }
            do {
                let player = try AVAudioPlayer(contentsOf: toneURL)
                player.delegate = self
                player.prepareToPlay()
                self.player = player
                player.play()
            } catch {
                // Couldn't play: release the session we just activated.
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            }
        }
    }

    /// Writes a short synthesized beep to a temporary WAV once; returns its URL.
    /// Returns `nil` on any failure (the manager then simply skips the tone).
    private static func makeToneFileIfNeeded() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-rear-cue.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate = 44_100.0
        let durationSeconds = 0.18
        let frequency = 880.0 // a short, distinct A5 beep
        let frameCount = Int(sampleRate * durationSeconds)

        var samples = [Int16]()
        samples.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            // Short linear fade in/out so the beep doesn't click.
            let fade = min(1.0, min(Double(frame), Double(frameCount - frame)) / (sampleRate * 0.01))
            let amplitude = 0.6 * fade
            let value = sin(2.0 * Double.pi * frequency * t) * amplitude
            samples.append(Int16(max(-1.0, min(1.0, value)) * Double(Int16.max)))
        }

        guard let data = wavData(samples: samples, sampleRate: Int(sampleRate)) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Wraps 16-bit mono PCM samples in a minimal WAV container.
    private static func wavData(samples: [Int16], sampleRate: Int) -> Data? {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data()
        func appendString(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendUInt32LE(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16LE(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendString("RIFF")
        appendUInt32LE(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32LE(16)
        appendUInt16LE(1) // PCM
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(UInt32(byteRate))
        appendUInt16LE(UInt16(blockAlign))
        appendUInt16LE(UInt16(bitsPerSample))
        appendString("data")
        appendUInt32LE(UInt32(dataSize))
        for sample in samples {
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}

extension AudioSessionTonePlayer: nonisolated AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Release the session once the short tone finishes so we don't hold the
        // audio route or keep other audio ducked.
        queue.async {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
