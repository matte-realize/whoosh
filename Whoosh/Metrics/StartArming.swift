import Foundation
import WhooshWire

/// The pure "arm the phone so the rider can start a ride from the wrist" state
/// machine (watch-companion task 7, design "`StartArming`"; Requirement 9.1–9.3).
///
/// Starting a ride is the one wrist action that creates state, so it is gated:
/// the rider taps **Ready to ride** on the phone (never the watch), which arms a
/// short window (default 5 min, range 1–15); while armed, a wrist `requestStart`
/// is accepted and the phone runs the normal start path with `startedFromWatch`.
/// The window disarms on expiry, the phone resigning active, a crash event, or
/// loss of location authorization — so an armed phone left in a pocket never
/// starts a ride by itself (Requirement 9.2). A watch can never arm.
///
/// A value-type machine: `apply(_:at:)` returns the next machine and the
/// `Effect` to run. `now` is passed in (matching the other `Metrics/`
/// policies); the armed deadline is absolute so expiry is a pure comparison.
/// Framework-free (Models + `WhooshWire` + Foundation).
struct StartArming: Equatable, Sendable {
    // MARK: - State

    enum State: Equatable, Sendable {
        /// Not armed; a wrist start is rejected `notArmed`.
        case disarmed
        /// Armed until the absolute `deadline`; a wrist start is accepted.
        case armed(deadline: Date)
        /// A `requestStart` was accepted; the start path is running for
        /// `commandId`.
        case starting(commandId: String)
        /// The armed window was spent by a start (wrist or phone); no re-arm
        /// until the ride ends/reset.
        case consumed
    }

    /// The preconditions that must ALL hold for "Ready to ride" to arm (design
    /// "Preconditions"). Expressed as plain data; the failing rows are returned
    /// as sorted `WireStartReasonCode`s for the watch to render.
    struct Preconditions: Equatable, Sendable {
        var appActive: Bool
        var rideIdle: Bool
        var locationAuthorized: Bool
        /// When the camera feature is on: framing completed this session and no
        /// readiness *block* row fails. `true` when the feature is off.
        var cameraReady: Bool
        var noCrashActive: Bool
        var linkReady: Bool

        init(
            appActive: Bool = true,
            rideIdle: Bool = true,
            locationAuthorized: Bool = true,
            cameraReady: Bool = true,
            noCrashActive: Bool = true,
            linkReady: Bool = true
        ) {
            self.appActive = appActive
            self.rideIdle = rideIdle
            self.locationAuthorized = locationAuthorized
            self.cameraReady = cameraReady
            self.noCrashActive = noCrashActive
            self.linkReady = linkReady
        }

        static let allPass = Preconditions()

        /// The sorted reason codes for the failing rows (empty when all pass).
        var failingReasons: [WireStartReasonCode] {
            var reasons: [WireStartReasonCode] = []
            if !appActive { reasons.append(.appNotActive) }
            if !rideIdle { reasons.append(.rideActive) }
            if !locationAuthorized { reasons.append(.location) }
            if !cameraReady { reasons.append(.camera) }
            if !noCrashActive { reasons.append(.crashActive) }
            if !linkReady { reasons.append(.linkNotReady) }
            return reasons.sorted()
        }

        var allPass: Bool { failingReasons.isEmpty }
    }

    // MARK: - Events

    enum Event: Equatable, Sendable {
        /// Rider taps "Ready to ride" on the phone, with the current
        /// preconditions.
        case readyTapped(Preconditions)
        /// Rider taps Cancel on the phone.
        case cancelTapped
        /// The absolute `deadline` passed (evaluated against `now`).
        case expiryCheck
        /// The app resigned active.
        case resignedActive
        /// A crash event became active.
        case crashBecameActive
        /// Location authorization was lost.
        case locationAuthorizationLost
        /// A wrist `requestStart` was accepted by the reducer (carries the id).
        case requestStartAccepted(commandId: String)
        /// The ride became active (the start path finished).
        case rideBecameActive
        /// The start path failed, with a reason to show the watch.
        case startFailed(reason: WireStartReasonCode)
        /// The rider tapped Start on the phone while armed.
        case phoneStartTapped
        /// The ride ended or the machine was reset.
        case rideEndedOrReset
    }

    /// What the caller should do after a transition. Pure data.
    enum Effect: Equatable, Sendable {
        case none
        /// Arm the phone: turn the idle timer off and publish `armed`.
        case didArm(deadline: Date)
        /// Publish `ready` (disarmed by cancel) — no notice.
        case didDisarmReady
        /// Disarm with a phone notice (expiry / resign / crash / auth loss).
        case didDisarmWithNotice(reason: WireStartReasonCode?)
        /// The "Ready" tap failed its preconditions; show the failing rows.
        case showFailingRows([WireStartReasonCode])
        /// Run the start path from the wrist.
        case runStartPath(commandId: String)
        /// Publish the ride status (the ride is now active).
        case publishRideActive
        /// Send a typed start-failure reason to the watch.
        case reportStartFailure(WireStartReasonCode)
        /// A normal phone start consumed the armed window.
        case normalStart
    }

    private(set) var state: State

    /// The armed-window length (default 5 min; clamped by `WatchTuning`).
    let armedExpiryMs: Int

    init(state: State = .disarmed, armedExpiryMs: Int = WatchTuning().armedExpiryMs) {
        self.state = state
        self.armedExpiryMs = armedExpiryMs
    }

    /// The armed deadline, if armed.
    var armedDeadline: Date? {
        if case .armed(let deadline) = state { return deadline }
        return nil
    }

    /// Whether a wrist start is currently accepted.
    var isArmed: Bool { armedDeadline != nil }

    // MARK: - Transition

    /// Apply `event` at `now`, returning the next machine and its effect. An
    /// undefined (state, event) pair is a no-op (row 12).
    func apply(_ event: Event, at now: Date) -> (StartArming, Effect) {
        switch (state, event) {
        // Row 1 — Ready tapped, preconditions pass → armed.
        case let (.disarmed, .readyTapped(pre)) where pre.allPass:
            let deadline = now.addingTimeInterval(Double(armedExpiryMs) / 1_000)
            return (with(.armed(deadline: deadline)), .didArm(deadline: deadline))

        // Row 2 — Ready tapped, a precondition fails → stay disarmed.
        case let (.disarmed, .readyTapped(pre)):
            return (self, .showFailingRows(pre.failingReasons))

        // Row 3 — Cancel while armed → disarmed, publish ready.
        case (.armed, .cancelTapped):
            return (with(.disarmed), .didDisarmReady)

        // Row 4 — expiry while armed.
        case let (.armed(deadline), .expiryCheck) where now >= deadline:
            return (with(.disarmed), .didDisarmWithNotice(reason: nil))
        case (.armed, .expiryCheck):
            return (self, .none) // not yet expired

        // Row 5 — app resigns active while armed.
        case (.armed, .resignedActive):
            return (with(.disarmed), .didDisarmWithNotice(reason: .appNotActive))

        // Row 6 — crash active or location authorization lost while armed.
        case (.armed, .crashBecameActive):
            return (with(.disarmed), .didDisarmWithNotice(reason: .crashActive))
        case (.armed, .locationAuthorizationLost):
            return (with(.disarmed), .didDisarmWithNotice(reason: .location))

        // Row 7 — requestStart accepted while armed → starting.
        case let (.armed, .requestStartAccepted(commandId)):
            return (with(.starting(commandId: commandId)), .runStartPath(commandId: commandId))

        // Row 8 — ride became active while starting → consumed.
        case (.starting, .rideBecameActive):
            return (with(.consumed), .publishRideActive)

        // Row 9 — start failed while starting → disarmed, report reason.
        case let (.starting, .startFailed(reason)):
            return (with(.disarmed), .reportStartFailure(reason))

        // Row 10 — phone Start tapped while armed → consumed (normal start).
        case (.armed, .phoneStartTapped):
            return (with(.consumed), .normalStart)

        // Row 11 — ride ended / reset → disarmed (from consumed or any state).
        case (.consumed, .rideEndedOrReset):
            return (with(.disarmed), .none)

        // Row 12 — undefined transition is a no-op.
        default:
            return (self, .none)
        }
    }

    private func with(_ next: State) -> StartArming {
        StartArming(state: next, armedExpiryMs: armedExpiryMs)
    }
}
