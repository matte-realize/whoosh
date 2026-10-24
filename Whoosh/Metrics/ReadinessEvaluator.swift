import Foundation

/// Pure readiness-checklist evaluator for the Mount & frame screen (rear-camera
/// spec Requirement 9.3, design "Readiness checklist"). Given the device/app
/// inputs, it classifies each checklist row as pass / warn / block and reports
/// whether recording can start (a `block` on any gating row means it cannot).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The view
/// model gathers the inputs from the permission, storage, battery, thermal, and
/// level sources (each behind its own seam) and passes a snapshot in. A failing
/// row explains the consequence; only the gating rows (camera permission,
/// storage, location) hard-block the ride.
enum ReadinessEvaluator {
    /// The outcome for one checklist row.
    enum Level: String, Equatable, Sendable {
        /// Good.
        case pass
        /// Allowed, with a consequence explained; never blocks the ride.
        case warn
        /// Recording cannot start (no permission, no space, or GPS impossible).
        case block
        /// Informational reminder, always shown (lens, mount, Focus, Guided Access).
        case reminder
    }

    /// Which checklist row a result refers to (stable identifiers for the UI).
    enum Row: String, Equatable, Sendable, CaseIterable {
        case cameraPermission
        case storage
        case battery
        case lowPowerMode
        case thermal
        case locationPermission
        case darkScene
        case level
        case lens
        case secureMount
        case focus
        case guidedAccess
    }

    /// One evaluated row.
    struct Result: Equatable, Sendable {
        let row: Row
        let level: Level
    }

    /// The location authorization, modeled locally so the Metrics layer needs
    /// only Foundation + Models.
    enum LocationReadiness: String, Equatable, Sendable {
        case whileUsing
        case notDetermined
        case denied
    }

    /// The inputs the checklist classifies.
    struct Input: Equatable, Sendable {
        let cameraPermission: CameraPermissionStatus
        /// Free bytes available for important usage.
        let freeBytes: Int64
        /// Battery charge as a 0...1 fraction.
        let batteryLevel: Double
        let isCharging: Bool
        let isLowPowerMode: Bool
        let thermalLevel: ThermalLevel
        let location: LocationReadiness
        /// Whether the scene is dark (a hint, never a blocker).
        let isSceneDark: Bool
        /// The level classification from `LevelCalculator`.
        let level: LevelCalculator.Classification
        let tuning: RideCameraTuning

        init(
            cameraPermission: CameraPermissionStatus,
            freeBytes: Int64,
            batteryLevel: Double,
            isCharging: Bool,
            isLowPowerMode: Bool,
            thermalLevel: ThermalLevel,
            location: LocationReadiness,
            isSceneDark: Bool,
            level: LevelCalculator.Classification,
            tuning: RideCameraTuning = RideCameraTuning()
        ) {
            self.cameraPermission = cameraPermission
            self.freeBytes = freeBytes
            self.batteryLevel = batteryLevel
            self.isCharging = isCharging
            self.isLowPowerMode = isLowPowerMode
            self.thermalLevel = thermalLevel
            self.location = location
            self.isSceneDark = isSceneDark
            self.level = level
            self.tuning = tuning
        }
    }

    /// Evaluate every row, in display order.
    static func evaluate(_ input: Input) -> [Result] {
        [
            Result(row: .cameraPermission, level: cameraPermission(input.cameraPermission)),
            Result(row: .storage, level: storage(input.freeBytes, input.tuning)),
            Result(row: .battery, level: battery(input)),
            Result(row: .lowPowerMode, level: input.isLowPowerMode ? .warn : .pass),
            Result(row: .thermal, level: thermal(input.thermalLevel)),
            Result(row: .locationPermission, level: location(input.location)),
            Result(row: .darkScene, level: input.isSceneDark ? .warn : .pass),
            Result(row: .level, level: input.level == .level ? .pass : .warn),
            Result(row: .lens, level: .reminder),
            Result(row: .secureMount, level: .reminder),
            Result(row: .focus, level: .reminder),
            Result(row: .guidedAccess, level: .reminder),
        ]
    }

    /// Whether recording can start: no gating row is `block`. The gating rows are
    /// camera permission, storage, and location (design: "Block means recording
    /// cannot start"); warns never block.
    static func canStartCamera(_ input: Input) -> Bool {
        !evaluate(input).contains { $0.level == .block }
    }

    // MARK: - Row classifiers

    private static func cameraPermission(_ status: CameraPermissionStatus) -> Level {
        switch status {
        case .authorized: return .pass
        case .notDetermined: return .warn
        case .denied, .restricted: return .block
        }
    }

    private static func storage(_ freeBytes: Int64, _ tuning: RideCameraTuning) -> Level {
        if freeBytes >= tuning.freeSpaceStart { return .pass }      // ≥ 2 GB
        if freeBytes >= tuning.freeSpaceWarn { return .warn }       // 1–2 GB
        return .block                                               // < 1 GB (below start)
    }

    private static func battery(_ input: Input) -> Level {
        if input.isCharging || input.batteryLevel >= 0.40 { return .pass }
        if input.batteryLevel >= input.tuning.batterySuggestEfficient { return .warn } // 20–40%
        return .block                                                                   // < 20% unplugged
    }

    private static func thermal(_ level: ThermalLevel) -> Level {
        switch level {
        case .nominal: return .pass
        case .fair: return .warn
        case .serious, .critical: return .block
        }
    }

    private static func location(_ location: LocationReadiness) -> Level {
        switch location {
        case .whileUsing: return .pass
        case .notDetermined: return .warn
        case .denied: return .block
        }
    }
}
