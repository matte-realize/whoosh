import Foundation
import Testing
@testable import Whoosh

/// The phone's haptic/audio manager plays only the rear-vehicle caution.
/// Camera status notices are routed to the eyes-free surfaces elsewhere, so
/// they must neither buzz the phone nor use up the rear-vehicle cooldown.
@MainActor
struct HapticAudioAlertManagerTests {
    private final class RecordingHaptics: HapticPlaying {
        var cautionCount = 0
        func prepare() {}
        func playCaution() { cautionCount += 1 }
    }

    private final class RecordingTone: TonePlaying {
        var toneCount = 0
        func playCautionTone() { toneCount += 1 }
    }

    private func makeManager() -> (HapticAudioAlertManager, RecordingHaptics, RecordingTone) {
        let haptics = RecordingHaptics()
        let tone = RecordingTone()
        let manager = HapticAudioAlertManager(clock: TestClock(), haptics: haptics, tone: tone)
        return (manager, haptics, tone)
    }

    @Test func rearVehicleCautionPlaysHapticAndTone() {
        let (manager, haptics, tone) = makeManager()
        manager.fire(.cautionRearVehicle)
        #expect(haptics.cautionCount == 1)
        #expect(tone.toneCount == 1)
    }

    @Test(arguments: [
        AlertKind.cameraInterrupted,
        .cameraResumed,
        .clipSaved,
        .phoneBatteryLow,
    ])
    func cameraNoticesDoNotBuzzThePhone(kind: AlertKind) {
        let (manager, haptics, tone) = makeManager()
        manager.fire(kind)
        #expect(haptics.cautionCount == 0)
        #expect(tone.toneCount == 0)
    }

    @Test func aCameraNoticeDoesNotSwallowARearVehicleCautionRightAfter() {
        let (manager, haptics, _) = makeManager()
        manager.fire(.clipSaved)
        manager.fire(.cautionRearVehicle)
        #expect(haptics.cautionCount == 1)
    }
}
