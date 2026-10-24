import Foundation
import SwiftData

/// The composition root (task 23). Builds and owns the concrete services and
/// view models, and is the **only** place that wires framework service types —
/// views stay free of them (layering table: "Composition knows about
/// everything").
///
/// Two factories exist:
/// - `live()` builds the real stack: a `SwiftDataRideRepository` over a
///   `ModelContainer` for `RideRecord`, `CoreLocationTracker`s, `SystemClock`,
///   and the no-op detector/alert seams.
/// - `preview(seeded:)` / the test initializer build a fake stack
///   (`InMemoryRideRepository`, `FakeLocationTracker`, an injected `Clock`) so
///   SwiftUI previews and unit tests never touch Core Location or on-disk
///   storage.
///
/// Location wiring note: `HomeViewModel` and `RideSessionViewModel` each take
/// their own `LocationTracking` instance (both set the single
/// `onAuthorizationChange` callback, so sharing one would clobber the other).
/// Home only needs authorization status + the first-run prompt; the ride
/// session owns the recording tracker. On a real device both wrap a
/// `CLLocationManager` and report the same system authorization.
@MainActor
final class AppEnvironment {
    let repository: RideRepository
    let clock: Clock
    let detector: HazardDetector
    let alertManager: AlertManager
    /// Local store of near-miss events (rear-camera Req 15, task 28). Shared by
    /// the recorder (write), the summary/history UI (read), and the sync path
    /// (read, upsert after a ride). Device-only; the local clip id is never
    /// uploaded.
    let nearMissRepository: NearMissRepository
    /// Persists near-miss events produced by detection/demo. Available for the
    /// detector-coordinator wiring and the demo-mode simulated-detector path.
    let nearMissRecorder: NearMissRecorder

    /// The opt-in crash-response sub-environment (crash-response task 26). Owns
    /// the coordinator, stores, and seams; always Tier 0 (Noop notifier, no
    /// network) here. With crash alerts off, nothing in it touches the network,
    /// so the app behaves exactly as the MVP (Requirement 1.5).
    let crash: CrashResponseEnvironment

    /// A calm, non-fatal notice to show the user when local storage had to fall
    /// back to a non-persistent store (Requirement 11.4). `nil` in the normal
    /// case. App-written copy only — never raw framework error text.
    let storageNotice: String?

    /// Persisted GPS-accuracy setting; fed into `RideTuning` for each new ride.
    let settingsViewModel: SettingsViewModel
    /// Drives the "Rear camera" Settings section and the first-enable camera
    /// permission flow (rear-camera spec Requirement 2/18.1, task 20). Off by
    /// default; the camera is requested only when the rider enables recording.
    let rearCameraSettingsViewModel: RearCameraSettingsViewModel
    /// The shared rear-camera service stack (capture, frame pipeline, segment
    /// store, clip pinner, level sensor) used to build a per-ride
    /// `CameraRecordingCoordinator` and the Mount & frame screen (rear-camera
    /// task 19/22). All framework ownership stays inside these services; views
    /// and view models see only protocols.
    let cameraServices: CameraServices
    /// The **single** rear-vehicle detector for the app session, built lazily on
    /// first use so its CoreML model loads **once** (not per ride). Each ride's
    /// `RideDetectionCoordinator` reuses this consumer, so the loaded model
    /// survives across rides. `nil` until the first ride-detection build. Only
    /// built when rear camera recording is enabled.
    private var sharedVisionConsumer: VisionVehicleConsumer?
    /// The SwiftData-backed clip repository over the same live `ModelContainer`
    /// as rides (rear-camera task 15/19). Clip metadata is on-device only.
    let clipRepository: ClipRepository
    /// The Home hub view model (owns its own tracker for authorization).
    let homeViewModel: HomeViewModel

    /// Demo mode's controller (demo-mode tasks 8–9). Built **always** but inert
    /// while its toggle is off, so the off path is the exact normal path
    /// (Requirement 9.1). The only composition-root branch on demo state lives
    /// in `makeRideSession()`.
    let demo: DemoModeController

    /// The opt-in sync coordinator. Backed by `NoopRideSyncService` in previews/
    /// tests and whenever no Supabase config is present, so with sync OFF the
    /// app makes zero network calls and behaves exactly as before.
    let syncCoordinator: SyncCoordinator

    /// Builds a fresh `LocationTracking` for a ride session. Injectable so
    /// previews/tests supply a `FakeLocationTracker`.
    private let makeRideTracker: () -> LocationTracking

    private init(
        repository: RideRepository,
        clock: Clock,
        detector: HazardDetector,
        alertManager: AlertManager,
        nearMissRepository: NearMissRepository,
        crash: CrashResponseEnvironment,
        calendar: Calendar,
        defaults: UserDefaults,
        storageNotice: String? = nil,
        supabaseProvider: SupabaseClientProvider?,
        appVersion: String,
        pendingDeletes: PendingRemoteDeleteStore,
        cameraPermission: CameraPermission,
        rearCameraStore: RearCameraSettingsStore,
        clipRepository: ClipRepository,
        cameraServices: CameraServices,
        makeHomeTracker: () -> LocationTracking,
        makeRideTracker: @escaping () -> LocationTracking
    ) {
        self.repository = repository
        self.clock = clock
        self.detector = detector
        self.alertManager = alertManager
        self.nearMissRepository = nearMissRepository
        self.nearMissRecorder = NearMissRecorder(repository: nearMissRepository)
        self.crash = crash
        self.storageNotice = storageNotice
        self.makeRideTracker = makeRideTracker
        self.clipRepository = clipRepository
        self.cameraServices = cameraServices
        let settings = SettingsViewModel(repository: repository, defaults: defaults)
        self.settingsViewModel = settings
        self.rearCameraSettingsViewModel = RearCameraSettingsViewModel(
            permission: cameraPermission,
            store: rearCameraStore,
            clipRepository: clipRepository
        )
        self.homeViewModel = HomeViewModel(
            repository: repository,
            clock: clock,
            calendar: calendar,
            tracker: makeHomeTracker()
        )
        // Build the demo controller over the same repository/clock/alert seams.
        // A simulated ride is recorded by a real `RideSessionViewModel` whose
        // tracker is a `SimulatedRouteTracker` (no mixing with real GPS by
        // construction, Requirement 5.4); the accuracy comes from the persisted
        // Settings choice, exactly like a normal ride.
        self.demo = DemoModeController(
            defaults: defaults,
            clock: clock,
            alertManager: alertManager,
            repository: repository,
            makeSimulatedTracker: { script, factor in
                SimulatedRouteTracker(script: script, clock: clock, speedFactor: factor)
            },
            makeSimulatedSession: { tracker in
                var tuning = RideTuning()
                tuning.accuracy = settings.trackingAccuracy
                return RideSessionViewModel(
                    tracker: tracker,
                    clock: clock,
                    repository: repository,
                    tuning: tuning
                )
            }
        )

        // Choose the sync service: the real Supabase one only when a client is
        // configured (secrets present); otherwise the Noop (sync never signs in).
        // Its `isEnabled` reads a thread-safe flag mirrored from the live
        // Settings toggle, so with sync OFF the coordinator makes zero network
        // calls and the app behaves as before.
        let enabledFlag = SyncEnabledFlag(settings.syncEnabled)
        let service: RideSyncService
        if let provider = supabaseProvider, let client = provider.client {
            let transport = SupabaseRideSyncTransport(client: client)
            service = SupabaseRideSyncService(
                transport: transport,
                appVersion: appVersion,
                isEnabled: { enabledFlag.isOn }
            )
        } else {
            service = NoopRideSyncService()
        }
        let coordinator = SyncCoordinator(
            service: service,
            repository: repository,
            pendingDeletes: pendingDeletes,
            nearMissEvents: { [nearMissRepository] rideId in
                (try? nearMissRepository.events(rideId: rideId)) ?? []
            }
        )
        self.syncCoordinator = coordinator

        // Mirror the Settings toggle into the flag and retry pending uploads
        // when the user turns sync on.
        settings.onSyncEnabledChange = { enabled in
            enabledFlag.set(enabled)
            guard enabled else { return }
            Task { await coordinator.retryPending() }
        }
        // When the user chooses to unshare already-shared rides.
        let repo = repository
        settings.onUnshareAllSharedRides = { [weak coordinator] in
            guard let coordinator else { return }
            let shared = ((try? repo.allRides()) ?? []).filter { $0.sharePublicly }
            Task { await coordinator.unshareRides(shared) }
        }
        // Propagate remote deletes after "Delete all rides".
        settings.onDidDeleteAllRides = { [weak coordinator] ids in
            guard let coordinator, !ids.isEmpty else { return }
            Task { await coordinator.allRidesWereDeleted(previouslySynced: ids) }
        }
    }

    // MARK: - Sync lifecycle hooks (called by the app / history)

    /// After a ride is saved locally, mirror it to the backend (stamping the
    /// current global sharing flag). No-op while sync is off.
    func rideDidFinish(_ ride: Ride) async {
        await syncCoordinator.rideDidFinish(
            ride,
            shareNewRidesPublicly: settingsViewModel.shareNewRidesPublicly
        )
    }

    /// After a ride is deleted locally, request its remote deletion and remove
    /// its local near-miss events (real deletion; footage/links never persist).
    func rideWasDeleted(_ ride: Ride) async {
        try? nearMissRepository.deleteAll(rideId: ride.id)
        await syncCoordinator.rideWasDeleted(ride)
    }

    /// Before/after "Delete all rides", propagate remote deletes for any rides
    /// that had been uploaded. Pass the ids collected before the wipe. Also
    /// clears every local near-miss event (they belong to the deleted rides).
    func allRidesWereDeleted(previouslySynced ids: [UUID]) async {
        try? nearMissRepository.deleteAll()
        await syncCoordinator.allRidesWereDeleted(previouslySynced: ids)
    }

    /// App-foreground retry of pending uploads and deletes.
    func retryPendingSync() async {
        await syncCoordinator.retryPending()
    }

    // MARK: - Factories for view models

    /// A fresh ride session, with `RideTuning.accuracy` taken from the persisted
    /// Settings choice so the setting applies to the next ride (Requirement
    /// 14.2). A new tracker is created so the session owns its location stream.
    ///
    /// Demo branch (the **only** composition-root branch on demo state): when a
    /// simulated ride has been requested, the demo controller already owns a
    /// `SimulatedRouteTracker`-backed session, so return that one — one ride ⇒
    /// one tracker ⇒ all-scripted or all-real, never mixed (Requirement 5.4).
    /// With demo mode off (or no simulated ride requested) this returns exactly
    /// today's `CoreLocationTracker`-backed session, so the off path is the
    /// identity path (Requirement 9.1).
    ///
    /// Also attaches the crash-response bridge to the session so detection can
    /// arm while recording (no-op unless the rider enabled crash alerts); the
    /// bridge is detached when the ride is cleared (`clearRideSession()`).
    func makeRideSession() -> RideSessionViewModel {
        if let simulated = demo.simulatedSession {
            // Demo rides get the bridge too, so a crash drill can arm during one.
            crash.attachRide(simulated)
            return simulated
        }
        var tuning = RideTuning()
        tuning.accuracy = settingsViewModel.trackingAccuracy
        let session = RideSessionViewModel(
            tracker: makeRideTracker(),
            clock: clock,
            repository: repository,
            tuning: tuning
        )
        crash.attachRide(session)
        return session
    }

    /// Detach the crash bridge when a ride session is cleared (ride finished or
    /// an interrupted-ride probe is thrown away). Safe to call repeatedly.
    func clearRideSession() {
        crash.detachRide()
    }

    // MARK: - Rear-camera factories (rear-camera task 19/22)

    /// Whether the rider has turned rear camera recording on (drives Mount &
    /// frame vs. a normal ride at Start Ride, and the Home/Settings toggle).
    var isRearCameraRecordingEnabled: Bool {
        rearCameraSettingsViewModel.recordingEnabled
    }

    /// Build a `CameraRecordingCoordinator` bound to a ride session, driving
    /// recording with the ride through a read-only `RideCameraBridge`. The ride
    /// engine is never modified; a camera failure never changes ride state or
    /// GPS points (Requirement 1.3, 17.4). Camera notices route through the
    /// shared `alertManager` (phone audio now; watch later).
    func makeCameraCoordinator(for session: RideSessionViewModel) -> CameraRecordingCoordinator {
        let bridge = RideCameraBridge(session: session, clock: clock)
        let services = cameraServices
        let coordinator = CameraRecordingCoordinator(
            capture: services.capture,
            pipeline: services.pipeline,
            makeRecorder: { rideId in services.makeRecorder(rideId) },
            segmentStore: services.segmentStore,
            clipPinner: services.clipPinner,
            alertManager: alertManager,
            bridge: bridge,
            settings: { services.settingsStore.load() },
            clock: clock,
            tuning: services.tuning
        )
        // Set concrete-only capture properties (camera position + the pixel
        // `videoSink` that feeds the detector pipeline) before start. Only the
        // real `CameraCaptureService` exposes these; the fake needs nothing.
        coordinator.configureCapture = { position in
            if let service = services.capture as? CameraCaptureService {
                service.cameraPosition = position
                service.videoSink = services.pipeline
            }
        }
        return coordinator
    }

    /// Build the rear-vehicle **detection** composition for a ride, bound to the
    /// same shared `FramePipeline` the camera coordinator records through
    /// (rear-camera task 14 + B1 glue). This is the missing wire: it registers
    /// the real `VisionVehicleConsumer` (Teammate B's `VehicleDetector` as a
    /// `FrameConsumer`) on the pipeline and runs the `DetectionCoordinator` only
    /// while the camera is recording. A detection fires the shared
    /// `alertManager` through `RearAlertGate` (demo mode bypasses only the speed
    /// gate) and records a local near-miss event. Detection never blocks capture
    /// or recording; footage never leaves the device.
    ///
    /// Returns `nil` when rear camera recording is off for this ride — the ride
    /// then runs exactly as before with no detector built and no model loaded.
    func makeRideDetectionCoordinator(for session: RideSessionViewModel) -> RideDetectionCoordinator? {
        guard isRearCameraRecordingEnabled else { return nil }
        let bridge = RideCameraBridge(session: session, clock: clock)
        let consumer = sharedRearDetector()
        let alertManager = self.alertManager
        let clock = self.clock
        let demo = self.demo
        let confidence = VisionTuning().minConfidence

        return RideDetectionCoordinator(
            consumer: consumer,
            isEnabled: { [weak self] in self?.isRearCameraRecordingEnabled ?? false },
            makeCoordinator: { detector, cameraStateProvider, isDetectionEnabled in
                DetectionCoordinator(
                    detector: detector,
                    pipeline: self.cameraServices.pipeline,
                    alertManager: alertManager,
                    clock: clock,
                    confidenceThreshold: confidence,
                    rideStateProvider: { bridge.rideState },
                    currentSpeedProvider: { bridge.speedMetersPerSecond ?? 0 },
                    cameraStateProvider: cameraStateProvider,
                    isDetectionEnabled: isDetectionEnabled,
                    isDemoMode: { demo.isEnabled },
                    currentRideId: { bridge.rideId },
                    routeCoordinate: { instant in bridge.routeCoordinate(at: instant) },
                    recordNearMiss: { _ in
                        // Near-miss persistence is owned by the parallel
                        // NearMissRecorder branch, which subscribes via
                        // `onDetection` / `detectionEvents()`; this composition
                        // only runs the detector and the alert path.
                    }
                )
            }
        )
    }

    /// Build the camera-preview view model for the active ride screen so the
    /// rider can see the live rear camera with the experimental vision
    /// detections drawn on top (owner device-testing feedback). It holds the
    /// same preview host Mount & frame uses and subscribes to the detector's
    /// **view-only** overlay-box seam. Display only: it never captures, records,
    /// or uploads; footage and frames stay on the device. Returns `nil` when the
    /// camera is off for this ride, which hides the camera view on the ride
    /// screen.
    func makeCameraPreviewViewModel(detection: RideDetectionCoordinator?) -> CameraPreviewViewModel? {
        guard isRearCameraRecordingEnabled else { return nil }
        let viewModel = CameraPreviewViewModel(previewHost: cameraServices.previewHost)
        detection?.onOverlayBoxes = { [weak viewModel] boxes in
            viewModel?.update(boxes: boxes)
        }
        return viewModel
    }

    /// The one shared rear-vehicle detector, built on first use so its CoreML
    /// model loads **once** for the whole app session.
    private func sharedRearDetector() -> VisionVehicleConsumer {
        if let consumer = sharedVisionConsumer { return consumer }
        let consumer = VisionVehicleConsumer(tuning: VisionTuning())
        sharedVisionConsumer = consumer
        return consumer
    }

    /// Start the one-time async model load as soon as rear camera recording is
    /// enabled, so the model is warm before the first ride (task: load once when
    /// the feature is enabled, not per ride). No-op when the feature is off or
    /// already preloaded. The detector consumes no frames until a ride registers
    /// it with the pipeline.
    func preloadRearDetectionModelIfNeeded() {
        guard isRearCameraRecordingEnabled else { return }
        sharedRearDetector().start()
    }

    /// Build the Mount & frame view model shown after Start Ride when rear
    /// recording is on. The caller wires `onStartWithCamera` / `onSkipCamera`.
    func makeMountAndFrameViewModel() -> MountAndFrameViewModel {
        let services = cameraServices
        return MountAndFrameViewModel(
            previewHost: services.previewHost,
            levelSensor: services.makeLevelSensor(),
            settingsStore: services.settingsStore,
            clock: clock
        )
    }

    /// Build the ride-mode controller for a ride (rear-camera task 21). Ride
    /// mode is on only when the rider enabled it in Settings; the controller
    /// restores brightness on every exit path.
    func makeRideModeController(isRideActive: @escaping () -> Bool) -> RideModeController {
        RideModeController(
            screen: UIKitScreenController.shared,
            dimGuardStore: UserDefaultsDimGuardStore(),
            clock: clock,
            tuning: cameraServices.tuning,
            pickupSensor: cameraServices.makeLevelSensor(),
            isRideActive: isRideActive,
            isRideModeEnabled: { [weak self] in
                self?.rearCameraSettingsViewModel.settings.rideModeEnabled ?? false
            }
        )
    }

    /// A fresh History view model over the shared repository.
    func makeHistoryViewModel(calendar: Calendar = .current) -> HistoryViewModel {
        HistoryViewModel(
            repository: repository,
            calendar: calendar,
            nearMissRepository: nearMissRepository
        )
    }

    // MARK: - Live stack

    /// The real composition root. Falls back to an in-memory SwiftData container
    /// if an on-disk store cannot be created, so the app still launches (history
    /// simply won't persist across launches in that degraded case).
    static func live() -> AppEnvironment {
        let (repository, crashRepository, clipRepository, nearMissRepository, storageNotice) = Self.makeLiveRepositories()
        let clock = SystemClock()

        // The single Supabase client provider, shared by opt-in ride sync and
        // opt-in crash alerts. When no secrets are present `isConfigured` is
        // false and both features stay offline (Noop notifier / Noop sync).
        let supabaseProvider = SupabaseClientProvider()
        let appVersion = Self.appVersion()

        // Crash-response stores (device-local only; no network). Contacts live
        // only in the Keychain; orphaned items are purged on a fresh install.
        let markerStore = UserDefaultsFreshInstallMarkerStore()
        let contactStore = KeychainEmergencyContactStore(markerStore: markerStore)
        try? contactStore.purgeOrphansIfFreshInstall()
        let settingsStore = UserDefaultsCrashAlertSettingsStore()
        let consentStore = UserDefaultsConsentStore()

        // Detector source. The experimental `MotionCrashDetector` is the LIVE
        // detector whenever crash alerts are enabled (the hackathon default is
        // on); it reads Core Motion only while the bridge arms it during a ride.
        // The `DebugCrashSimulator` is still built when developer/demo tools are
        // on so the "Simulate crash" drill works. When both exist they are fanned
        // into one `CompositeCrashDetector`; either alone is used directly.
        //
        // Either way detection only *acts* when the bridge arms it (recording +
        // consent + label + reachable contact) and the reducer allows it — the
        // detector never decides that. Experimental: cannot guarantee detection
        // or delivery; the countdown's "I'm OK — Cancel" is the safety net.
        let crashSettings = settingsStore.current()
        let speedSnapshot = RideSpeedSnapshot()

        let motion: MotionCrashDetector? = crashSettings.enabled
            ? MotionCrashDetector(clock: clock, speedSnapshot: speedSnapshot)
            : nil
        let simulator: DebugCrashSimulator? = crashSettings.developerToolsEnabled
            ? DebugCrashSimulator(clock: clock)
            : nil

        let detector: CrashDetector
        switch (motion, simulator) {
        case let (m?, s?):
            detector = CompositeCrashDetector([m, s])
        case let (m?, nil):
            detector = m
        case let (nil, s?):
            detector = s
        case (nil, nil):
            detector = NoopCrashDetector()
        }

        // Notifier: Tier 1 `SupabaseCrashNotifier` when a Supabase client is
        // configured (auto-send on the rider's behalf — the owner's "if it's
        // bad the user won't be able to click send" requirement); otherwise the
        // Tier 0 Noop (no network), so the composer fallback and local
        // notification remain. Only `Services/Notification` touches the network.
        let notifier: CrashNotifier
        let messagingConnected: Bool
        if let client = supabaseProvider.client {
            let transport = SupabaseFunctionsCrashTransport(client: client)
            notifier = SupabaseCrashNotifier(
                transport: transport,
                appVersion: appVersion
            )
            messagingConnected = true
        } else {
            notifier = NoopCrashNotifier()           // Tier 0: no network
            messagingConnected = false
        }

        let crash = CrashResponseEnvironment(
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: crashRepository,
            connectivity: NWPathConnectivityMonitor(),
            scheduler: UserNotificationsCrashNotificationScheduler(),
            notifier: notifier,
            feedback: SystemCountdownFeedback(),
            footageBuffer: NoopFootageBuffer(),
            detector: detector,
            simulator: simulator,
            clock: clock,
            speedSnapshot: speedSnapshot,
            isMessagingConnected: messagingConnected
        )

        // Rear-camera service stack (rear-camera task 19/22). The capture
        // service is the only capture-session owner and also vends the Mount
        // & frame preview host. Clip metadata is stored in the shared live
        // container's `ClipRepository`; footage files live on-device only.
        let rearCameraStore = UserDefaultsRearCameraSettingsStore()
        let captureService = CameraCaptureService()
        let cameraServices = CameraServices.live(
            capture: captureService,
            previewHost: captureService,
            clipRepository: clipRepository,
            settingsStore: rearCameraStore,
            clock: clock
        )

        // The app-wide alert manager is a `FanOutAlertManager` with a phone
        // audio sink (the no-watch fallback channel), so camera notices and the
        // rear-vehicle cue surface on the phone (rear-camera task 29). A watch
        // sink is added later. It stays inert until `fire(_:)` is called.
        let alertManager = FanOutAlertManager(
            sinks: [PhoneAudioAlertSink()],
            clock: clock,
            appState: { .foregroundActiveScreen }
        )

        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            // Ship the fan-out alert manager app-wide: it is inert until
            // `fire(_:)` is called, so normal mode is unchanged, the demo's
            // forced-alert path produces a real cue, and camera notices reach the
            // phone speaker.
            alertManager: alertManager,
            nearMissRepository: nearMissRepository,
            crash: crash,
            calendar: .current,
            defaults: .standard,
            storageNotice: storageNotice,
            supabaseProvider: supabaseProvider,
            appVersion: appVersion,
            pendingDeletes: UserDefaultsPendingRemoteDeleteStore(),
            cameraPermission: AVCameraPermission(),
            rearCameraStore: rearCameraStore,
            clipRepository: clipRepository,
            cameraServices: cameraServices,
            makeHomeTracker: { CoreLocationTracker() },
            makeRideTracker: { CoreLocationTracker() }
        )
    }

    /// The short build string (`CFBundleShortVersionString`), capped at the
    /// contract's 32-char `app_version` limit.
    private static func appVersion() -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        return String(raw.prefix(32))
    }

    /// Builds the ride, crash-alert, clip, and near-miss repositories over a
    /// **single shared `ModelContainer`** holding `RideRecord`,
    /// `CrashAlertRecordEntity`, `ClipRecordEntity`, and `NearMissEventEntity`
    /// (crash-response task 26, rear-camera tasks 15/19/28: every record entity
    /// lives in the same live container as rides, keeping the container-retention
    /// rule and the in-memory fallback). Existing ride data is untouched by adding
    /// the new `@Model`s.
    private static func makeLiveRepositories() -> (RideRepository, CrashAlertRepository, ClipRepository, NearMissRepository, String?) {
        let schema: [any PersistentModel.Type] = [
            RideRecord.self,
            CrashAlertRecordEntity.self,
            ClipRecordEntity.self,
            NearMissEventEntity.self,
        ]
        do {
            let container = try ModelContainer(for: Schema(schema))
            let context = container.mainContext
            return (
                SwiftDataRideRepository(context: context),
                SwiftDataCrashAlertRepository(context: context),
                SwiftDataClipRepository(context: context),
                SwiftDataNearMissRepository(context: context),
                nil
            )
        } catch {
            // Degrade gracefully: an in-memory store keeps the app usable. Never
            // surface the raw framework error — a calm, app-written notice only
            // (Requirements 11.4 / design: SwiftData container failure is a
            // non-fatal notice, not a crash).
            let notice = "Saved rides are unavailable right now, so new rides won't be kept after you close the app. Everything else works."
            if let inMemory = try? ModelContainer(
                for: Schema(schema),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                let context = inMemory.mainContext
                return (
                    SwiftDataRideRepository(context: context),
                    SwiftDataCrashAlertRepository(context: context),
                    SwiftDataClipRepository(context: context),
                    SwiftDataNearMissRepository(context: context),
                    notice
                )
            }
            return (
                InMemoryRideRepository(),
                InMemoryCrashAlertRepository(),
                InMemoryClipRepository(),
                InMemoryNearMissRepository(),
                notice
            )
        }
    }

    // MARK: - Preview / test stack

    /// A fake-backed environment for SwiftUI previews and unit tests. All
    /// dependencies are fakes; nothing touches Core Location or disk.
    static func preview(
        seeded: Bool = true,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> AppEnvironment {
        let rides = seeded ? PreviewSeed.rides(now: Date()) : []
        let repository = InMemoryRideRepository(rides: rides)
        let clipRepository = InMemoryClipRepository()
        let rearCameraStore = InMemoryRearCameraSettingsStore()
        let cameraServices = CameraServices.fake(
            clipRepository: clipRepository,
            settingsStore: rearCameraStore,
            clock: clock
        )
        let crash = CrashResponseEnvironment(
            contactStore: InMemoryEmergencyContactStore(),
            consentStore: InMemoryConsentStore(),
            settingsStore: InMemoryCrashAlertSettingsStore(),
            repository: InMemoryCrashAlertRepository(),
            connectivity: FakeConnectivityMonitor(isOnline: true),
            scheduler: FakeCrashNotificationScheduler(),
            notifier: NoopCrashNotifier(),
            feedback: NoopCountdownFeedback(),
            footageBuffer: NoopFootageBuffer(),
            detector: NoopCrashDetector(),
            simulator: nil,
            clock: clock
        )
        return AppEnvironment(
            repository: repository,
            clock: clock,
            detector: NoopDetector(),
            alertManager: StubAlertManager(),
            nearMissRepository: InMemoryNearMissRepository(),
            crash: crash,
            calendar: calendar,
            defaults: defaults,
            supabaseProvider: nil,
            appVersion: "preview",
            pendingDeletes: InMemoryPendingRemoteDeleteStore(),
            cameraPermission: FakeCameraPermission(status: .notDetermined),
            rearCameraStore: rearCameraStore,
            clipRepository: clipRepository,
            cameraServices: cameraServices,
            makeHomeTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) },
            makeRideTracker: { FakeLocationTracker(authorizationStatus: .authorizedWhenInUse) }
        )
    }
}
