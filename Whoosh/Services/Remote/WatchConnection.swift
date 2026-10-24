import Foundation
import Observation
import WhooshWire

/// The read-only + test-buzz seam the phone's "Apple Watch" readiness screen and
/// the pre-ride connect step observe (watch-companion task 22; design "Readiness
/// screen"; Requirement 3.1–3.10, 1.8, 13.3).
///
/// It exposes only **facts the phone already knows** — whether a watch is
/// paired, whether the Whoosh watch app is installed, and the current link state
/// — plus two rider-initiated sends (a test buzz and a haptic pattern preview)
/// that go over the existing device-to-device `WireLink`. It never touches the
/// network (the link is device to device) and never records or holds ride data.
///
/// The concrete `WatchConnection` is built in `Services/Remote/` so views and
/// view models never import `WatchConnectivity` (privacy rule 14); the paired /
/// installed facts are read inside the phone wire-link adapter and handed over
/// as plain closures, so this type imports only the Foundation-only wire
/// package.
@MainActor
protocol WatchConnectionProviding: AnyObject {
    /// Whether an Apple Watch is paired to this iPhone.
    var isPaired: Bool { get }
    /// Whether the Whoosh watch app is installed on the paired watch.
    var isWatchAppInstalled: Bool { get }
    /// Whether the watch app is reachable right now (foreground on the wrist).
    var isReachable: Bool { get }
    /// The link lifecycle state, used by `WatchReadinessEvaluator` to pick copy.
    var linkState: WireLinkState { get }

    /// Begin the link and start tracking reachability. Idempotent.
    func activate() async
    /// Re-read the paired / installed / reachable facts (e.g. on screen appear).
    func refresh()
    /// Send a one-shot test buzz to the wrist. Returns `true` when the send was
    /// accepted by the link (not a guarantee the wrist felt it — haptics are a
    /// cue, not a promise).
    @discardableResult
    func sendTestBuzz() async -> Bool
    /// Preview one catalog haptic pattern by its short code. Never starts a
    /// countdown or any ride action.
    @discardableResult
    func sendPatternPreview(named patternName: String) async -> Bool
}

/// The live `WatchConnectionProviding` over a device-to-device `WireLink`. It
/// imports only the wire package; the paired / installed facts come from the
/// injected closures the phone wire-link factory provides (the only place
/// allowed to read the watch connectivity session).
@MainActor
@Observable
final class WatchConnection: WatchConnectionProviding {
    @ObservationIgnored private let link: any WireLink
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let pairedFact: @MainActor () -> Bool
    @ObservationIgnored private let installedFact: @MainActor () -> Bool

    private(set) var isPaired: Bool
    private(set) var isWatchAppInstalled: Bool
    private(set) var isReachable: Bool = false

    init(
        link: any WireLink,
        clock: Clock,
        pairedFact: @escaping @MainActor () -> Bool,
        installedFact: @escaping @MainActor () -> Bool
    ) {
        self.link = link
        self.clock = clock
        self.pairedFact = pairedFact
        self.installedFact = installedFact
        self.isPaired = pairedFact()
        self.isWatchAppInstalled = installedFact()
    }

    /// Derive the link state the readiness evaluator consumes from the facts.
    /// Pairing/installation are phone-only facts; reachability maps the rest.
    var linkState: WireLinkState {
        if !isPaired { return .notPaired }
        if !isWatchAppInstalled { return .notInstalled }
        return isReachable ? .reachableHelloPending : .installedUnreachable
    }

    func activate() async {
        await link.onReachabilityChange { [weak self] reachable in
            Task { @MainActor in self?.isReachable = reachable }
        }
        await link.activate()
        isReachable = await link.isReachable
        refresh()
    }

    func refresh() {
        isPaired = pairedFact()
        isWatchAppInstalled = installedFact()
    }

    func sendTestBuzz() async -> Bool {
        await send(makeAlert(kind: .hapticTest, patternName: nil))
    }

    func sendPatternPreview(named patternName: String) async -> Bool {
        await send(makeAlert(kind: .patternPreview, patternName: patternName))
    }

    // MARK: - Private

    private func makeAlert(kind: WireAlertKind, patternName: String?) -> WireAlert {
        WireAlert(
            alertId: UUID().uuidString,
            kind: kind,
            tier: .notice,
            patternName: patternName,
            createdAgoMs: 0,
            ttlMs: 5_000
        )
    }

    private func send(_ alert: WireAlert) async -> Bool {
        let now = clock.now()
        guard let envelope = try? WireCodec.encode(
            alert, id: alert.alertId, seq: 0, sentAt: now.timeIntervalSince1970, ttlMs: alert.ttlMs
        ) else { return false }
        switch await link.send(envelope) {
        case .delivered, .queued: return true
        case .unreachable, .failed: return false
        }
    }
}

/// The inert connection used when no watch is usable and in previews/tests that
/// need a "no watch" world. Every fact is false; sends are no-ops.
@MainActor
final class NoopWatchConnection: WatchConnectionProviding {
    var isPaired: Bool { false }
    var isWatchAppInstalled: Bool { false }
    var isReachable: Bool { false }
    var linkState: WireLinkState { .notPaired }

    init() {}
    func activate() async {}
    func refresh() {}
    func sendTestBuzz() async -> Bool { false }
    func sendPatternPreview(named patternName: String) async -> Bool { false }
}

/// A controllable fake for SwiftUI previews and unit tests: set the facts and
/// record what was sent, with no link and no framework.
@MainActor
final class FakeWatchConnection: WatchConnectionProviding {
    var isPaired: Bool
    var isWatchAppInstalled: Bool
    var isReachable: Bool
    /// The pattern codes (or `nil` for a plain test buzz) sent, in order.
    private(set) var sent: [String?] = []

    init(
        isPaired: Bool = true,
        isWatchAppInstalled: Bool = true,
        isReachable: Bool = true
    ) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        self.isReachable = isReachable
    }

    var linkState: WireLinkState {
        if !isPaired { return .notPaired }
        if !isWatchAppInstalled { return .notInstalled }
        return isReachable ? .reachableHelloPending : .installedUnreachable
    }

    func activate() async {}
    func refresh() {}

    func sendTestBuzz() async -> Bool {
        sent.append(nil)
        return isReachable
    }

    func sendPatternPreview(named patternName: String) async -> Bool {
        sent.append(patternName)
        return isReachable
    }
}
