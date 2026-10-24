import Foundation
import Testing
@testable import Whoosh

/// Tests for the rear-camera thermal/storage/battery policies and the capture
/// profile selector (rear-camera spec task 5, design "Thermal, battery, and
/// storage budgets"): named cases TP-1…8, SP-1…6, CS-1…8. Pure, no AVFoundation,
/// with a `TestClock`-style fixed `now` supplied through the inputs.
struct CameraPolicyTests {
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)
    private static let tuning = RideCameraTuning()

    // MARK: - ThermalPolicy (TP-1…8)

    /// TP-1: nominal ⇒ run the requested profile (full step); consumers full rate.
    @Test func tp1_nominalRunsFull() {
        let input = ThermalPolicy.Input(thermalLevel: .nominal, currentStep: .full, now: Self.epoch)
        #expect(ThermalPolicy.decide(input) == .run(.full))
        #expect(ThermalPolicy.consumersHalfRate(input) == false)
    }

    /// TP-2: fair ⇒ still the requested profile; consumers full rate.
    @Test func tp2_fairRunsFull() {
        let input = ThermalPolicy.Input(thermalLevel: .fair, currentStep: .full, now: Self.epoch)
        #expect(ThermalPolicy.decide(input) == .run(.full))
        #expect(ThermalPolicy.consumersHalfRate(input) == false)
    }

    /// TP-3: serious steps DOWN frame rate first (full → fps24), not resolution;
    /// consumers capped at half rate.
    @Test func tp3_seriousStepsFpsFirst() {
        let input = ThermalPolicy.Input(thermalLevel: .serious, currentStep: .full, now: Self.epoch)
        #expect(ThermalPolicy.decide(input) == .run(.fps24))
        #expect(ThermalPolicy.consumersHalfRate(input) == true)
    }

    /// TP-4: serious continues stepping one at a time toward resolution-reduced
    /// (fps24 → fps15 → resolutionReduced); never a two-step jump.
    @Test func tp4_seriousStepsOneAtATime() {
        let fromFps24 = ThermalPolicy.Input(thermalLevel: .serious, currentStep: .fps24, now: Self.epoch)
        #expect(ThermalPolicy.decide(fromFps24) == .run(.fps15))

        let fromFps15 = ThermalPolicy.Input(thermalLevel: .serious, currentStep: .fps15, now: Self.epoch)
        #expect(ThermalPolicy.decide(fromFps15) == .run(.resolutionReduced))

        // At the floor it stays there.
        let atFloor = ThermalPolicy.Input(thermalLevel: .serious, currentStep: .resolutionReduced, now: Self.epoch)
        #expect(ThermalPolicy.decide(atFloor) == .run(.resolutionReduced))
    }

    /// TP-5: critical ⇒ stop (finalize; GPS continues).
    @Test func tp5_criticalStops() {
        let input = ThermalPolicy.Input(thermalLevel: .critical, currentStep: .fps15, now: Self.epoch)
        #expect(ThermalPolicy.decide(input) == .stop)
    }

    /// TP-6: a system-pressure shutdown risk (mapped to critical) stops even when
    /// the ProcessInfo thermal level is only fair — the worse level wins.
    @Test func tp6_systemPressureStops() {
        let input = ThermalPolicy.Input(
            thermalLevel: .fair,
            systemPressureLevel: .critical,
            currentStep: .full,
            now: Self.epoch
        )
        #expect(ThermalPolicy.effectiveLevel(input) == .critical)
        #expect(ThermalPolicy.decide(input) == .stop)
    }

    /// TP-7: recovery steps UP one level only after the hysteresis windows pass,
    /// and never two steps at once.
    @Test func tp7_recoveryStepsUpWithHysteresis() {
        // Too soon since the last change ⇒ hold.
        let tooSoon = ThermalPolicy.Input(
            thermalLevel: .fair,
            currentStep: .fps15,
            now: Self.epoch.addingTimeInterval(60),
            lastChangeAt: Self.epoch,
            lastStepUpAt: nil
        )
        #expect(ThermalPolicy.decide(tooSoon) == .run(.fps15))

        // ≥ 5 min since the last change and no prior step-up ⇒ step up ONE level
        // (fps15 → fps24), not to full.
        let ready = ThermalPolicy.Input(
            thermalLevel: .fair,
            currentStep: .fps15,
            now: Self.epoch.addingTimeInterval(5 * 60 + 1),
            lastChangeAt: Self.epoch,
            lastStepUpAt: nil
        )
        #expect(ThermalPolicy.decide(ready) == .run(.fps24))
    }

    /// TP-8: a step-up is rate-limited to one per 10 minutes even if the
    /// per-change cooldown has elapsed.
    @Test func tp8_stepUpRateLimited() {
        let input = ThermalPolicy.Input(
            thermalLevel: .nominal,
            currentStep: .fps24,
            now: Self.epoch.addingTimeInterval(6 * 60),
            lastChangeAt: Self.epoch,                      // 6 min ago (> 5 min)
            lastStepUpAt: Self.epoch.addingTimeInterval(60) // step-up 5 min ago (< 10 min)
        )
        #expect(ThermalPolicy.decide(input) == .run(.fps24))

        // Past the 10-minute interval ⇒ allowed.
        let later = ThermalPolicy.Input(
            thermalLevel: .nominal,
            currentStep: .fps24,
            now: Self.epoch.addingTimeInterval(11 * 60),
            lastChangeAt: Self.epoch,
            lastStepUpAt: Self.epoch.addingTimeInterval(60)
        )
        #expect(ThermalPolicy.decide(later) == .run(.full))
    }

    // MARK: - StoragePolicy + BatteryPolicy (SP-1…6)

    /// SP-1: free space thresholds map to ok/warn/stop (strict-less triggers).
    @Test func sp1_statusThresholds() {
        #expect(StoragePolicy.status(freeBytes: 3_000_000_000) == .ok)   // ≥ start 2 GB
        #expect(StoragePolicy.status(freeBytes: 2_000_000_000) == .ok)   // exactly start
        #expect(StoragePolicy.status(freeBytes: 1_500_000_000) == .ok)   // between warn and start
        #expect(StoragePolicy.status(freeBytes: 900_000_000) == .warn)   // < warn 1 GB
        #expect(StoragePolicy.status(freeBytes: 400_000_000) == .stop)   // < stop 500 MB
    }

    /// SP-2: the start guard refuses to start below the start minimum, allows at/above.
    @Test func sp2_startGuard() {
        #expect(StoragePolicy.canStart(freeBytes: 2_000_000_000) == true)
        #expect(StoragePolicy.canStart(freeBytes: 1_999_999_999) == false)
        #expect(StoragePolicy.allowsAutoPins(freeBytes: 2_000_000_000) == true)
        #expect(StoragePolicy.allowsAutoPins(freeBytes: 900_000_000) == false) // warn refuses auto-pins
    }

    /// SP-3: the effective ring cap shrinks at warn (50%) and is zero at stop.
    @Test func sp3_effectiveRingCapShrinks() {
        #expect(StoragePolicy.effectiveRingCap(freeBytes: 3_000_000_000) == Self.tuning.ringMaxBytes)
        #expect(StoragePolicy.effectiveRingCap(freeBytes: 900_000_000) == Self.tuning.ringMaxBytes / 2)
        #expect(StoragePolicy.effectiveRingCap(freeBytes: 400_000_000) == 0)
    }

    /// SP-4: battery ≤ 20% unplugged ⇒ suggest Efficient; ≤ 8% unplugged ⇒ stop.
    @Test func sp4_batteryFloors() {
        let suggest = BatteryPolicy.Input(batteryLevel: 0.20, isCharging: false, isLowPowerMode: false)
        #expect(BatteryPolicy.decide(suggest) == .useEfficient)

        let higher = BatteryPolicy.Input(batteryLevel: 0.21, isCharging: false, isLowPowerMode: false)
        #expect(BatteryPolicy.decide(higher) == .keep)

        let stop = BatteryPolicy.Input(batteryLevel: 0.08, isCharging: false, isLowPowerMode: false)
        #expect(BatteryPolicy.decide(stop) == .stop)
    }

    /// SP-5: charging cancels the suggest and the stop (but LPM still ⇒ Efficient).
    @Test func sp5_chargingOverride() {
        let lowButCharging = BatteryPolicy.Input(batteryLevel: 0.05, isCharging: true, isLowPowerMode: false)
        #expect(BatteryPolicy.decide(lowButCharging) == .keep)

        let chargingLPM = BatteryPolicy.Input(batteryLevel: 0.05, isCharging: true, isLowPowerMode: true)
        #expect(BatteryPolicy.decide(chargingLPM) == .useEfficient)
    }

    /// SP-6: Low Power Mode (unplugged, ample battery) ⇒ default to Efficient.
    @Test func sp6_lowPowerModeEfficient() {
        let lpm = BatteryPolicy.Input(batteryLevel: 0.90, isCharging: false, isLowPowerMode: true)
        #expect(BatteryPolicy.decide(lpm) == .useEfficient)
    }

    // MARK: - CaptureProfileSelector (CS-1…8)

    private static let allSupported: [CaptureProfile] = [.standard, .efficient, .reduced]

    /// CS-1: requested is supported with no adjustments ⇒ use it as-is.
    @Test func cs1_requestedSupported() {
        let input = CaptureProfileSelector.Input(requested: .standard, supported: Self.allSupported)
        #expect(CaptureProfileSelector.select(input) == .use(.standard))
    }

    /// CS-2: thermal fps step lowers the frame rate of the chosen profile.
    @Test func cs2_thermalFpsStep() {
        let input = CaptureProfileSelector.Input(
            requested: .standard,
            supported: Self.allSupported,
            thermalStep: .fps24
        )
        if case let .use(profile) = CaptureProfileSelector.select(input) {
            #expect(profile.framesPerSecond == 24)
            #expect(profile.width == 1920)
        } else {
            Issue.record("expected a profile")
        }
    }

    /// CS-3: thermal resolution-reduced step selects the Reduced-class profile.
    @Test func cs3_thermalResolutionStep() {
        let input = CaptureProfileSelector.Input(
            requested: .standard,
            supported: Self.allSupported,
            thermalStep: .resolutionReduced
        )
        #expect(CaptureProfileSelector.select(input) == .use(.reduced))
    }

    /// CS-4: battery useEfficient biases a Standard request down to Efficient.
    @Test func cs4_batteryBiasesEfficient() {
        let input = CaptureProfileSelector.Input(
            requested: .standard,
            supported: Self.allSupported,
            battery: .useEfficient
        )
        #expect(CaptureProfileSelector.select(input) == .use(.efficient))
    }

    /// CS-5: battery stop ⇒ unavailable regardless of support.
    @Test func cs5_batteryStopUnavailable() {
        let input = CaptureProfileSelector.Input(
            requested: .standard,
            supported: Self.allSupported,
            battery: .stop
        )
        #expect(CaptureProfileSelector.select(input) == .unavailable)
    }

    /// CS-6: a requested profile the device cannot satisfy falls back to the
    /// nearest supported one (here only Efficient is supported).
    @Test func cs6_fallbackToNearest() {
        let input = CaptureProfileSelector.Input(
            requested: .standard,
            supported: [.efficient]
        )
        #expect(CaptureProfileSelector.select(input) == .use(.efficient))
    }

    /// CS-7: no supported profiles at all ⇒ unavailable (never fails the ride
    /// by crashing; the caller keeps GPS).
    @Test func cs7_noneSupportedUnavailable() {
        let input = CaptureProfileSelector.Input(requested: .standard, supported: [])
        #expect(CaptureProfileSelector.select(input) == .unavailable)
    }

    /// CS-8: combined adjustments — Efficient request under a serious-thermal
    /// fps15 step keeps 720p and drops to 15 fps.
    @Test func cs8_combinedAdjustments() {
        let input = CaptureProfileSelector.Input(
            requested: .efficient,
            supported: Self.allSupported,
            thermalStep: .fps15,
            battery: .useEfficient
        )
        if case let .use(profile) = CaptureProfileSelector.select(input) {
            #expect(profile.width == 1280)
            #expect(profile.height == 720)
            #expect(profile.framesPerSecond == 15)
        } else {
            Issue.record("expected a profile")
        }
    }
}
