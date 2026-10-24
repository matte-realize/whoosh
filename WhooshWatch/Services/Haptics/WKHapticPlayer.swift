import Foundation
import WatchKit
import WhooshWire

/// The one and only watch file that calls `WKInterfaceDevice.play` (enforced by
/// `scripts/privacy-check.sh`, rule 21). It is the haptic actuator behind the
/// `HapticPlaying` seam (watch-companion design "Haptic playing"; task 19).
///
/// - It maps each pure `HapticCue` (from `WhooshWire`, Foundation-only) to a
///   system `WKHapticType`.
/// - It plays a `HapticPattern`'s steps in **one cancellable serial task** so a
///   later, higher-tier pattern can preempt one already playing (`cancel()`),
///   and so overlapping requests never interleave on the Taptic engine.
/// - It plays only when the app can actually buzz (`isActive`: foreground or a
///   running workout session). When not active, callers (the limiter) report
///   `suppressedNotActive` and nothing plays.
///
/// Honest framing: haptics are a cue, not a guarantee — a watch may be on a
/// locked screen, muted, or low on battery; Whoosh cannot guarantee detection
/// or delivery.
@MainActor
public final class WKHapticPlayer: HapticPlaying {
    private var playTask: Task<Void, Never>?
    private let device = WKInterfaceDevice.current()

    /// Whether a workout session is keeping the app alive. The workout
    /// controller sets this; a running session lets the watch buzz with the
    /// wrist down even when the display is off.
    public var workoutActive = false

    public init() {}

    /// The app can buzz when it is foreground-active or a workout session is
    /// keeping it alive.
    public nonisolated var isActive: Bool {
        MainActor.assumeIsolated {
            if workoutActive { return true }
            return WKApplication.shared().applicationState == .active
        }
    }

    public func play(_ pattern: HapticPattern) {
        // Preempt anything in progress; start a fresh serial task.
        playTask?.cancel()
        let steps = pattern.steps
        playTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for (index, step) in steps.enumerated() {
                if Task.isCancelled { return }
                self.device.play(Self.hapticType(for: step.cue))
                // Wait the gap before the next cue (the last step's gap is
                // ignored). The platform enforces ~100 ms between cues; the
                // catalog authors gaps ≥ 100 ms.
                if index < steps.count - 1, step.gapMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(step.gapMs) * 1_000_000)
                }
            }
        }
    }

    public func cancel() {
        playTask?.cancel()
        playTask = nil
    }

    /// Map a pure cue to a system haptic type (the only place this mapping
    /// exists; the package never names `WKHapticType`).
    static func hapticType(for cue: HapticCue) -> WKHapticType {
        switch cue {
        case .notification: return .notification
        case .directionUp: return .directionUp
        case .directionDown: return .directionDown
        case .success: return .success
        case .failure: return .failure
        case .retry: return .retry
        case .start: return .start
        case .stop: return .stop
        case .click: return .click
        }
    }
}
