import Foundation
import WhooshWire

/// The haptic actuator seam (watch-companion design "Haptic playing"). The
/// model selects a `HapticPattern` (pure, in `WhooshWire`) and asks the player
/// to play it; `isActive` reflects whether the app can actually buzz right now
/// (foreground or a running workout session). Keeping this a protocol means the
/// model never imports WatchKit — the only `WKInterfaceDevice.play` caller is
/// `WhooshWatch/Services/Haptics/WKHapticPlayer.swift`.
public protocol HapticPlaying: AnyObject, Sendable {
    /// Whether the watch can play a haptic now (app active or a workout running).
    /// When false the limiter reports `suppressedNotActive` and nothing plays.
    var isActive: Bool { get }

    /// Play a pattern. Implementations run the steps in one cancellable serial
    /// task so a later, higher-tier pattern can preempt an in-progress one.
    func play(_ pattern: HapticPattern)

    /// Cancel any in-progress pattern (used when a higher tier preempts).
    func cancel()
}

/// An in-memory `HapticPlaying` for previews and tests: records what it was
/// asked to play and lets a test flip `isActive`. Plays nothing.
public final class FakeHapticPlayer: HapticPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var _isActive: Bool
    public private(set) var played: [HapticPattern] = []
    public private(set) var cancelCount = 0

    public init(isActive: Bool = true) {
        self._isActive = isActive
    }

    public var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isActive
    }

    public func setActive(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        _isActive = value
    }

    public func play(_ pattern: HapticPattern) {
        lock.lock(); defer { lock.unlock() }
        played.append(pattern)
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelCount += 1
    }

    /// The name of the most recently played pattern, if any.
    public var lastPlayedName: String? {
        lock.lock(); defer { lock.unlock() }
        return played.last?.name
    }
}
