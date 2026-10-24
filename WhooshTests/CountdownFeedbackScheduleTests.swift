import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `CountdownFeedbackSchedule` (task 19): which second gets a
/// tone, a haptic, a spoken final warning, or a periodic milestone. The
/// framework-touching `SystemCountdownFeedback` is only construction-tested
/// (its audio/speech/haptic behaviour is verified on device, task 27).
struct CountdownFeedbackScheduleTests {

    @Test func tonePlaysInLastTenSeconds() {
        let schedule = CountdownFeedbackSchedule(totalSeconds: 30)
        #expect(!schedule.shouldPlayTone(remaining: 11))
        #expect(schedule.shouldPlayTone(remaining: 10))
        #expect(schedule.shouldPlayTone(remaining: 1))
        #expect(!schedule.shouldPlayTone(remaining: 0))
    }

    @Test func hapticFiresEverySecond() {
        let schedule = CountdownFeedbackSchedule(totalSeconds: 30)
        #expect(schedule.shouldFireHaptic(remaining: 30))
        #expect(schedule.shouldFireHaptic(remaining: 1))
        #expect(!schedule.shouldFireHaptic(remaining: 0))
    }

    @Test func finalWarningSpokenInLastFiveSeconds() {
        let schedule = CountdownFeedbackSchedule(totalSeconds: 30)
        #expect(!schedule.shouldSpeakFinalWarning(remaining: 6))
        #expect(schedule.shouldSpeakFinalWarning(remaining: 5))
        #expect(schedule.shouldSpeakFinalWarning(remaining: 1))
        #expect(!schedule.shouldSpeakFinalWarning(remaining: 0))
    }

    @Test func milestonesEveryTenSecondsExcludingStartAndFinalBand() {
        let schedule = CountdownFeedbackSchedule(totalSeconds: 30)
        // Start (30) is the opening prompt, not a milestone.
        #expect(!schedule.shouldAnnounceMilestone(remaining: 30))
        #expect(schedule.shouldAnnounceMilestone(remaining: 20))
        #expect(schedule.shouldAnnounceMilestone(remaining: 10))
        // 5 and below belong to the final-warning band.
        #expect(!schedule.shouldAnnounceMilestone(remaining: 5))
        #expect(!schedule.shouldAnnounceMilestone(remaining: 15))
        #expect(!schedule.shouldAnnounceMilestone(remaining: 0))
    }

    @Test func noMilestoneAtOrAboveTotal() {
        let schedule = CountdownFeedbackSchedule(totalSeconds: 60)
        #expect(!schedule.shouldAnnounceMilestone(remaining: 60))
        #expect(schedule.shouldAnnounceMilestone(remaining: 50))
    }

    @Test func minimumCountdownScheduleIsConsistent() {
        let schedule = CountdownFeedbackSchedule(totalSeconds: 15)
        #expect(schedule.shouldPlayTone(remaining: 10))
        #expect(schedule.shouldAnnounceMilestone(remaining: 10))
        #expect(!schedule.shouldAnnounceMilestone(remaining: 15))
    }

    @MainActor
    @Test func systemCountdownFeedbackConstructs() {
        // Only construction is asserted; device check (task 27) covers behaviour.
        let feedback = SystemCountdownFeedback()
        feedback.end(reason: .cancelled) // idempotent end before begin is safe
    }
}
