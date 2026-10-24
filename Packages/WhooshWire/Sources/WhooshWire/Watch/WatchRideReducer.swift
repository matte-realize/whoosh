import Foundation

/// The pure watch-side ride reducer (watch-companion design "`WatchRideReducer`";
/// Requirement 8.1, 8.4, 10.4). It folds incoming statuses, local intents, the
/// link state, and the passage of time into a **view model** (phase, numbers,
/// chips, enabled controls with reasons). It never decides a ride transition —
/// it only reflects what the phone published (phone-authoritative).
///
/// Skew-free time: `activeMs` is advanced by the watch's own monotonic clock
/// while `recording`/`signalLost` and frozen when `paused`; staleness is "no
/// message for `statusStaleMs`" measured on the watch clock only.
public struct WatchRideReducer: Sendable {
    public let tuning: WatchTuning

    public enum Phase: Equatable, Sendable {
        case noLink
        case idle
        case activeFresh
        case activeStale
        case ending
        case summary
    }

    public enum LinkState: Equatable, Sendable {
        case connected
        case stale
        case lost
    }

    /// A control and why it is (dis)abled — shown as a short instruction.
    public enum ControlReason: Equatable, Sendable {
        case ok
        case noRide
        case notRecording   // save clip while camera is off
        case linkDown
        case notArmed
        case stale
    }

    public struct Controls: Equatable, Sendable {
        public var pauseResume: ControlReason
        public var saveClip: ControlReason
        public var stop: ControlReason
        public var start: ControlReason
        public init(
            pauseResume: ControlReason = .noRide,
            saveClip: ControlReason = .noRide,
            stop: ControlReason = .noRide,
            start: ControlReason = .notArmed
        ) {
            self.pauseResume = pauseResume
            self.saveClip = saveClip
            self.stop = stop
            self.start = start
        }
        public var pauseResumeEnabled: Bool { pauseResume == .ok }
        public var saveClipEnabled: Bool { saveClip == .ok }
        public var stopEnabled: Bool { stop == .ok }
        public var startEnabled: Bool { start == .ok }
    }

    public struct ViewModel: Equatable, Sendable {
        public var phase: Phase
        public var elapsedMs: Int
        public var distance10m: Int
        public var speedDms: Int?
        public var rideState: WireRideState
        public var cameraState: WireCameraState
        public var banner: WireBanner
        public var controls: Controls
        public var showStaleChip: Bool
    }

    // Latest accepted status and bookkeeping.
    private var status: WireRideStatus?
    private var lastEpoch: Int?
    private var lastSeq: Int?
    private var lastMessageMs: Int?
    private var activeMsAtReceipt: Int = 0
    private var receiptNowMs: Int = 0
    private var link: LinkState = .connected

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    /// Apply an incoming status at monotonic `nowMs`. Returns true if accepted
    /// (false when it is an out-of-order/old `seq` for the same epoch).
    @discardableResult
    public mutating func apply(_ incoming: WireRideStatus, nowMs: Int) -> Bool {
        // A new epoch (or a different ride) resets the seq gate.
        let newEpoch = lastEpoch != incoming.epoch || status?.rideId != incoming.rideId
        if !newEpoch, let last = lastSeq, incoming.seq <= last {
            return false   // stale/duplicate within the epoch — ignore.
        }
        status = incoming
        lastEpoch = incoming.epoch
        lastSeq = incoming.seq
        lastMessageMs = nowMs
        activeMsAtReceipt = max(0, incoming.activeMs)
        receiptNowMs = nowMs
        if link == .lost || link == .stale { link = .connected }
        return true
    }

    /// Set the link state (from the link state machine). `lost` blanks controls.
    public mutating func setLink(_ state: LinkState) {
        link = state
    }

    /// The projected elapsed time at `nowMs` (frozen when paused).
    public func elapsedMs(nowMs: Int) -> Int {
        guard let s = status else { return 0 }
        switch s.state {
        case .recording, .signalLost:
            return activeMsAtReceipt + max(0, nowMs - receiptNowMs)
        default:
            return activeMsAtReceipt   // paused / idle / finished: frozen
        }
    }

    /// Whether the display is stale (no message for `statusStaleMs`).
    public func isStale(nowMs: Int) -> Bool {
        guard let last = lastMessageMs else { return false }
        return nowMs - last >= tuning.statusStaleMs
    }

    /// Compute the view model at `nowMs`.
    public func viewModel(nowMs: Int) -> ViewModel {
        guard let s = status else {
            return ViewModel(
                phase: link == .lost ? .noLink : .idle,
                elapsedMs: 0, distance10m: 0, speedDms: nil,
                rideState: .idle, cameraState: .off, banner: .none,
                controls: Controls(start: s_startReason(nil)),
                showStaleChip: false
            )
        }

        let stale = isStale(nowMs: nowMs) || link == .stale
        let down = link == .lost

        let phase: Phase
        switch s.state {
        case .idle:
            phase = down ? .noLink : .idle
        case .recording, .signalLost, .paused:
            phase = down ? .noLink : (stale ? .activeStale : .activeFresh)
        case .finished:
            phase = .summary
        case .unknown:
            phase = down ? .noLink : .activeStale
        }

        let controls = computeControls(status: s, down: down, stale: stale)

        return ViewModel(
            phase: phase,
            elapsedMs: elapsedMs(nowMs: nowMs),
            distance10m: s.distance10m,
            speedDms: s.speedDms,
            rideState: s.state,
            cameraState: s.camera.state,
            banner: s.banner,
            controls: controls,
            showStaleChip: stale && !down
        )
    }

    // MARK: - Controls

    private func computeControls(status s: WireRideStatus, down: Bool, stale: Bool) -> Controls {
        if down {
            return Controls(
                pauseResume: .linkDown, saveClip: .linkDown,
                stop: .linkDown, start: .linkDown
            )
        }
        let active = s.state == .recording || s.state == .paused || s.state == .signalLost
        let pauseResume: ControlReason = active ? (stale ? .stale : .ok) : .noRide
        let stop: ControlReason = active ? (stale ? .stale : .ok) : .noRide
        // Save clip only when the camera is actually recording.
        let cameraRecording = s.camera.state == .recording || s.camera.state == .degraded
        let saveClip: ControlReason
        if !active { saveClip = .noRide }
        else if stale { saveClip = .stale }
        else if !cameraRecording { saveClip = .notRecording }
        else { saveClip = .ok }

        return Controls(
            pauseResume: pauseResume,
            saveClip: saveClip,
            stop: stop,
            start: s_startReason(s)
        )
    }

    /// Start is enabled only when the status says `armed`.
    private func s_startReason(_ s: WireRideStatus?) -> ControlReason {
        guard let s else { return .notArmed }
        if s.state != .idle { return .noRide }
        return s.start.kind == .armed ? .ok : .notArmed
    }
}
