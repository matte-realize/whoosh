import Foundation

/// The rendered output of `CrashMessageBuilder`: the GSM-7 message text, its
/// character count, and the SMS segment count (spec Requirement 10).
struct CrashMessage: Equatable, Sendable {
    let text: String
    let characterCount: Int
    let segmentCount: Int
}

/// Pure, Foundation-only builder for the fixed crash-alert SMS templates
/// (spec task 4, `design.md` "Message template", contract Appendix A).
///
/// The contract's Appendix A golden strings are the single source of truth
/// shared with the backend renderer; any wording change bumps `templateVersion`
/// in both places. The builder:
/// - renders the five kinds (`crash_alert`, `drill`, `test`, `intro`,
///   `all_clear`);
/// - formats the local time with a fixed, locale-independent English calendar
///   (12-hour clock, fixed day/month abbreviations) by shifting the detection
///   instant by `utcOffsetMinutes` only — it never consults a time-zone
///   database, so DST transitions do not affect output;
/// - renders the three location-block variants (current / last known / none);
/// - appends the delay clause when `delayedSeconds >= 60`;
/// - returns the character count and SMS segment count;
/// - drops the Google Maps line first if the rendering exceeds the 612-char cap;
/// - restricts the rider label to the GSM-7-safe charset via `GSM7Sanitizer`.
///
/// The builder carries no free text other than the sanitized rider label and no
/// footage, matching the backend's "no open relay" rule.
enum CrashMessageBuilder {
    /// The message template version shared with the backend contract
    /// (Appendix A, `templateVersion` currently 1). A wording change bumps this
    /// in both the app and the contract appendix in the same PR window.
    static let templateVersion = 1

    /// Build the full message for `kind`.
    ///
    /// - Parameters:
    ///   - kind: which template to render.
    ///   - riderLabel: the rider's chosen label (sanitized here).
    ///   - detectedAt: the detection instant (UTC).
    ///   - utcOffsetMinutes: the rider's local UTC offset in minutes.
    ///   - location: the location snapshot for `crash_alert`/`drill`; ignored
    ///     for `test`/`intro`/`all_clear` (pass `nil`).
    ///   - delayedSeconds: how long the send was delayed; a clause is added at
    ///     >= 60 s.
    ///   - now: the current instant, used to derive a snapshot's age.
    static func build(
        kind: CrashMessageKind,
        riderLabel: String,
        detectedAt: Date,
        utcOffsetMinutes: Int,
        location: LocationSnapshot?,
        delayedSeconds: TimeInterval,
        now: Date
    ) -> CrashMessage {
        let label = GSM7Sanitizer.riderLabel(riderLabel)
        let timeString = formatTime(detectedAt, utcOffsetMinutes: utcOffsetMinutes)

        let text: String
        switch kind {
        case .crashAlert, .drill:
            text = buildLocated(
                kind: kind,
                label: label,
                timeString: timeString,
                location: location ?? .unavailable,
                delayedSeconds: delayedSeconds,
                now: now
            )
        case .test:
            text = "WHOOSH TEST: This is a test message from \(label). No crash happened. A real alert would include the time and location. Sent by Whoosh, not an emergency service. Reply STOP to opt out."
        case .intro:
            text = "WHOOSH: \(label) added you as an emergency contact in the Whoosh cycling app. If their phone detects a possible crash, you may get a text like this. Nothing to do now. Reply STOP to opt out."
        case .allClear:
            text = "WHOOSH UPDATE: \(label) says they are OK. Please ignore the crash alert sent at \(timeString). Sent by Whoosh, not an emergency service. Reply STOP to opt out."
        }

        return finalize(text)
    }

    // MARK: - Located templates (crash_alert / drill)

    private static func buildLocated(
        kind: CrashMessageKind,
        label: String,
        timeString: String,
        location: LocationSnapshot,
        delayedSeconds: TimeInterval,
        now: Date
    ) -> String {
        let header: String
        let footer: String
        switch kind {
        case .drill:
            header = "WHOOSH DEMO - NOT REAL: \(label) is demonstrating Whoosh crash alerts. No crash happened."
            footer = "Sent by Whoosh, not an emergency service. Reply STOP to opt out."
        default: // .crashAlert
            header = "WHOOSH ALERT: \(label) may have crashed while cycling. A crash was detected but an injury has NOT been confirmed."
            footer = "Please try to reach them. If you can't, consider calling emergency services.\nSent automatically by Whoosh, not an emergency service. Reply STOP to opt out."
        }

        let timeLine = "Time: \(timeString)\(delayClause(delayedSeconds: delayedSeconds))"
        let block = locationBlock(for: location, now: now)

        return "\(header)\n\(timeLine)\n\(block)\n\(footer)"
    }

    // MARK: - Location block

    /// Render the location block for a snapshot: the `current` variant (header
    /// plus the two map links), the `last_known` variant (header with age and
    /// accuracy plus links), or `Location unavailable.`
    static func locationBlock(for location: LocationSnapshot, now: Date) -> String {
        guard location.status != .unavailable,
              let latitude = location.latitude,
              let longitude = location.longitude else {
            return "Location unavailable."
        }

        let accuracy = roundedAccuracy(location.horizontalAccuracy ?? 0)
        let latString = formatCoordinate(latitude)
        let lonString = formatCoordinate(longitude)
        let links = mapLinks(latString: latString, lonString: lonString)

        switch location.status {
        case .current:
            return "Location (+/-\(accuracy) m):\n\(links)"
        case .lastKnown:
            let age = location.age(at: now) ?? 0
            return "Last known location (\(formatAge(age)), +/-\(accuracy) m):\n\(links)"
        case .unavailable:
            return "Location unavailable."
        }
    }

    private static func mapLinks(latString: String, lonString: String) -> String {
        let apple = "Apple Maps: https://maps.apple.com/?ll=\(latString),\(lonString)&q=Rider"
        let google = "Google Maps: https://www.google.com/maps/search/?api=1&query=\(latString),\(lonString)"
        return "\(apple)\n\(google)"
    }

    // MARK: - Length cap and segment counting

    /// The hard character cap (4 GSM-7 segments). Mirrors
    /// `CrashResponseTuning.messageCharacterCap`.
    static let characterCap = 612

    /// Finalize text: enforce the character cap, then compute character and
    /// segment counts.
    private static func finalize(_ text: String) -> CrashMessage {
        let capped = applyCap(to: text)
        let count = capped.count
        return CrashMessage(text: capped, characterCount: count, segmentCount: segmentCount(forLength: count))
    }

    /// Enforce the 612-character cap by dropping the `Google Maps:` line first
    /// (the longest droppable line). With valid inputs the templates stay well
    /// under the cap (worst golden case is 540); this is a defensive safety net
    /// and a parity point with the backend renderer.
    static func applyCap(to text: String) -> String {
        guard text.count > characterCap else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("Google Maps:") }
        return lines.joined(separator: "\n")
    }

    /// SMS segment count: `<= 160 ⇒ 1`, otherwise `ceil(n / 153)` (the
    /// concatenated-SMS rule used by the contract's counts).
    static func segmentCount(forLength length: Int) -> Int {
        guard length > 160 else { return 1 }
        return Int((Double(length) / 153.0).rounded(.up))
    }

    // MARK: - Time, offset, delay, age, accuracy, coordinate formatting

    private static let weekdayAbbreviations = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// A fixed, locale-independent calendar: Gregorian, UTC, Sunday-first.
    /// Local time is produced by shifting the detection instant by the offset,
    /// then reading its UTC components — so the output never depends on the
    /// device locale or a time-zone database.
    private static var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") {
            calendar.timeZone = utc
        }
        calendar.firstWeekday = 1
        return calendar
    }

    /// Format the local detection time: `Sat Oct 24, 1:41 PM (UTC-4)`.
    static func formatTime(_ detectedAt: Date, utcOffsetMinutes: Int) -> String {
        let shifted = detectedAt.addingTimeInterval(TimeInterval(utcOffsetMinutes * 60))
        let calendar = fixedCalendar
        let components = calendar.dateComponents(
            [.weekday, .month, .day, .hour, .minute], from: shifted
        )

        let weekday = weekdayAbbreviations[(components.weekday ?? 1) - 1]
        let month = monthAbbreviations[(components.month ?? 1) - 1]
        let day = components.day ?? 1
        let (hour12, meridiem) = to12Hour(components.hour ?? 0)
        let minute = String(format: "%02d", components.minute ?? 0)

        return "\(weekday) \(month) \(day), \(hour12):\(minute) \(meridiem) (\(formatOffset(minutes: utcOffsetMinutes)))"
    }

    private static func to12Hour(_ hour24: Int) -> (Int, String) {
        let meridiem = hour24 < 12 ? "AM" : "PM"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return (hour12, meridiem)
    }

    /// Format a UTC offset: `UTC` + sign + hours, with `:mm` only when the
    /// minute part is non-zero. Examples: `UTC-4`, `UTC+5:30`, `UTC+0`.
    static func formatOffset(minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : "+"
        let absolute = abs(minutes)
        let hours = absolute / 60
        let mins = absolute % 60
        if mins == 0 {
            return "UTC\(sign)\(hours)"
        }
        return "UTC\(sign)\(hours):\(String(format: "%02d", mins))"
    }

    /// The delay clause appended to the Time line when `delayedSeconds >= 60`:
    /// `. Message delayed by N min.` where `N = floor(seconds / 60)`.
    static func delayClause(delayedSeconds: TimeInterval) -> String {
        let seconds = Int(delayedSeconds)
        guard seconds >= 60 else { return "" }
        let minutes = seconds / 60
        return ". Message delayed by \(minutes) min."
    }

    /// Format a fix age: `< 60 s ⇒ N s old`; `60–3599 s ⇒ N min old` (floor);
    /// `>= 3600 s ⇒ N h old` (floor).
    static func formatAge(_ ageSeconds: TimeInterval) -> String {
        let seconds = max(0, Int(ageSeconds))
        if seconds < 60 {
            return "\(seconds) s old"
        }
        if seconds < 3600 {
            return "\(seconds / 60) min old"
        }
        return "\(seconds / 3600) h old"
    }

    /// Round accuracy to the nearest whole meter, minimum 1.
    static func roundedAccuracy(_ meters: Double) -> Int {
        max(1, Int(meters.rounded()))
    }

    /// Format a coordinate to exactly 5 decimal places with a `.` separator and
    /// a leading `-` for negatives.
    static func formatCoordinate(_ value: Double) -> String {
        String(format: "%.5f", value)
    }
}
