import SwiftUI

/// The app entry point and navigation host (task 23).
///
/// Builds the live composition root (`AppEnvironment.live()`), owns a
/// `NavigationStack` rooted at `HomeView`, pushes History and Settings (with a
/// "Home" back label), pushes `RideSummaryView` for a tapped recent/history
/// ride, and presents the active ride as a **non-dismissible full-screen
/// cover** while a session is in progress. When the ride finishes the cover
/// switches to the finished-ride summary; "Done" resets the session and returns
/// to Home. All service wiring lives here; views stay framework-service-free.
///
/// Lifecycle: `persistSnapshot()` runs when the scene goes background/inactive
/// (task 21 safeguard), and on launch an unfinished ride triggers a "Finish your
/// interrupted ride?" alert (Save finalizes it; Discard deletes that record).
@main
struct WhooshApp: App {
    @State private var environment = AppEnvironment.live()
    @State private var path: [Route] = []

    /// The in-progress ride session, or `nil` when idle. Created on Start Ride.
    @State private var rideSession: RideSessionViewModel?
    /// An unfinished ride found on launch, pending the recovery decision.
    @State private var interruptedRide: Ride?
    /// Set once if local storage degraded to a non-persistent store; shown as a
    /// calm, dismissible notice (Requirement 11.4).
    @State private var storageNoticePresented = false
    /// Presents the crash-alert status screen after a backup-notification tap
    /// (crash-response task 26, Requirement 13.3). Prompt-only; nothing automatic.
    @State private var crashStatusPresented = false
    /// Routes crash backup-notification taps to the status screen.
    @State private var notificationRouter = CrashNotificationRouter()
    /// Presents the crash-alert setup hub. It is a sheet, not a push: the hub
    /// owns its own NavigationStack, and nesting one stack inside the Home
    /// stack crashes SwiftUI (AnyNavigationPath comparisonTypeMismatch).
    @State private var crashAlertsPresented = false

    /// The Mount & frame view model, presented after Start Ride when rear camera
    /// recording is on (rear-camera task 22). `nil` when not framing.
    @State private var mountAndFrame: MountAndFrameViewModel?
    /// The camera recording coordinator for the active ride (rear-camera task
    /// 19). `nil` when the camera is off for this ride. Drives recording with
    /// the ride; a camera failure never affects the ride or GPS.
    @State private var cameraCoordinator: CameraRecordingCoordinator?
    /// The ride-mode controller for the active ride (rear-camera task 21). `nil`
    /// unless ride mode is on for this ride.
    @State private var rideModeController: RideModeController?
    /// The rear-vehicle detection composition for the active ride. `nil` when
    /// rear camera recording is off for this ride. It registers the vision
    /// detector on the shared frame pipeline and runs it only while recording;
    /// its `detectionState` drives the ride-screen camera chip.
    @State private var rideDetection: RideDetectionCoordinator?
    /// The live rear-camera preview + detection-box view model for the active
    /// ride screen (owner device-testing feedback). `nil` when the camera is off
    /// for this ride; the ride screen then shows only the map with no camera
    /// toggle. Display only — it never captures, records, or uploads.
    @State private var cameraPreview: CameraPreviewViewModel?
    @Environment(\.scenePhase) private var scenePhase

    /// Routes pushed on the Home-rooted stack.
    private enum Route: Hashable {
        case history
        case settings
        case summary(Ride)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(
                    viewModel: environment.homeViewModel,
                    onStartRide: startRide,
                    onOpenHistory: { path.append(.history) },
                    onOpenSettings: { path.append(.settings) },
                    onSelectRide: { path.append(.summary($0)) },
                    crashAlertsOn: environment.crash.isFeatureOn,
                    rearCameraOn: environment.isRearCameraRecordingEnabled
                )
                .navigationDestination(for: Route.self, destination: destination)
            }
            .overlay(alignment: .top) {
                // DEMO MODE badge over the app chrome (Home + pushed screens),
                // below the ride cover and any crash takeover. Tapping it opens
                // the demo tools in Settings (O-DM5).
                if environment.demo.badgeVisible {
                    DemoBadge(scheme: .light) {
                        if path.last != .settings { path.append(.settings) }
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
            }
            .fullScreenCover(isPresented: coverBinding) {
                coverContent
            }
            // Mount & frame: shown after Start Ride when rear camera recording
            // is on (rear-camera task 22). "Start ride" begins the ride with the
            // camera; "Ride without camera" starts a normal ride.
            .fullScreenCover(isPresented: mountAndFrameBinding) {
                if let mountAndFrame {
                    MountAndFrameView(viewModel: mountAndFrame)
                }
            }
            // The crash-countdown takeover is mounted as a root-level overlay
            // ABOVE the NavigationStack AND the active-ride full-screen cover
            // (design D25): it must appear from Home (drills) and from the ride
            // screen, and cannot be swiped away.
            .crashCountdownHost(coordinator: environment.crash.coordinator)
            .sheet(isPresented: $crashStatusPresented) {
                NavigationStack {
                    CrashAlertStatusView(coordinator: environment.crash.coordinator)
                }
            }
            .alert(
                "Finish your interrupted ride?",
                isPresented: interruptedAlertBinding,
                presenting: interruptedRide
            ) { ride in
                Button("Save") { saveInterrupted(ride) }
                Button("Discard", role: .destructive) { discardInterrupted(ride) }
            } message: { _ in
                Text("Whoosh found a ride that didn't finish. Save it to your history or discard it.")
            }
            .alert(
                "Ride saving unavailable",
                isPresented: $storageNoticePresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(environment.storageNotice ?? "")
            }
            .onAppear(perform: onLaunch)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
            .onChange(of: notificationRouter.shouldOpenStatus) { _, shouldOpen in
                if shouldOpen {
                    crashStatusPresented = true
                    notificationRouter.shouldOpenStatus = false
                }
            }
            // Push the crash countdown to the wrist the instant it starts/ends
            // (real or a demo drill), so the watch shows its Cancel takeover
            // without waiting for the next 1 Hz tick.
            .onChange(of: environment.crash.coordinator.isTakeoverPresented) { _, _ in
                environment.watchLive.publishNow()
            }
        }
    }

    // MARK: - Navigation destinations

    /// Builds the History view model and wires its local delete to request a
    /// remote deletion too (no-op while sync is off).
    private func makeHistoryViewModel() -> HistoryViewModel {
        let viewModel = environment.makeHistoryViewModel()
        viewModel.onDidDelete = { ride in
            Task { await environment.rideWasDeleted(ride) }
        }
        return viewModel
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .history:
            HistoryView(
                viewModel: makeHistoryViewModel(),
                onSelectRide: { path.append(.summary($0)) }
            )
        case .settings:
            SettingsView(
                viewModel: environment.settingsViewModel,
                rearCamera: environment.rearCameraSettingsViewModel,
                demo: environment.demo,
                onOpenCrashAlerts: { crashAlertsPresented = true }
            )
            .sheet(isPresented: $crashAlertsPresented, onDismiss: {
                // Contacts / consent / toggle may have changed in setup; re-arm.
                environment.crash.reevaluateArming()
            }) {
                crashAlertsSetup
            }
        case .summary(let ride):
            RideSummaryView(ride: ride, presentation: .historyDetail, nearMisses: nearMisses(for: ride))
        }
    }

    /// The crash-alert setup hub, presented as a sheet from Settings.
    private var crashAlertsSetup: some View {
        EmergencySetupHostView(
            contactStore: environment.crash.contactStore,
            consentStore: environment.crash.consentStore,
            settingsStore: environment.crash.settingsStore,
            notifier: environment.crash.noopNotifier,
            connectivity: environment.crash.connectivity,
            scheduler: environment.crash.scheduler,
            repository: environment.crash.repository,
            clock: environment.clock,
            isMessagingConnected: environment.crash.isMessagingConnected,
            onConsentRevoked: {
                // Revoking disarms immediately and cancels any queued unsent
                // alert (Requirement 3.7).
                environment.crash.coordinator.consentRevoked()
                environment.crash.reevaluateArming()
            }
        )
    }

    // MARK: - Ride cover

    /// Present the cover whenever a session is active or finished (showing the
    /// summary). Non-dismissible: the setter ignores programmatic dismissal so a
    /// swipe/tap can't abandon a ride (Requirement 1.5).
    private var coverBinding: Binding<Bool> {
        Binding(
            get: {
                guard let session = rideSession else { return false }
                return RideFlowCoordinator.isCoverPresented(
                    for: session.rideState,
                    finishedRide: session.finishedRide
                )
            },
            set: { _ in }
        )
    }

    @ViewBuilder
    private var coverContent: some View {
        if let session = rideSession {
            switch RideFlowCoordinator.coverContent(
                for: session.rideState,
                finishedRide: session.finishedRide
            ) {
            case .activeRide:
                ActiveRideView(
                    viewModel: session,
                    crashAlertsOn: environment.crash.isFeatureOn,
                    cameraState: cameraCoordinator?.state,
                    detectionState: rideDetection?.detectionState,
                    onSaveClip: cameraCoordinator == nil ? nil : { cameraCoordinator?.saveClip() ?? .nothingToSave },
                    cameraPreview: cameraPreview
                )
                .interactiveDismissDisabled()
                .overlay(alignment: .top) {
                    if environment.demo.badgeVisible {
                        // Positioned at the top so it never obscures the
                        // three metrics or the hold-to-stop control.
                        DemoBadge(scheme: .dark)
                            .padding(.top, Theme.Spacing.sm)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if environment.demo.badgeVisible {
                        RideScreenDemoMenu(controller: environment.demo)
                            .padding(Theme.Spacing.lg)
                    }
                }
                // Ride mode overlay (true-black, touch-locked) above the active
                // ride content when the camera is on with ride mode enabled.
                .overlay {
                    if let rideModeController, rideModeController.isOverlayPresented {
                        RideModeView(
                            controller: rideModeController,
                            controls: RideModeControls(
                                isPaused: session.rideState == .paused,
                                onStop: { session.stop() },
                                onTogglePause: {
                                    if session.rideState == .paused {
                                        session.resume()
                                    } else {
                                        session.pause()
                                    }
                                },
                                onSaveClip: cameraCoordinator == nil
                                    ? nil
                                    : { cameraCoordinator?.saveClip() ?? .nothingToSave }
                            )
                        )
                    }
                }
            case .summary(let ride):
                NavigationStack {
                    RideSummaryView(
                        ride: ride,
                        presentation: .justFinished,
                        nearMisses: nearMisses(for: ride),
                        onDone: finishRide
                    )
                }
                .interactiveDismissDisabled()
            case .none:
                // Nothing to show; dismiss by clearing the session next runloop.
                Color.clear.onAppear { clearRideSession() }
            }
        }
    }

    // MARK: - Mount & frame binding

    private var mountAndFrameBinding: Binding<Bool> {
        Binding(
            get: { mountAndFrame != nil },
            set: { if !$0 { mountAndFrame = nil } }
        )
    }

    // MARK: - Near misses

    /// The locally stored near-miss events for a ride (rear-camera Req 15, task
    /// 28), shown as markers on the summary map and a count row. Empty when the
    /// store has none; footage is never referenced (events only).
    private func nearMisses(for ride: Ride) -> [NearMissEvent] {
        (try? environment.nearMissRepository.events(rideId: ride.id)) ?? []
    }

    // MARK: - Ride lifecycle

    /// Start Ride from Home. When rear camera recording is on, go through Mount
    /// & frame first (frame the camera, then start with or without the camera).
    /// Otherwise start a normal ride immediately — the MVP path is unchanged.
    private func startRide() {
        guard environment.isRearCameraRecordingEnabled else {
            beginRide(withCamera: false)
            return
        }
        let viewModel = environment.makeMountAndFrameViewModel()
        viewModel.onStartWithCamera = {
            mountAndFrame = nil
            beginRide(withCamera: true)
        }
        viewModel.onSkipCamera = {
            mountAndFrame = nil
            beginRide(withCamera: false)
        }
        mountAndFrame = viewModel
    }

    /// Begin the ride session and, when requested and enabled, the camera
    /// recording coordinator and ride mode. A camera failure never affects the
    /// ride or GPS (the coordinator only reads the ride through a bridge).
    private func beginRide(withCamera: Bool) {
        let session = environment.makeRideSession()
        rideSession = session
        session.start()

        // Make the watch live for this ride: publish ride/camera/crash status
        // ~1 Hz and route wrist commands (pause/resume/stop/save clip/cancel
        // crash) to the ride engine. A no-op remote (no usable watch) makes this
        // harmless, so the ride flow is unchanged.
        environment.watchLive.attach(ride: session, camera: nil)
        attachWatchCommands(to: session)

        guard withCamera, environment.isRearCameraRecordingEnabled else { return }

        let coordinator = environment.makeCameraCoordinator(for: session)
        cameraCoordinator = coordinator

        // Now that the camera coordinator exists, re-attach so the watch sees the
        // live camera state and "Save clip" from the wrist works.
        environment.watchLive.attach(ride: session, camera: coordinator)
        attachWatchCommands(to: session)

        // Rear-vehicle detection on the SAME frame pipeline the camera records
        // through: load the model once (it was preloaded when the feature was
        // enabled) and run the detector only while recording. A detection fires
        // the shared alert manager; detection never blocks capture or the ride.
        let detection = environment.makeRideDetectionCoordinator(for: session)
        rideDetection = detection
        detection?.beginRide()

        // The live-preview view model for the ride screen's camera toggle (owner
        // device-testing feedback). It subscribes to the detector's view-only
        // overlay-box seam; the preview itself is off by default (battery). Nil
        // when the camera is off for this ride.
        cameraPreview = environment.makeCameraPreviewViewModel(detection: detection)

        // Ride mode (dim, touch-locked) when the rider left it on in Settings.
        var rideMode: RideModeController?
        if environment.rearCameraSettingsViewModel.settings.rideModeEnabled {
            let controller = environment.makeRideModeController(
                isRideActive: { [weak session] in session?.rideState.isActive ?? false }
            )
            rideModeController = controller
            controller.rideStarted()
            rideMode = controller
            coordinator.onClipSaved = { [weak controller] saved in
                controller?.showToast(saved ? .clipSaved : .clipNotSaved)
            }
        }

        // One state-change fan-out: drive detection start/stop from the live
        // camera state, and (when present) reflect camera trouble as the amber
        // dot in ride mode. Detection tears down on pause/interruption/stop/
        // failure because those are not `.recording`/`.degraded`.
        coordinator.onStateChange = { [weak rideMode] state in
            detection?.cameraStateChanged(state)
            rideMode?.setTrouble(!state.isRecording && state != .off)
        }

        coordinator.rideStarted()
    }

    /// Route wrist commands to the ride engine and the crash cancel. Called when
    /// a ride begins and again once the camera coordinator exists (so "Save clip"
    /// from the wrist saves a real clip). A no-op remote (no usable watch) never
    /// invokes the handler, so nothing changes when no watch is paired.
    private func attachWatchCommands(to session: RideSessionViewModel) {
        environment.attachRemoteCommands(
            to: session,
            saveClip: { [weak cameraCoordinator] in
                cameraCoordinator?.saveClip() ?? .nothingToSave
            },
            cancelCrashCountdown: { environment.crash.coordinator.riderCancel() }
        )
    }

    /// "Done" on the finished-ride summary: upload it (no-op while sync is off),
    /// clear the session (dismisses the cover) and refresh Home so the new ride
    /// appears in stats/recent.
    private func finishRide() {
        let finished = rideSession?.finishedRide
        clearRideSession()
        environment.homeViewModel.load()
        if let finished {
            Task { await environment.rideDidFinish(finished) }
        }
    }

    /// Clear the ride session and detach the crash bridge (disarms detection).
    /// Also tears down the camera coordinator and ride mode so the camera stops
    /// and the brightness is restored.
    private func clearRideSession() {
        cameraCoordinator?.rideEnded()
        cameraCoordinator = nil
        rideDetection?.endRide()
        rideDetection = nil
        cameraPreview?.clear()
        cameraPreview = nil
        rideModeController?.rideEnded()
        rideModeController = nil
        // Drop the ride binding but keep the watch coordinator ticking so a crash
        // drill triggered later from Home still reaches the wrist.
        environment.watchLive.detachRide()
        environment.clearRideSession()
        rideSession = nil
    }

    // MARK: - Launch

    private func onLaunch() {
        notificationRouter.install()
        // Reconcile any persisted active crash event (task 14): resume a live
        // countdown, prompt for recovery past a deadline, or mark stale — never
        // auto-send on relaunch (Requirement 13.5).
        environment.crash.reconcileOnLaunch()
        checkForInterruptedRide()
        // Warm the rear-vehicle detection model once if the feature is on, so it
        // is ready before the first ride (no-op when rear camera is off).
        environment.preloadRearDetectionModelIfNeeded()
        // Crash alerts are on by default, so ask for notification access up
        // front rather than only inside the consent flow (the countdown's
        // backup notification needs it). The system shows the prompt once.
        if environment.crash.settingsStore.current().enabled {
            let scheduler = environment.crash.scheduler
            Task { _ = await scheduler.requestAuthorizationIfNeeded() }
        }
        // Begin the watch live feed so a crash drill triggered from Home (demo,
        // no ride) still reaches the wrist. A no-op remote (no usable watch) makes
        // this a harmless no-op.
        environment.watchLive.start()
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            environment.crash.coordinator.enterForeground()
            // Retry pending uploads/deletes (no-op while sync is off).
            Task { await environment.retryPendingSync() }
        } else {
            rideSession?.persistSnapshot()
            environment.crash.coordinator.enterBackground()
        }
    }

    // MARK: - Interrupted-ride recovery (task 21 / 3.6)

    private func checkForInterruptedRide() {
        // Use a throwaway session purely to query the repository for an
        // unfinished ride; it owns no live tracking until `start()`. Detach the
        // crash bridge the probe attached, since we are not starting a ride.
        let probe = environment.makeRideSession()
        interruptedRide = probe.recoverInterruptedRide()
        environment.clearRideSession()
        // Surface the non-fatal storage notice once, if storage degraded.
        if environment.storageNotice != nil { storageNoticePresented = true }
    }

    private func saveInterrupted(_ ride: Ride) {
        let session = environment.makeRideSession()
        session.finalizeRecoveredRide(ride)
        environment.clearRideSession()
        interruptedRide = nil
        environment.homeViewModel.load()
    }

    private func discardInterrupted(_ ride: Ride) {
        try? environment.repository.delete(id: ride.id)
        interruptedRide = nil
        environment.homeViewModel.load()
    }

    // MARK: - Alert binding

    private var interruptedAlertBinding: Binding<Bool> {
        Binding(
            get: { interruptedRide != nil },
            set: { if !$0 { interruptedRide = nil } }
        )
    }
}
