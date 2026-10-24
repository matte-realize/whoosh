import Foundation
import Testing
@testable import Whoosh

/// Golden tests for `CrashMessageBuilder` (spec task 4, Requirements 10.1–10.9,
/// 12.9, 17.4). The golden strings G1–G9 are copied **verbatim** from the
/// backend contract Appendix A.2 and are the single source of truth shared with
/// the backend renderer. Appendix A.3 adds derived boundary cases.
///
/// All asserts use exact string equality; every output is additionally checked
/// to contain no non-GSM-7 character.
struct CrashMessageBuilderTests {
    // Fixed detection instant for G1–G4, G6, G9: 2026-10-24T17:41:07Z.
    private static let g1Detected = Date(timeIntervalSince1970: 1_792_863_667)
    // Worst-case instant for G5: 2026-12-28T18:29:00Z.
    private static let g5Detected = Date(timeIntervalSince1970: 1_798_482_540)

    /// Convenience to build a `current`/`last_known` snapshot with explicit age.
    private static func snapshot(
        status: LocationFixStatus,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        ageSeconds: TimeInterval,
        now: Date
    ) -> LocationSnapshot {
        LocationSnapshot(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: accuracy,
            fixTime: now.addingTimeInterval(-ageSeconds),
            status: status
        )
    }

    // MARK: - Golden cases G1–G9 (verbatim from contract Appendix A.2)

    @Test func g1_crashAlert_currentFix() {
        let loc = Self.snapshot(status: .current, latitude: 42.36012, longitude: -71.05888,
                                accuracy: 12, ageSeconds: 0, now: Self.g1Detected)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: loc,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = """
        WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
        Time: Sat Oct 24, 1:41 PM (UTC-4)
        Location (+/-12 m):
        Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
        Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
        Please try to reach them. If you can't, consider calling emergency services.
        Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
        """
        #expect(result.text == expected)
        #expect(result.characterCount == 465)
        #expect(result.segmentCount == 4)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g2_crashAlert_lastKnown() {
        let loc = Self.snapshot(status: .lastKnown, latitude: 42.36012, longitude: -71.05888,
                                accuracy: 30, ageSeconds: 45, now: Self.g1Detected)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: loc,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = """
        WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
        Time: Sat Oct 24, 1:41 PM (UTC-4)
        Last known location (45 s old, +/-30 m):
        Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
        Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
        Please try to reach them. If you can't, consider calling emergency services.
        Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
        """
        #expect(result.text == expected)
        #expect(result.characterCount == 486)
        #expect(result.segmentCount == 4)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g3_crashAlert_locationUnavailable() {
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: .unavailable,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = """
        WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
        Time: Sat Oct 24, 1:41 PM (UTC-4)
        Location unavailable.
        Please try to reach them. If you can't, consider calling emergency services.
        Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
        """
        #expect(result.text == expected)
        #expect(result.characterCount == 321)
        #expect(result.segmentCount == 3)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g4_crashAlert_delayed() {
        let loc = Self.snapshot(status: .lastKnown, latitude: 42.36012, longitude: -71.05888,
                                accuracy: 30, ageSeconds: 45, now: Self.g1Detected)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: loc,
            delayedSeconds: 1020,
            now: Self.g1Detected
        )
        let expected = """
        WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
        Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 17 min.
        Last known location (45 s old, +/-30 m):
        Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
        Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
        Please try to reach them. If you can't, consider calling emergency services.
        Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
        """
        #expect(result.text == expected)
        #expect(result.characterCount == 514)
        #expect(result.segmentCount == 4)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g5_worstCase() {
        let loc = Self.snapshot(status: .lastKnown, latitude: -42.36012, longitude: -171.05888,
                                accuracy: 499, ageSeconds: 540, now: Self.g5Detected)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Abcdefghij Klmnopqrs",
            detectedAt: Self.g5Detected,
            utcOffsetMinutes: 330,
            location: loc,
            delayedSeconds: 1740,
            now: Self.g5Detected
        )
        let expected = """
        WHOOSH ALERT: Abcdefghij Klmnopqrs may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
        Time: Mon Dec 28, 11:59 PM (UTC+5:30). Message delayed by 29 min.
        Last known location (9 min old, +/-499 m):
        Apple Maps: https://maps.apple.com/?ll=-42.36012,-171.05888&q=Rider
        Google Maps: https://www.google.com/maps/search/?api=1&query=-42.36012,-171.05888
        Please try to reach them. If you can't, consider calling emergency services.
        Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
        """
        #expect(result.text == expected)
        #expect(result.characterCount == 540)
        #expect(result.segmentCount == 4)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g6_drill() {
        let loc = Self.snapshot(status: .current, latitude: 42.36012, longitude: -71.05888,
                                accuracy: 12, ageSeconds: 0, now: Self.g1Detected)
        let result = CrashMessageBuilder.build(
            kind: .drill,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: loc,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = """
        WHOOSH DEMO - NOT REAL: Alex is demonstrating Whoosh crash alerts. No crash happened.
        Time: Sat Oct 24, 1:41 PM (UTC-4)
        Location (+/-12 m):
        Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
        Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
        Sent by Whoosh, not an emergency service. Reply STOP to opt out.
        """
        #expect(result.text == expected)
        #expect(result.characterCount == 350)
        #expect(result.segmentCount == 3)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g7_test() {
        let result = CrashMessageBuilder.build(
            kind: .test,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: nil,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = "WHOOSH TEST: This is a test message from Alex. No crash happened. A real alert would include the time and location. Sent by Whoosh, not an emergency service. Reply STOP to opt out."
        #expect(result.text == expected)
        #expect(result.characterCount == 180)
        #expect(result.segmentCount == 2)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g8_intro() {
        let result = CrashMessageBuilder.build(
            kind: .intro,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: nil,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = "WHOOSH: Alex added you as an emergency contact in the Whoosh cycling app. If their phone detects a possible crash, you may get a text like this. Nothing to do now. Reply STOP to opt out."
        #expect(result.text == expected)
        #expect(result.characterCount == 186)
        #expect(result.segmentCount == 2)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func g9_allClear() {
        let result = CrashMessageBuilder.build(
            kind: .allClear,
            riderLabel: "Alex",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: nil,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        let expected = "WHOOSH UPDATE: Alex says they are OK. Please ignore the crash alert sent at Sat Oct 24, 1:41 PM (UTC-4). Sent by Whoosh, not an emergency service. Reply STOP to opt out."
        #expect(result.text == expected)
        #expect(result.characterCount == 169)
        #expect(result.segmentCount == 2)
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    // MARK: - A.3 Offset formatting

    @Test(arguments: [
        (-570, "UTC-9:30"),
        (-240, "UTC-4"),
        (0, "UTC+0"),
        (330, "UTC+5:30"),
        (345, "UTC+5:45"),
    ])
    func offsetFormatting(offsetMinutes: Int, expected: String) {
        #expect(CrashMessageBuilder.formatOffset(minutes: offsetMinutes) == expected)
    }

    // MARK: - A.3 Age formatting boundaries 0/9/10/11/59/60/119/3599/3600

    @Test(arguments: [
        (TimeInterval(0), "current"),
        (TimeInterval(9), "current"),
        (TimeInterval(10), "current"),
        (TimeInterval(11), "11 s old"),
        (TimeInterval(59), "59 s old"),
        (TimeInterval(60), "1 min old"),
        (TimeInterval(119), "1 min old"),
        (TimeInterval(3599), "59 min old"),
        (TimeInterval(3600), "1 h old"),
    ])
    func ageFormatting(ageSeconds: TimeInterval, expected: String) {
        // Age ≤ 10 s renders as a `current` fix (no age text); older renders the
        // last-known age string. We assert via the location-block builder.
        let status: LocationFixStatus = ageSeconds <= 10 ? .current : .lastKnown
        let now = Date(timeIntervalSince1970: 1_000_000)
        let loc = Self.snapshot(status: status, latitude: 42.36012, longitude: -71.05888,
                                accuracy: 12, ageSeconds: ageSeconds, now: now)
        let block = CrashMessageBuilder.locationBlock(for: loc, now: now)
        if expected == "current" {
            #expect(block.hasPrefix("Location (+/-12 m):"))
        } else {
            #expect(block.hasPrefix("Last known location (\(expected), +/-12 m):"))
        }
    }

    // MARK: - A.3 Delay clause boundaries 0/59/60/119/120

    @Test(arguments: [
        (TimeInterval(0), ""),
        (TimeInterval(59), ""),
        (TimeInterval(60), ". Message delayed by 1 min."),
        (TimeInterval(119), ". Message delayed by 1 min."),
        (TimeInterval(120), ". Message delayed by 2 min."),
    ])
    func delayClause(delayedSeconds: TimeInterval, expected: String) {
        #expect(CrashMessageBuilder.delayClause(delayedSeconds: delayedSeconds) == expected)
    }

    // MARK: - A.3 Accuracy rounding (nearest whole meter, minimum 1)

    @Test(arguments: [
        (0.0, 1),
        (0.4, 1),
        (0.6, 1),
        (1.0, 1),
        (11.5, 12),
        (29.4, 29),
        (499.0, 499),
    ])
    func accuracyRounding(input: Double, expected: Int) {
        #expect(CrashMessageBuilder.roundedAccuracy(input) == expected)
    }

    // MARK: - A.3 DST-adjacent dates (fixed English locale, offset arithmetic only)

    @Test func dstAdjacentSpringForward() {
        // 2026-03-08T06:45:00Z, offset -300 (EST) → Sun Mar 8, 1:45 AM.
        // The builder shifts by the given offset only; it never consults a
        // time zone database, so DST transitions do not affect the output.
        let detected = Date(timeIntervalSince1970: 1_772_952_300)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: detected,
            utcOffsetMinutes: -300,
            location: .unavailable,
            delayedSeconds: 0,
            now: detected
        )
        #expect(result.text.contains("Time: Sun Mar 8, 1:45 AM (UTC-5)"))
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func dstAdjacentFallBack() {
        // 2026-11-01T05:30:00Z, offset -240 (EDT) → Sun Nov 1, 1:30 AM.
        let detected = Date(timeIntervalSince1970: 1_793_511_000)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: detected,
            utcOffsetMinutes: -240,
            location: .unavailable,
            delayedSeconds: 0,
            now: detected
        )
        #expect(result.text.contains("Time: Sun Nov 1, 1:30 AM (UTC-4)"))
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    // MARK: - Midnight / noon 12-hour formatting

    @Test func midnightFormatsAs12AM() {
        // 2026-10-24T04:00:00Z, offset -240 → Sat Oct 24, 12:00 AM.
        let detected = Date(timeIntervalSince1970: 1_792_814_400)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert, riderLabel: "Alex", detectedAt: detected,
            utcOffsetMinutes: -240, location: .unavailable, delayedSeconds: 0, now: detected
        )
        #expect(result.text.contains("Time: Sat Oct 24, 12:00 AM (UTC-4)"))
    }

    @Test func noonFormatsAs12PM() {
        // 2026-10-24T16:00:00Z, offset -240 → Sat Oct 24, 12:00 PM.
        let detected = Date(timeIntervalSince1970: 1_792_857_600)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert, riderLabel: "Alex", detectedAt: detected,
            utcOffsetMinutes: -240, location: .unavailable, delayedSeconds: 0, now: detected
        )
        #expect(result.text.contains("Time: Sat Oct 24, 12:00 PM (UTC-4)"))
    }

    // MARK: - A.3 Cap fallback: a render > 612 chars drops the Google Maps line

    @Test func capFallbackDropsGoogleMapsLine() {
        // With valid inputs (20-char label, 5-decimal coordinates) the templates
        // stay well under 612 chars — the worst golden case is 540 — so the cap
        // path is a defensive safety net. Exercise it directly with a synthetic
        // over-length rendering to prove the Google Maps line is dropped first.
        let apple = "Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider"
        let google = "Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888"
        let padding = String(repeating: "A", count: 600)
        let overLength = "\(padding)\n\(apple)\n\(google)"
        #expect(overLength.count > CrashMessageBuilder.characterCap)

        let capped = CrashMessageBuilder.applyCap(to: overLength)
        #expect(!capped.contains("Google Maps:"))
        #expect(capped.contains("Apple Maps:"))
        #expect(GSM7Sanitizer.isGSM7(capped))
    }

    @Test func worstCaseValidInputStaysUnderCap() {
        // The longest valid render: 20-char label, last-known block, delay
        // clause, half-hour-and-quarter offset, large age/accuracy.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let loc = Self.snapshot(status: .lastKnown, latitude: -42.36012, longitude: -171.05888,
                                accuracy: 9999, ageSeconds: 86_400, now: now)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Abcdefghij Klmnopqrs",
            detectedAt: now,
            utcOffsetMinutes: 345,
            location: loc,
            delayedSeconds: 86_400,
            now: now
        )
        #expect(result.characterCount <= CrashMessageBuilder.characterCap)
        #expect(result.segmentCount <= 4)
        // Under the cap, both links are kept.
        #expect(result.text.contains("Apple Maps:"))
        #expect(result.text.contains("Google Maps:"))
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }

    @Test func withinCapKeepsBothLinks() {
        // G1 is comfortably within the cap and must keep both links.
        let loc = Self.snapshot(status: .current, latitude: 42.36012, longitude: -71.05888,
                                accuracy: 12, ageSeconds: 0, now: Self.g1Detected)
        let result = CrashMessageBuilder.build(
            kind: .crashAlert, riderLabel: "Alex", detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240, location: loc, delayedSeconds: 0, now: Self.g1Detected
        )
        #expect(result.text.contains("Apple Maps:"))
        #expect(result.text.contains("Google Maps:"))
    }

    // MARK: - Segment counting rule (≤160 ⇒ 1, else ceil(n/153))

    @Test(arguments: [
        (1, 1),
        (160, 1),
        (161, 2),
        (306, 2),
        (307, 3),
        (459, 3),
        (460, 4),
        (612, 4),
    ])
    func segmentCounting(length: Int, expected: Int) {
        #expect(CrashMessageBuilder.segmentCount(forLength: length) == expected)
    }

    // MARK: - Label sanitization is applied before rendering

    @Test func labelIsSanitizedIntoMessage() {
        // A curly apostrophe and a non-ASCII letter are sanitized by the
        // builder (via GSM7Sanitizer.riderLabel) before rendering.
        let result = CrashMessageBuilder.build(
            kind: .test,
            riderLabel: "O\u{2019}Brien\u{00A0}\u{1F600}",
            detectedAt: Self.g1Detected,
            utcOffsetMinutes: -240,
            location: nil,
            delayedSeconds: 0,
            now: Self.g1Detected
        )
        #expect(result.text.contains("from O'Brien."))
        #expect(GSM7Sanitizer.isGSM7(result.text))
    }
}
