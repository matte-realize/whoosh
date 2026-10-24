import Foundation
import Observation

/// Drives the compact pre-ride "Connect your watch" step shown before Mount &
/// frame when an Apple Watch is paired (owner request: "there should be a screen
/// to connect it to the watch first"; watch-companion Requirement 1.8, 3.3).
///
/// It is **skippable** and remembers "Don't show this again" in `UserDefaults`,
/// so it never gets in the way of a rider who doesn't use the watch. It is only
/// ever presented when a watch is paired (the composition root checks
/// `shouldPresent` first); with no watch the ride flow is unchanged.
///
/// UI-framework-free; the `UserDefaults` suite is injectable for tests.
@MainActor
@Observable
final class WatchConnectStepViewModel {
    /// Stable key for the persisted "don't show again" choice.
    static let suppressDefaultsKey = "whoosh.watch.connectStep.suppressed"

    @ObservationIgnored private let connection: WatchConnectionProviding
    @ObservationIgnored private let defaults: UserDefaults

    private(set) var isSending = false
    private(set) var lastSendMessage: String?
    /// Bound to the "Don't show this again" toggle in the view.
    var dontShowAgain = false

    init(connection: WatchConnectionProviding, defaults: UserDefaults = .standard) {
        self.connection = connection
        self.defaults = defaults
    }

    // MARK: - Presentation decision

    /// Whether this step should be shown before a ride: only when a watch is
    /// paired and the rider hasn't suppressed it. The composition root calls the
    /// static form before building the view model.
    static func shouldPresent(
        connection: WatchConnectionProviding,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard connection.isPaired else { return false }
        return !defaults.bool(forKey: suppressDefaultsKey)
    }

    // MARK: - Facts (for the compact status line)

    var isWatchAppInstalled: Bool { connection.isWatchAppInstalled }
    var isReachable: Bool { connection.isReachable }

    /// The compact status: connected when installed + reachable, otherwise a
    /// short reason the rider can act on.
    var statusTitle: String {
        if !isWatchAppInstalled { return "Watch app not installed" }
        return isReachable ? "Watch connected" : "Watch not reachable" }

    var statusDetail: String {
        if !isWatchAppInstalled {
            return "Install the Whoosh watch app to feel ride cues on your wrist. You can ride without it."
        }
        return isReachable
            ? "Your watch will show the ride and buzz for cues. A buzz is a cue, not a guarantee."
            : "Open Whoosh on your watch and keep it nearby. Whoosh falls back to audio cues on your phone."
    }

    var isConnected: Bool { isWatchAppInstalled && isReachable }

    func onAppear() {
        connection.refresh()
        Task { await connection.activate() }
    }

    // MARK: - Intents

    func testBuzz() async {
        guard !isSending else { return }
        isSending = true
        lastSendMessage = nil
        let ok = await connection.sendTestBuzz()
        isSending = false
        lastSendMessage = ok
            ? "Sent to your watch — did you feel it?"
            : "Couldn't reach your watch. Open Whoosh on the watch and keep it nearby."
    }

    /// Persist the "don't show again" choice. Call when the step is dismissed by
    /// either Continue or Skip.
    func persistSuppressionChoice() {
        defaults.set(dontShowAgain, forKey: Self.suppressDefaultsKey)
    }
}
