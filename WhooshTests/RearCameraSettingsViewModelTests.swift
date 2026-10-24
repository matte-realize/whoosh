import Foundation
import Testing
@testable import Whoosh

/// Tests for the rear-camera permission flow and the Settings view model
/// (rear-camera spec Requirement 2.1–2.7, 18.1; task 20, test cases PERM-1…4).
///
/// `@MainActor` because `RearCameraSettingsViewModel` and the fakes inherit the
/// project's default MainActor isolation. Permission is driven by
/// `FakeCameraPermission`; settings are persisted into an injected in-memory
/// store, so nothing touches AVFoundation or global `UserDefaults`.
@MainActor
struct RearCameraSettingsViewModelTests {

    private func makeViewModel(
        permission: FakeCameraPermission = FakeCameraPermission(),
        store: InMemoryRearCameraSettingsStore = InMemoryRearCameraSettingsStore(),
        clips: InMemoryClipRepository = InMemoryClipRepository()
    ) -> RearCameraSettingsViewModel {
        RearCameraSettingsViewModel(
            permission: permission,
            store: store,
            clipRepository: clips
        )
    }

    // MARK: - PERM-1: never requests at launch; explanation gates the prompt

    /// PERM-1: constructing the view model never requests camera access; the
    /// prompt is only triggered after the rider enables recording AND
    /// acknowledges the explanation.
    @Test func perm1_noRequestAtLaunchExplanationGatesPrompt() async {
        let permission = FakeCameraPermission(status: .notDetermined, grantResult: .authorized)
        let vm = makeViewModel(permission: permission)

        // Construction asked for nothing.
        #expect(permission.requestCount == 0)
        #expect(vm.recordingEnabled == false)

        // Enabling from notDetermined shows the explanation but does NOT prompt.
        vm.setRecordingEnabled(true)
        #expect(vm.isShowingExplanation == true)
        #expect(permission.requestCount == 0)
        #expect(vm.recordingEnabled == false)

        // Acknowledging triggers the prompt; a grant turns recording on.
        await vm.acknowledgeExplanation()
        #expect(permission.requestCount == 1)
        #expect(vm.permissionStatus == .authorized)
        #expect(vm.recordingEnabled == true)
        #expect(vm.isShowingExplanation == false)
    }

    /// PERM-1b: dismissing the explanation requests nothing and leaves recording
    /// off.
    @Test func perm1b_dismissExplanationRequestsNothing() {
        let permission = FakeCameraPermission(status: .notDetermined)
        let vm = makeViewModel(permission: permission)

        vm.setRecordingEnabled(true)
        vm.dismissExplanation()

        #expect(permission.requestCount == 0)
        #expect(vm.recordingEnabled == false)
        #expect(vm.isShowingExplanation == false)
    }

    // MARK: - PERM-2: already authorized skips the prompt

    /// PERM-2: enabling while already authorized turns recording on with no
    /// explanation and no prompt.
    @Test func perm2_alreadyAuthorizedSkipsPrompt() {
        let permission = FakeCameraPermission(status: .authorized)
        let vm = makeViewModel(permission: permission)

        vm.setRecordingEnabled(true)

        #expect(vm.isShowingExplanation == false)
        #expect(permission.requestCount == 0)
        #expect(vm.recordingEnabled == true)
    }

    // MARK: - PERM-3: denied / restricted flow

    /// PERM-3: a prompt that resolves to denied leaves recording off and shows
    /// the denied state with an Open Settings path.
    @Test func perm3_promptDeniedShowsDeniedState() async {
        let permission = FakeCameraPermission(status: .notDetermined, grantResult: .denied)
        let vm = makeViewModel(permission: permission)

        vm.setRecordingEnabled(true)
        await vm.acknowledgeExplanation()

        #expect(vm.permissionStatus == .denied)
        #expect(vm.recordingEnabled == false)
        #expect(vm.showsDeniedState == true)
    }

    /// PERM-3b: enabling while already denied does NOT re-prompt (the system
    /// never re-prompts); it surfaces the denied state and stays off.
    @Test func perm3b_enablingWhileDeniedDoesNotRePrompt() {
        let permission = FakeCameraPermission(status: .denied)
        let vm = makeViewModel(permission: permission)

        vm.setRecordingEnabled(true)

        #expect(permission.requestCount == 0)
        #expect(vm.isShowingExplanation == false)
        #expect(vm.recordingEnabled == false)
        #expect(vm.showsDeniedState == true)
    }

    /// PERM-3c: restricted behaves like denied for the gating + Settings path.
    @Test func perm3c_restrictedShowsDeniedState() {
        let permission = FakeCameraPermission(status: .restricted)
        let vm = makeViewModel(permission: permission)

        vm.setRecordingEnabled(true)

        #expect(vm.recordingEnabled == false)
        #expect(vm.showsDeniedState == true)
    }

    /// PERM-3d: "Open Settings" invokes the injected hook.
    @Test func perm3d_openSettingsInvokesHook() {
        let vm = makeViewModel(permission: FakeCameraPermission(status: .denied))
        var opened = 0
        vm.onOpenSystemSettings = { opened += 1 }

        vm.openSystemSettings()

        #expect(opened == 1)
    }

    // MARK: - PERM-4: revoke mid-session + returning from Settings

    /// PERM-4: revoking access while recording is on turns the stored flag off
    /// and updates the status without a restart.
    @Test func perm4_revokeWhileRecordingTurnsOff() {
        let permission = FakeCameraPermission(status: .authorized)
        let store = InMemoryRearCameraSettingsStore(
            settings: RearCameraSettings(recordingEnabled: true)
        )
        let vm = makeViewModel(permission: permission, store: store)
        #expect(vm.recordingEnabled == true)

        permission.changeStatus(.denied)

        #expect(vm.permissionStatus == .denied)
        #expect(vm.recordingEnabled == false)
        #expect(vm.showsDeniedState == true)
    }

    /// PERM-4b: granting access from Settings (while off) updates the status; the
    /// rider can then enable without a fresh prompt.
    @Test func perm4b_grantFromSettingsUpdatesStatus() {
        let permission = FakeCameraPermission(status: .denied)
        let vm = makeViewModel(permission: permission)

        permission.changeStatus(.authorized)
        #expect(vm.permissionStatus == .authorized)
        #expect(vm.showsDeniedState == false)

        vm.setRecordingEnabled(true)
        #expect(vm.recordingEnabled == true)
    }

    // MARK: - Persistence + settings rows

    /// Enabling recording persists to the store and reloads across instances.
    @Test func recordingChoicePersistsAcrossInstances() {
        let permission = FakeCameraPermission(status: .authorized)
        let store = InMemoryRearCameraSettingsStore()
        let first = makeViewModel(permission: permission, store: store)

        first.setRecordingEnabled(true)

        let second = makeViewModel(
            permission: FakeCameraPermission(status: .authorized),
            store: store
        )
        #expect(second.recordingEnabled == true)
    }

    /// Camera position, quality, and ride mode persist.
    @Test func cameraPositionQualityRideModePersist() {
        let store = InMemoryRearCameraSettingsStore()
        let vm = makeViewModel(store: store)

        vm.setCameraPosition(.front)
        vm.setQuality(.efficient)
        vm.setRideModeEnabled(false)

        let reloaded = store.load()
        #expect(reloaded.cameraPosition == .front)
        #expect(reloaded.quality == .efficient)
        #expect(reloaded.rideModeEnabled == false)
    }

    /// Defaults match the spec: recording off, back camera, Standard, ride mode
    /// on, 10-minute buffer.
    @Test func defaultsMatchSpec() {
        let vm = makeViewModel()
        #expect(vm.settings.recordingEnabled == false)
        #expect(vm.settings.cameraPosition == .back)
        #expect(vm.settings.quality == .standard)
        #expect(vm.settings.rideModeEnabled == true)
        #expect(vm.settings.bufferLengthSeconds == 10 * 60)
    }

    /// The buffer length clamps to the tuning range.
    @Test func bufferLengthClampsToRange() {
        let tuning = RideCameraTuning()
        let vm = makeViewModel()

        vm.setBufferLengthSeconds(1) // below min
        #expect(vm.settings.bufferLengthSeconds == tuning.ringMaxDurationRange.lowerBound)

        vm.setBufferLengthSeconds(60 * 60) // above max
        #expect(vm.settings.bufferLengthSeconds == tuning.ringMaxDurationRange.upperBound)

        vm.setBufferLengthSeconds(5 * 60) // in range
        #expect(vm.settings.bufferLengthSeconds == 5 * 60)
    }

    /// Storage used reads the clip repository's total bytes.
    @Test func storageUsedReadsClipRepository() throws {
        let rideId = UUID()
        let clips = InMemoryClipRepository()
        let created = Date(timeIntervalSince1970: 0)
        try clips.save(
            ClipRecord(
                id: UUID(), rideId: rideId, reasons: [.manual], createdAt: created,
                start: created, end: created.addingTimeInterval(45),
                inOffset: 0, outOffset: 45, durationSeconds: 45, bytes: 1_234,
                thumbnailPath: nil, hasAudio: false, state: .saved, hasGap: false,
                eventRef: nil, expiresAt: created.addingTimeInterval(30 * 24 * 3600)
            )
        )
        let vm = makeViewModel(clips: clips)

        vm.refreshStorageUsed()

        #expect(vm.clipBytesUsed == 1_234)
    }
}
