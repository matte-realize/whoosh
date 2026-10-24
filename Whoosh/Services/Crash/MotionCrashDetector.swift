import CoreMotion
import Foundation

/// A thread-safe holder for the ride's latest GPS speed (m/s). The composition
/// root updates it from the active ride session; the detector reads it when it
/// processes a motion sample. Kept as a tiny `Sendable` box so wiring stays
/// decoupled from the ride engine's concrete type.
///
/// Lives with the detector (Services/Crash) because it exists only to bridge the
/// ride engine and the motion detector.
final class RideSpeedSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var speed: Double?

    init(speed: Double? = nil) {
        self.speed = speed
    }

    /// The latest known speed in m/s, or `nil` when unknown.
    var current: Double? {
        lock.lock(); defer { lock.unlock() }
        return speed
    }

    /// Update the latest speed (called on the main actor from the ride engine).
    func update(_ newSpeed: Double?) {
        lock.lock(); defer { lock.unlock() }
        speed = newSpeed
    }
}

/// The **experimental** motion-based crash detector (crash-response task 33,
/// Requirement 5.5/5.6/5.7). The only `CrashDetector` that reads Core Motion.
///
/// It is a thin adapter: it streams device-motion from `CMMotionManager`, feeds
/// the acceleration magnitude and the current GPS speed into the pure
/// `MotionCrashSignalCore` (task 32), and emits a `CrashSignal` when the core
/// reports a probable crash. **All of the decision logic lives in the pure
/// core**; this file only moves numbers from the device into it and the
/// resulting signal out.
///
/// ## Where the work runs
/// Device-motion callbacks are delivered on the **main actor** (the project's
/// default isolation). Per sample the work is a vector magnitude plus windowed
/// scoring over a few seconds of samples — cheap enough to stay on the main
/// actor without affecting ride recording, and it keeps the adapter free of
/// cross-actor plumbing. The sampling rate is battery-aware (see
/// `MotionSamplingProfile`) so the main-actor cost is bounded. If this ever
/// shows up in profiling, the core is already a pure value type that can be
/// moved to a dedicated executor without changing its logic.
///
/// ## Contract (privacy steering + `CrashDetector` docs)
/// - **Armed only while riding.** `start()`/`stop()` are driven by
///   `RideSessionBridge`/`CrashArming`, so motion streams only while a ride is
///   recording with consent, a label, and a reachable contact. `stop()` releases
///   the motion manager.
/// - **No permission prompt.** Device-motion / raw accelerometer streaming is not
///   gated by a permission prompt (motion *activity* APIs are — those are not
///   used). No `NSMotionUsageDescription` is required.
/// - **On-device, nothing uploaded.** Samples never leave the device, are not
///   logged, and are not persisted. This file imports no networking API.
/// - **Battery-aware.** The update interval is chosen by the injected
///   `MotionSamplingProfile` so a low-battery/Low-Power ride samples less often;
///   the owner tunes the acceptance bar (O9) from measured field results before
///   any UI offers this.
/// - **Never blocks recording.** `start()`/`stop()` return immediately and a
///   failure degrades to "no signal" (Requirement 5.8).
/// - **Experimental.** Labeled experimental everywhere; it cannot guarantee
///   detection or delivery. The countdown's large "I'm OK — Cancel" is the
///   false-positive safety net.
@MainActor
final class MotionCrashDetector: CrashDetector {
    /// Battery-aware sampling cadence. Faster sampling resolves a short impact
    /// spike better; slower sampling saves power. The adapter maps the chosen
    /// profile to a `CMMotionManager` update interval.
    enum MotionSamplingProfile: Sendable {
        /// ~50 Hz — the default while on battery at a healthy charge.
        case standard
        /// ~20 Hz — used under Low Power Mode or a low battery.
        case efficient

        /// Seconds between device-motion updates.
        var updateInterval: TimeInterval {
            switch self {
            case .standard: return 1.0 / 50.0
            case .efficient: return 1.0 / 20.0
            }
        }
    }

    var onSignal: ((CrashSignal) -> Void)?

    /// The source label recorded on emitted signals.
    static let sourceLabel = "motion"

    private let tuning: MotionCrashTuning
    private let clock: Clock
    /// The ride's current GPS speed, read when a sample is processed.
    private let speedSnapshot: RideSpeedSnapshot
    /// Chooses the sampling cadence at `start()` (battery-aware). Injectable so
    /// tests and previews do not read `UIDevice`/`ProcessInfo`.
    private let samplingProfile: () -> MotionSamplingProfile
    /// Factory for the motion manager, injectable so tests never need a device.
    private let makeMotionManager: () -> CMMotionManager

    /// The live motion manager while monitoring; `nil` when stopped.
    private var motionManager: CMMotionManager?
    /// The pure core (value type), mutated only on the main actor.
    private var core: MotionCrashSignalCore

    /// `true` between `start()` and `stop()`.
    private(set) var isMonitoring = false

    init(
        tuning: MotionCrashTuning = MotionCrashTuning(),
        clock: Clock,
        speedSnapshot: RideSpeedSnapshot,
        samplingProfile: @escaping () -> MotionSamplingProfile = { .standard },
        makeMotionManager: @escaping () -> CMMotionManager = { CMMotionManager() }
    ) {
        self.tuning = tuning
        self.clock = clock
        self.speedSnapshot = speedSnapshot
        self.samplingProfile = samplingProfile
        self.makeMotionManager = makeMotionManager
        self.core = MotionCrashSignalCore(tuning: tuning)
    }

    // MARK: - CrashDetector

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let manager = makeMotionManager()
        guard manager.isDeviceMotionAvailable else {
            // No device motion (e.g. Simulator): degrade to "no signal". Ride
            // recording is unaffected (Requirement 5.8).
            motionManager = nil
            return
        }

        // Fresh core each ride so a previous ride's samples never carry over.
        core = MotionCrashSignalCore(tuning: tuning)
        manager.deviceMotionUpdateInterval = samplingProfile().updateInterval
        motionManager = manager

        // Deliver on the main queue so processing stays on the main actor; the
        // per-sample work is light and the rate is battery-aware.
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.handle(motion)
            }
        }
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
    }

    // MARK: - Processing (main actor)

    /// Process one device-motion sample: feed the magnitude and current speed to
    /// the core, then emit on any trigger. Exposed for unit tests to drive the
    /// adapter's wiring without a device.
    func handle(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z) * MotionCrashTuning.gravity
        ingestAndEvaluate(accelerationMagnitude: magnitude, at: clock.now())
    }

    /// The device-free processing step (same path `handle` uses): ingest the
    /// acceleration magnitude (m/s²) and the current GPS speed, evaluate, and
    /// emit on a trigger. Separated so tests can drive it without a
    /// `CMDeviceMotion`.
    func ingestAndEvaluate(accelerationMagnitude magnitude: Double, at now: Date) {
        core.ingest(acceleration: magnitude, at: now)
        if let speed = speedSnapshot.current {
            core.ingest(speed: speed, at: now)
        }
        if case let .trigger(confidence, at) = core.evaluate(now: now) {
            emit(confidence: confidence, at: at)
        }
    }

    /// Deliver a probable-crash signal (the contract delivers on the main actor).
    /// The coordinator still decides whether to act (it may be disarmed,
    /// suppressed, or capped).
    private func emit(confidence: Double, at time: Date) {
        guard isMonitoring else { return }
        onSignal?(
            CrashSignal(
                timestamp: time,
                confidence: confidence,
                source: Self.sourceLabel,
                isDrill: false
            )
        )
    }
}
