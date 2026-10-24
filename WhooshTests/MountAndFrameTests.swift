import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure Mount & frame helpers (rear-camera spec task 9, design
/// "Mount & frame"): `LevelCalculator` LV-1…6 and `ReadinessEvaluator` RE-1…10.
/// No Core Motion; gravity vectors are passed as plain numbers.
struct MountAndFrameTests {
    private static let tuning = RideCameraTuning()

    // MARK: - LevelCalculator (LV-1…6)

    /// LV-1: a perfectly upright portrait phone (gravity straight down the frame,
    /// view axis horizontal) reads ~0° roll, ~0° pitch, and classifies level.
    @Test func lv1_uprightIsLevel() {
        // Gravity points toward the frame's "down" (-y), none out of the screen.
        let r = LevelCalculator.reading(gx: 0, gy: -1, gz: 0, orientation: .portrait)
        #expect(abs(r.rollDegrees) < 0.001)
        #expect(abs(r.pitchDegrees) < 0.001)
        #expect(r.classification == .level)
    }

    /// LV-2: a left/right tilt within 3° stays level; beyond 3° is slightly off.
    @Test func lv2_rollThreshold() {
        // ~2° roll: small +x component.
        let small = LevelCalculator.reading(gx: sin(deg(2)), gy: -cos(deg(2)), gz: 0)
        #expect(abs(small.rollDegrees - 2) < 0.01)
        #expect(small.classification == .level)

        // ~5° roll: beyond tolerance.
        let big = LevelCalculator.reading(gx: sin(deg(5)), gy: -cos(deg(5)), gz: 0)
        #expect(abs(big.rollDegrees - 5) < 0.01)
        #expect(big.classification == .slightlyOff)
    }

    /// LV-3: pitch sign — gravity out of the screen (+z) means the camera points
    /// down (positive pitch), inside the +15° target.
    @Test func lv3_pitchDownInRange() {
        let r = LevelCalculator.reading(gx: 0, gy: -cos(deg(10)), gz: sin(deg(10)))
        #expect(r.pitchDegrees > 0)
        #expect(abs(r.pitchDegrees - 10) < 0.01)
        #expect(r.classification == .level)
    }

    /// LV-4: pitch beyond the +15° / −5° range is slightly off.
    @Test func lv4_pitchOutOfRange() {
        let tooDown = LevelCalculator.reading(gx: 0, gy: -cos(deg(25)), gz: sin(deg(25)))
        #expect(tooDown.pitchDegrees > 15)
        #expect(tooDown.classification == .slightlyOff)

        let tooUp = LevelCalculator.reading(gx: 0, gy: -cos(deg(10)), gz: -sin(deg(10)))
        #expect(tooUp.pitchDegrees < -5)
        #expect(tooUp.classification == .slightlyOff)
    }

    /// LV-5: landscape orientation remaps the roll axis, so a device-space tilt
    /// that would be roll in portrait is handled relative to the mounted frame.
    @Test func lv5_landscapeOrientation() {
        // In landscapeLeft the frame's "down" is device -x. Gravity along -x is
        // upright for that orientation ⇒ ~0° roll.
        let r = LevelCalculator.reading(gx: 1, gy: 0, gz: 0, orientation: .landscapeLeft)
        #expect(abs(r.rollDegrees) < 0.01)
        #expect(r.classification == .level)
    }

    /// LV-6: small sensor noise around upright stays level (robustness).
    @Test func lv6_noiseStaysLevel() {
        let r = LevelCalculator.reading(gx: 0.01, gy: -0.999, gz: 0.01)
        #expect(r.classification == .level)
    }

    // MARK: - ReadinessEvaluator (RE-1…10)

    /// A baseline all-good input; individual tests override one field.
    private func goodInput(
        camera: CameraPermissionStatus = .authorized,
        freeBytes: Int64 = 3_000_000_000,
        battery: Double = 0.80,
        charging: Bool = false,
        lowPower: Bool = false,
        thermal: ThermalLevel = .nominal,
        location: ReadinessEvaluator.LocationReadiness = .whileUsing,
        dark: Bool = false,
        level: LevelCalculator.Classification = .level
    ) -> ReadinessEvaluator.Input {
        ReadinessEvaluator.Input(
            cameraPermission: camera,
            freeBytes: freeBytes,
            batteryLevel: battery,
            isCharging: charging,
            isLowPowerMode: lowPower,
            thermalLevel: thermal,
            location: location,
            isSceneDark: dark,
            level: level
        )
    }

    private func level(_ results: [ReadinessEvaluator.Result], _ row: ReadinessEvaluator.Row) -> ReadinessEvaluator.Level? {
        results.first(where: { $0.row == row })?.level
    }

    /// RE-1: all good ⇒ every gating row passes and the camera can start.
    @Test func re1_allGood() {
        let input = goodInput()
        #expect(ReadinessEvaluator.canStartCamera(input) == true)
        let results = ReadinessEvaluator.evaluate(input)
        #expect(level(results, .cameraPermission) == .pass)
        #expect(level(results, .storage) == .pass)
        #expect(level(results, .battery) == .pass)
        #expect(level(results, .thermal) == .pass)
        #expect(level(results, .locationPermission) == .pass)
    }

    /// RE-2: camera permission states map pass/warn/block and block stops start.
    @Test func re2_cameraPermission() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(camera: .authorized)), .cameraPermission) == .pass)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(camera: .notDetermined)), .cameraPermission) == .warn)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(camera: .denied)), .cameraPermission) == .block)
        #expect(ReadinessEvaluator.canStartCamera(goodInput(camera: .denied)) == false)
        #expect(ReadinessEvaluator.canStartCamera(goodInput(camera: .notDetermined)) == true)
    }

    /// RE-3: storage thresholds (≥2 GB pass, 1–2 GB warn, <1 GB block).
    @Test func re3_storage() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(freeBytes: 2_000_000_000)), .storage) == .pass)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(freeBytes: 1_500_000_000)), .storage) == .warn)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(freeBytes: 900_000_000)), .storage) == .block)
        #expect(ReadinessEvaluator.canStartCamera(goodInput(freeBytes: 900_000_000)) == false)
    }

    /// RE-4: battery (≥40% or charging pass, 20–40% warn, <20% unplugged block).
    @Test func re4_battery() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(battery: 0.45)), .battery) == .pass)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(battery: 0.30)), .battery) == .warn)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(battery: 0.10)), .battery) == .block)
        // Charging makes even 5% pass.
        #expect(level(ReadinessEvaluator.evaluate(goodInput(battery: 0.05, charging: true)), .battery) == .pass)
    }

    /// RE-5: Low Power Mode is a warn (profile will switch to Efficient), never a block.
    @Test func re5_lowPowerMode() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(lowPower: false)), .lowPowerMode) == .pass)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(lowPower: true)), .lowPowerMode) == .warn)
        #expect(ReadinessEvaluator.canStartCamera(goodInput(lowPower: true)) == true)
    }

    /// RE-6: thermal (nominal pass, fair warn, serious/critical block).
    @Test func re6_thermal() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(thermal: .nominal)), .thermal) == .pass)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(thermal: .fair)), .thermal) == .warn)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(thermal: .serious)), .thermal) == .block)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(thermal: .critical)), .thermal) == .block)
    }

    /// RE-7: location permission (whileUsing pass, notDetermined warn, denied block).
    @Test func re7_location() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(location: .whileUsing)), .locationPermission) == .pass)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(location: .notDetermined)), .locationPermission) == .warn)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(location: .denied)), .locationPermission) == .block)
        #expect(ReadinessEvaluator.canStartCamera(goodInput(location: .denied)) == false)
    }

    /// RE-8: dark scene is a hint (warn), never a blocker; level slightly-off is warn.
    @Test func re8_darkSceneAndLevelAreWarns() {
        #expect(level(ReadinessEvaluator.evaluate(goodInput(dark: true)), .darkScene) == .warn)
        #expect(level(ReadinessEvaluator.evaluate(goodInput(level: .slightlyOff)), .level) == .warn)
        #expect(ReadinessEvaluator.canStartCamera(goodInput(dark: true, level: .slightlyOff)) == true)
    }

    /// RE-9: the always-shown reminder rows are present and classified as reminders.
    @Test func re9_reminderRows() {
        let results = ReadinessEvaluator.evaluate(goodInput())
        #expect(level(results, .lens) == .reminder)
        #expect(level(results, .secureMount) == .reminder)
        #expect(level(results, .focus) == .reminder)
        #expect(level(results, .guidedAccess) == .reminder)
        // Every row appears exactly once, in order.
        #expect(results.count == ReadinessEvaluator.Row.allCases.count)
    }

    /// RE-10: warns never block, but any gating block prevents start even amid passes.
    @Test func re10_blockGatesStart() {
        // Several warns, no blocks ⇒ can start.
        let warnsOnly = goodInput(camera: .notDetermined, battery: 0.30, lowPower: true, thermal: .fair, dark: true)
        #expect(ReadinessEvaluator.canStartCamera(warnsOnly) == true)

        // One gating block (location denied) ⇒ cannot start, regardless of passes.
        let blocked = goodInput(location: .denied)
        #expect(ReadinessEvaluator.canStartCamera(blocked) == false)
    }

    // MARK: - Helpers

    private func deg(_ d: Double) -> Double { d * Double.pi / 180 }
}
