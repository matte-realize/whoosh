import Foundation

/// Scriptable `ScreenController` for tests and SwiftUI previews: brightness is a
/// stored 0...1 value and the system-change callback is driven on demand, so the
/// ride-mode reducer and the brightness guard (tasks 8/21) can be exercised
/// without UIKit.
///
/// Lives under `Services/Screen/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Scripting:
/// - `setBrightness(_:)` updates `brightness` (clamped) and records the history.
/// - `setIdleTimerDisabled(_:)` records the latest value.
/// - `simulateSystemBrightnessChange(_:)` models Auto-Brightness / the rider
///   moving the slider: it updates `brightness` and fires `onSystemBrightnessChange`.
/// Callbacks fire synchronously on the main actor so expectations are
/// deterministic.
@MainActor
final class FakeScreenController: ScreenController {
    private(set) var brightness: Double

    var onSystemBrightnessChange: ((Double) -> Void)?

    // MARK: Recorded interactions (for test assertions)

    /// Every value passed to `setBrightness`, in order.
    private(set) var setBrightnessHistory: [Double] = []
    /// The most recent `setIdleTimerDisabled` value, or `nil` if never called.
    private(set) var idleTimerDisabled: Bool?
    /// Number of `setIdleTimerDisabled` calls.
    private(set) var setIdleTimerCount = 0

    init(brightness: Double = 0.5) {
        self.brightness = Self.clamp(brightness)
    }

    // MARK: ScreenController

    func setBrightness(_ value: Double) {
        let clamped = Self.clamp(value)
        brightness = clamped
        setBrightnessHistory.append(clamped)
    }

    func setIdleTimerDisabled(_ disabled: Bool) {
        idleTimerDisabled = disabled
        setIdleTimerCount += 1
    }

    // MARK: Scripting API (test/preview driven)

    /// Model a system-driven brightness change (Auto-Brightness or the rider):
    /// updates `brightness` and notifies through `onSystemBrightnessChange`. Does
    /// not append to `setBrightnessHistory` (that tracks our own writes).
    func simulateSystemBrightnessChange(_ value: Double) {
        let clamped = Self.clamp(value)
        brightness = clamped
        onSystemBrightnessChange?(clamped)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
