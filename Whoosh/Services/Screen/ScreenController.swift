import Foundation

/// Abstracts the screen brightness and idle-timer controls so the ride-mode
/// controller and tests never touch UIKit (rear-camera spec Requirement 10,
/// design "Service protocols: ScreenController"). `UIKitScreenController`
/// (task 21) is the only concrete type that writes `UIScreen` brightness and
/// `isIdleTimerDisabled`; `FakeScreenController` scripts the readings and the
/// system-brightness-change callback for tests and previews.
///
/// ## Contract (non-negotiable; see privacy steering and the design)
/// - **Restore on every exit.** Ride mode dims the screen to minimum; the
///   controller records the original brightness and the `ScreenModeStateMachine`
///   / `BrightnessGuard` restore it on unlock, ride end, resign-active, and the
///   next launch (persisted guard). The rider's phone is never left dim.
/// - **Honest, no hiding.** Dimming saves power; the red recording dot stays
///   visible and system camera/location indicators are never hidden or imitated.
/// - **Main actor.** Brightness and the idle timer are UIKit main-actor state;
///   `onSystemBrightnessChange` is delivered on the main actor so the reducer can
///   re-apply the minimum (rate-limited) when Auto-Brightness fights the setting.
///
/// `AnyObject` because a concrete controller is a long-lived reference type
/// owning the UIKit observers. `brightness` is a 0...1 fraction.
@MainActor
protocol ScreenController: AnyObject {
    /// The current screen brightness (0...1).
    var brightness: Double { get }

    /// Invoked when the system changes brightness externally (Auto-Brightness or
    /// the rider), so the reducer can decide whether to re-apply the minimum.
    var onSystemBrightnessChange: ((Double) -> Void)? { get set }

    /// Set the screen brightness (0...1), clamped to the valid range.
    func setBrightness(_ value: Double)

    /// Keep the screen awake (disable the idle timer) while ride mode is active,
    /// and restore the default when it ends.
    func setIdleTimerDisabled(_ disabled: Bool)
}
