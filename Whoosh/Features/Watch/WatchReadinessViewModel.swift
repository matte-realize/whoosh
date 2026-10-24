import Foundation
import Observation
import WhooshWire

/// Drives the phone's "Apple Watch" readiness screen (watch-companion task 22;
/// design "Readiness screen"; Requirement 3.1–3.10, 1.8, 13.3).
///
/// It reads the phone's facts from a `WatchConnectionProviding`, runs the pure
/// `WatchReadinessEvaluator` to produce the checklist, and maps each row's
/// status code to plain, honest copy (icon + text — never color alone). It also
/// owns the rider-initiated **test buzz** and **pattern previews** and tracks
/// whether the last test was felt, so the haptics row reflects reality and a
/// repeated miss surfaces troubleshooting.
///
/// Nothing here blocks a ride: the screen is informational. Haptics are a cue,
/// not a guarantee — the copy says so (privacy honesty rules).
@MainActor
@Observable
final class WatchReadinessViewModel {
    @ObservationIgnored private let connection: WatchConnectionProviding
    @ObservationIgnored private let evaluator: WatchReadinessEvaluator

    /// How many test buzzes in a row were reported "didn't feel it"; after a few
    /// the view shows troubleshooting (Requirement 3.3).
    private(set) var consecutiveMisses = 0
    /// `nil` = not tested yet; `true`/`false` = the last reported outcome.
    private(set) var lastHapticTestFelt: Bool?
    /// Set while a test buzz / preview send is in flight so the view can disable
    /// the buttons and show progress.
    private(set) var isSending = false
    /// A short, app-written status line after the last send (e.g. "Sent — did
    /// you feel it?" or "Couldn't reach your watch"). Never raw error text.
    private(set) var lastSendMessage: String?

    init(connection: WatchConnectionProviding, tuning: WatchTuning = WatchTuning()) {
        self.connection = connection
        self.evaluator = WatchReadinessEvaluator(tuning: tuning)
    }

    // MARK: - Facts

    var isPaired: Bool { connection.isPaired }
    var isWatchAppInstalled: Bool { connection.isWatchAppInstalled }
    var isReachable: Bool { connection.isReachable }

    /// The number of consecutive misses past which the view reveals the
    /// troubleshooting note (design: "after three misses").
    static let troubleshootThreshold = 3
    var showsTroubleshooting: Bool { consecutiveMisses >= Self.troubleshootThreshold }

    /// True only when a watch is paired and the app is installed — the test-buzz
    /// and pattern previews are meaningful (otherwise the install steps show).
    var canTestHaptics: Bool { isPaired && isWatchAppInstalled }

    // MARK: - Lifecycle

    func onAppear() {
        connection.refresh()
        Task { await connection.activate() }
    }

    // MARK: - Checklist

    /// A display row: an SF Symbol, a title, a short detail, and an overall tone
    /// so the view renders icon + text with a consistent treatment.
    struct DisplayRow: Identifiable, Equatable {
        enum Tone { case pass, warn, info }
        var id: String { title }
        var systemImage: String
        var title: String
        var detail: String
        var tone: Tone
    }

    /// The curated checklist shown on the screen. The evaluator returns every
    /// row; the demo surfaces the ones a rider acts on (paired, installed, link,
    /// haptics test, audio fallback) with honest copy.
    var rows: [DisplayRow] {
        let items = evaluator.evaluate(
            .init(
                linkState: connection.linkState,
                watch: nil,
                armed: false,
                lastHapticTestFelt: lastHapticTestFelt
            )
        )
        let shown: [WatchReadinessEvaluator.Row] = [
            .watchPaired, .appInstalled, .link, .hapticsTest, .audioFallback,
        ]
        return items
            .filter { shown.contains($0.row) }
            .map(displayRow(for:))
    }

    private func displayRow(for item: WatchReadinessEvaluator.Item) -> DisplayRow {
        let tone: DisplayRow.Tone
        switch item.status {
        case .pass: tone = .pass
        case .warn: tone = .warn
        case .info: tone = .info
        }
        return DisplayRow(
            systemImage: icon(for: item.row, tone: tone),
            title: title(for: item.row),
            detail: detail(for: item),
            tone: tone
        )
    }

    private func icon(for row: WatchReadinessEvaluator.Row, tone: DisplayRow.Tone) -> String {
        switch tone {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info:
            switch row {
            case .watchPaired, .appInstalled: return "applewatch"
            case .hapticsTest: return "hand.tap.fill"
            case .audioFallback: return "speaker.wave.2.fill"
            default: return "info.circle"
            }
        }
    }

    private func title(for row: WatchReadinessEvaluator.Row) -> String {
        switch row {
        case .watchPaired: return "Apple Watch paired"
        case .appInstalled: return "Whoosh app on your watch"
        case .link: return "Connection"
        case .hapticsTest: return "Wrist buzz"
        case .audioFallback: return "Audio backup"
        default: return "Watch"
        }
    }

    private func detail(for item: WatchReadinessEvaluator.Item) -> String {
        switch item.status {
        case .pass:
            switch item.row {
            case .watchPaired: return "A watch is paired with this iPhone."
            case .appInstalled: return "The Whoosh watch app is installed."
            case .link: return "Your watch is connected and ready."
            case .hapticsTest: return "You felt the last test buzz."
            default: return "Ready."
            }
        case let .warn(code), let .info(code):
            return Self.copy(for: code)
        }
    }

    /// Map a status code from the evaluator (or a locally derived one) to plain
    /// copy. Honest: a cue is never promised to be felt.
    static func copy(for code: String) -> String {
        switch code {
        case "pairInstructions":
            return "Pair an Apple Watch with this iPhone in the Watch app to use wrist buzzes."
        case "installInstructions":
            return "Install the Whoosh watch app from the Watch app, or build the WhooshWatch scheme to your watch."
        case "openWhooshOnWatch":
            return "Open Whoosh on your watch so it can connect."
        case "linkNotReady":
            return "Your watch isn't connected yet. Open Whoosh on the watch and keep it nearby."
        case "updateWhoosh":
            return "Update Whoosh on both devices so they can talk."
        case "noTestYet":
            return "Tap Buzz my watch to feel a test cue. A buzz is a cue, not a guarantee."
        case "retryHapticTest":
            return "You said you didn't feel it. Try again, or check your watch isn't muted or low on battery."
        case "audioFallbackAlways":
            return "If the watch can't buzz, Whoosh plays an audio cue on your phone instead."
        default:
            return "Keep your watch nearby with Whoosh open."
        }
    }

    // MARK: - Pattern previews (Feel the patterns)

    /// One previewable haptic pattern: a short code (the wire pattern name) and
    /// a rider-facing label.
    struct PatternPreview: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var label: String
    }

    /// The patterns a rider can feel. Uses the public safety-critical catalog so
    /// a preview feels exactly like the real cue (never starts a countdown). The
    /// catalog is `[crashCountdownStart, rearLevel1, cameraStopped]`; we label
    /// each by its wire pattern name.
    var patterns: [PatternPreview] {
        HapticPatternSelector.safetyCritical.map { pattern in
            PatternPreview(name: pattern.name, label: Self.label(forPattern: pattern.name))
        }
    }

    private static func label(forPattern name: String) -> String {
        switch name {
        case "rearLevel1", "rearLevel2": return "Vehicle behind you"
        case "cameraStopped": return "Camera stopped"
        case "crashCountdownStart": return "Crash countdown"
        default: return "Ride cue"
        }
    }

    // MARK: - Intents

    /// Send a test buzz to the wrist. On success the haptics row becomes
    /// "did you feel it?"; a failure explains the watch couldn't be reached.
    func buzzMyWatch() async {
        await perform { await connection.sendTestBuzz() }
    }

    /// Preview one named catalog pattern on the wrist. Never starts a countdown.
    func previewPattern(_ preview: PatternPreview) async {
        await perform { await connection.sendPatternPreview(named: preview.name) }
    }

    /// The rider reports whether they felt the last test buzz (Requirement 3.3).
    func reportFelt(_ felt: Bool) {
        lastHapticTestFelt = felt
        if felt {
            consecutiveMisses = 0
            lastSendMessage = "Great — your watch buzzes are working."
        } else {
            consecutiveMisses += 1
            lastSendMessage = "No buzz felt. A watch may be muted, asleep, or low on battery."
        }
    }

    private func perform(_ send: () async -> Bool) async {
        guard !isSending else { return }
        isSending = true
        lastSendMessage = nil
        let ok = await send()
        isSending = false
        lastSendMessage = ok
            ? "Sent to your watch — did you feel it?"
            : "Couldn't reach your watch. Open Whoosh on the watch and keep it nearby."
    }
}
