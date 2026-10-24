import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The production `ScreenController` (rear-camera spec Requirement 10, design
/// "Service protocols: ScreenController"). It is the **only** type that writes
/// `UIScreen` brightness and toggles the idle timer — every other layer goes
/// through this protocol, which the privacy script enforces
/// (`Services/Screen/` only).
///
/// Responsibilities:
/// - **Brightness** via the active window scene's `UIScreen` (the global
///   `UIScreen.main` accessor is deprecated; capability row 5). Reading and
///   writing `brightness` is a 0...1 fraction, clamped to the valid range.
/// - **Idle timer** routed through `KeepAwake` under the `.ride` reason, so the
///   reason-counting owner (shared with the crash countdown) is preserved: a
///   ride that out-lives a cancelled crash countdown is never allowed to sleep
///   (`KeepAwakeTests`).
/// - **System brightness notifications**: observes
///   `UIScreen.brightnessDidChangeNotification` and forwards the new reading to
///   `onSystemBrightnessChange` on the main actor, so the `RideModeController`
///   can re-apply the minimum (rate-limited) when Auto-Brightness or the rider
///   fights the setting (`ScreenModeStateMachine` row 13, `BrightnessGuard`).
///
/// The controller never *decides* what brightness to set or whether to restore
/// it — that is the pure `ScreenModeStateMachine` / `BrightnessGuard`, driven by
/// the `RideModeController`. This type only performs the writes.
///
/// `@MainActor` (brightness and the idle timer are UIKit main-actor state) and a
/// class because it owns the long-lived notification observer.
@MainActor
final class UIKitScreenController: ScreenController {
    var onSystemBrightnessChange: ((Double) -> Void)?

    /// A process-wide controller for callers that only need the idle-timer
    /// migration (e.g. `ActiveRideView` when ride mode is off), sharing the one
    /// reason-counting `KeepAwake` owner with the crash countdown. The
    /// `RideModeController` is injected its own instance by the composition root.
    static let shared = UIKitScreenController()

    /// The reason-counting idle-timer owner (shared with the crash countdown).
    private let keepAwake: KeepAwake
    /// Whether this controller is currently holding the `.ride` reason, so a
    /// repeated `setIdleTimerDisabled(true)` does not acquire twice and a
    /// release only happens if we actually acquired.
    private var holdingIdleTimer = false

    #if canImport(UIKit)
    /// The brightness-change observer token. `nonisolated(unsafe)` because it is
    /// only written once on the main actor during `init` and read once in the
    /// nonisolated `deinit` after all other references are gone, so there is no
    /// concurrent access to race on.
    private nonisolated(unsafe) var brightnessObserver: NSObjectProtocol?
    #endif

    /// - Parameter keepAwake: the idle-timer owner; defaults to the shared one so
    ///   the crash countdown and ride mode share reason counting.
    init(keepAwake: KeepAwake = .shared) {
        self.keepAwake = keepAwake
        observeSystemBrightness()
    }

    deinit {
        #if canImport(UIKit)
        if let brightnessObserver {
            NotificationCenter.default.removeObserver(brightnessObserver)
        }
        #endif
    }

    // MARK: - ScreenController

    var brightness: Double {
        #if canImport(UIKit)
        guard let screen = activeScreen else { return 1.0 }
        return Self.clamp(Double(screen.brightness))
        #else
        return 1.0
        #endif
    }

    func setBrightness(_ value: Double) {
        #if canImport(UIKit)
        let clamped = Self.clamp(value)
        activeScreen?.brightness = CGFloat(clamped)
        #endif
    }

    func setIdleTimerDisabled(_ disabled: Bool) {
        // Route through the reason-counting owner so this write and the crash
        // countdown's write never fight. Idempotent on our own `.ride` hold.
        if disabled {
            guard !holdingIdleTimer else { return }
            holdingIdleTimer = true
            keepAwake.acquire(.ride)
        } else {
            guard holdingIdleTimer else { return }
            holdingIdleTimer = false
            keepAwake.release(.ride)
        }
    }

    // MARK: - Private

    #if canImport(UIKit)
    /// The active foreground window scene's screen, used to read/write
    /// brightness without the deprecated `UIScreen.main`.
    private var activeScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.screen
    }
    #endif

    private func observeSystemBrightness() {
        #if canImport(UIKit)
        brightnessObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer fires on the main queue; hop to the main actor so the
            // reading and the callback are main-actor isolated.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onSystemBrightnessChange?(self.brightness)
            }
        }
        #endif
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
