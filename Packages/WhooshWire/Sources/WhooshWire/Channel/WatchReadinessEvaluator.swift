import Foundation

/// Evaluates the phone's "Apple Watch" readiness checklist (watch-companion
/// design "Readiness screen (`WatchReadinessEvaluator`, pure)"; Requirement
/// 3.6, 3.9). Pure value type. **Block does not exist here** — nothing on this
/// screen prevents a ride; every row is pass / warn / info only.
public struct WatchReadinessEvaluator: Sendable {
    public let tuning: WatchTuning

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    /// Which checklist row this is (icon + text rendered by the view).
    public enum Row: String, Equatable, Sendable, CaseIterable {
        case watchPaired
        case appInstalled
        case link
        case healthPermission
        case keepAlive
        case watchBattery
        case hapticsTest
        case reminders
        case audioFallback
        case startFromWatch
    }

    /// A row's status. `info` and `warn` carry a short reason code the view maps
    /// to copy; `pass` means the row is satisfied.
    public enum Status: Equatable, Sendable {
        case pass
        case warn(code: String)
        case info(code: String)
    }

    public struct Item: Equatable, Sendable {
        public var row: Row
        public var status: Status
        public init(row: Row, status: Status) {
            self.row = row
            self.status = status
        }
    }

    /// Inputs to the evaluation (facts the phone already knows).
    public struct Input: Sendable {
        public var linkState: WireLinkState
        public var watch: WireWatchState?
        public var armed: Bool
        public var lastHapticTestFelt: Bool?   // nil = not tested yet

        public init(
            linkState: WireLinkState,
            watch: WireWatchState?,
            armed: Bool,
            lastHapticTestFelt: Bool?
        ) {
            self.linkState = linkState
            self.watch = watch
            self.armed = armed
            self.lastHapticTestFelt = lastHapticTestFelt
        }
    }

    /// Evaluate every row in display order.
    public func evaluate(_ input: Input) -> [Item] {
        [
            Item(row: .watchPaired, status: pairedStatus(input)),
            Item(row: .appInstalled, status: installedStatus(input)),
            Item(row: .link, status: linkStatus(input)),
            Item(row: .healthPermission, status: healthStatus(input)),
            Item(row: .keepAlive, status: keepAliveStatus(input)),
            Item(row: .watchBattery, status: batteryStatus(input)),
            Item(row: .hapticsTest, status: hapticsStatus(input)),
            Item(row: .reminders, status: .info(code: "modesAndStrength")),
            Item(row: .audioFallback, status: .info(code: "audioFallbackAlways")),
            Item(row: .startFromWatch, status: input.armed ? .pass : .info(code: "tapReady")),
        ]
    }

    // MARK: - Per-row rules

    private func pairedStatus(_ input: Input) -> Status {
        input.linkState == .notPaired ? .info(code: "pairInstructions") : .pass
    }

    private func installedStatus(_ input: Input) -> Status {
        input.linkState == .notInstalled ? .info(code: "installInstructions") : .pass
    }

    private func linkStatus(_ input: Input) -> Status {
        switch input.linkState {
        case .ready:
            return .pass
        case .incompatible:
            return .warn(code: "updateWhoosh")
        case .installedUnreachable, .reachableHelloPending:
            return .warn(code: "openWhooshOnWatch")
        case .notPaired, .notInstalled, .unsupported, .activating, .inactive:
            return .warn(code: "linkNotReady")
        }
    }

    private func healthStatus(_ input: Input) -> Status {
        switch input.watch?.healthAuthorized {
        case true?: return .pass
        case false?: return .warn(code: "healthDeniedHapticsOnScreen")
        case nil: return .info(code: "willAskOnWatch")
        }
    }

    private func keepAliveStatus(_ input: Input) -> Status {
        if input.watch?.anotherWorkout == true { return .warn(code: "otherWorkoutRunning") }
        return .pass
    }

    private func batteryStatus(_ input: Input) -> Status {
        guard let pct = input.watch?.batteryPct else { return .pass }
        if pct < tuning.watchBatteryLowPct { return .warn(code: "watchBatteryVeryLow") }
        if pct < tuning.watchBatteryWarnPct { return .warn(code: "watchBatteryLow") }
        return .pass
    }

    private func hapticsStatus(_ input: Input) -> Status {
        switch input.lastHapticTestFelt {
        case true?: return .pass
        case false?: return .info(code: "retryHapticTest")
        case nil: return .info(code: "noTestYet")
        }
    }
}
