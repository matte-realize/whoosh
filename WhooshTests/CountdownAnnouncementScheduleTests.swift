import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `CountdownAnnouncementSchedule` (crash-response task 20):
/// VoiceOver announcements fire at the start, every 10 s, and in the last 5 s,
/// with honest phrasing. No framework/accessibility APIs are exercised here.
struct CountdownAnnouncementScheduleTests {

    @Test func announcesAtStart() {
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 30)
        #expect(schedule.shouldAnnounce(remaining: 30))
        #expect(schedule.announcement(remaining: 30)?.contains("Sending an alert in 30 seconds") == true)
        #expect(schedule.announcement(remaining: 30)?.contains("I'm OK") == true)
    }

    @Test func announcesEveryTenSecondsInterior() {
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 30)
        #expect(schedule.shouldAnnounce(remaining: 20))
        #expect(schedule.shouldAnnounce(remaining: 10))
        // Not at non-multiples outside the final band.
        #expect(!schedule.shouldAnnounce(remaining: 25))
        #expect(!schedule.shouldAnnounce(remaining: 15))
        #expect(schedule.announcement(remaining: 20) == "20 seconds until the alert is sent.")
    }

    @Test func announcesEachOfTheLastFiveSeconds() {
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 30)
        for remaining in 1...5 {
            #expect(schedule.shouldAnnounce(remaining: remaining))
        }
        #expect(!schedule.shouldAnnounce(remaining: 6))
        #expect(schedule.announcement(remaining: 5) == "5 seconds")
        #expect(schedule.announcement(remaining: 1) == "1 second")
    }

    @Test func noAnnouncementAtZeroOrBelow() {
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 30)
        #expect(!schedule.shouldAnnounce(remaining: 0))
        #expect(schedule.announcement(remaining: 0) == nil)
        #expect(!schedule.shouldAnnounce(remaining: -3))
    }

    @Test func tenMarkInsideFinalBandIsNotDuplicatedOrDropped() {
        // A 10-second countdown: start at 10, then the 1...5 band. The "10" mark
        // is the start; there is no interior 10-mark to double up.
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 10)
        #expect(schedule.shouldAnnounce(remaining: 10))          // start
        #expect(schedule.announcement(remaining: 10)?.contains("Sending an alert in 10 seconds") == true)
        #expect(!schedule.shouldAnnounce(remaining: 9))
        #expect(schedule.shouldAnnounce(remaining: 5))           // final band
    }

    @Test func minimumFifteenSecondCountdown() {
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 15)
        #expect(schedule.shouldAnnounce(remaining: 15))   // start
        #expect(schedule.shouldAnnounce(remaining: 10))   // interior 10-mark
        #expect(!schedule.shouldAnnounce(remaining: 14))
        #expect(schedule.shouldAnnounce(remaining: 5))    // final band
    }

    @Test func maximumSixtySecondCountdown() {
        let schedule = CountdownAnnouncementSchedule(totalSeconds: 60)
        #expect(schedule.shouldAnnounce(remaining: 60))   // start
        #expect(schedule.shouldAnnounce(remaining: 50))
        #expect(schedule.shouldAnnounce(remaining: 20))
        #expect(schedule.shouldAnnounce(remaining: 10))
        #expect(!schedule.shouldAnnounce(remaining: 55))
    }
}
