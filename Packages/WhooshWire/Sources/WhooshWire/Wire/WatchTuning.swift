import Foundation

/// Every tunable constant for the watch companion, gathered in one place
/// (watch-companion design "Revisability note"; Requirement 5 "Configurable").
///
/// All values are **hypotheses to be measured** on the owner's watch and the
/// iPhone 14 (tagged *(verify)* in the design); none is a promise. Each value
/// has a documented default and an inclusive valid range; `init` and the
/// mutating setters **clamp** every value into its range so a bad caller can
/// never push a value out of bounds.
///
/// Time values are milliseconds unless the name says otherwise; counts are
/// plain integers; percentages are 0…100.
public struct WatchTuning: Equatable, Sendable {
    // MARK: Status transport (design "StatusTransportPolicy", Req 8.5)
    /// Live-status heartbeat while the watch display is active (default 5 s).
    public private(set) var statusHeartbeatActiveMs: Int
    /// Context-status heartbeat while the display is off (default 30 s).
    public private(set) var statusHeartbeatIdleMs: Int
    /// Minimum spacing between live status sends (default 5 s; 1 s floor).
    public private(set) var statusMinLiveIntervalMs: Int

    // MARK: Freshness / staleness (design "StatusFreshness", Req 10.4)
    /// Status is shown stale after this long without a message (default 15 s).
    public private(set) var statusStaleMs: Int
    /// The phone is announced disconnected after this long (default 20 s).
    public private(set) var linkLostAnnounceMs: Int
    /// "iPhone app may have closed" after this long of silence (default 60 s).
    public private(set) var phoneSilentWarnMs: Int
    /// Orphan workout-session timeout with no phone contact (default 15 min).
    public private(set) var orphanTimeoutMs: Int

    // MARK: Commands (design "WatchCommandTracker", Req 6)
    /// Command time-to-live before "Not confirmed" (default 8 s).
    public private(set) var commandTtlMs: Int
    /// Minimum spacing between distinct commands on the watch (default 500 ms).
    public private(set) var commandMinSpacingMs: Int
    /// Maximum retry attempts with the same id (default 3).
    public private(set) var commandMaxAttempts: Int
    /// Save-clip debounce on the phone (default 2 s).
    public private(set) var saveClipDebounceMs: Int
    /// Dedupe cache window (default 5 min) and size (default 128).
    public private(set) var dedupeWindowMs: Int
    public private(set) var dedupeMaxEntries: Int

    // MARK: Arming (design "StartArming", Req 9.2)
    /// Armed-window expiry (default 5 min, range 1–15 min).
    public private(set) var armedExpiryMs: Int
    /// Start hold duration (default 0.8 s).
    public private(set) var startHoldMs: Int
    /// Stop hold duration (default 1.0 s).
    public private(set) var stopHoldMs: Int

    // MARK: Alerts / escalation (design "Fan-out", Req 13.2)
    /// Watch acknowledgement timeout before escalating to audio (default 1.5 s).
    public private(set) var watchAckTimeoutMs: Int

    // MARK: Haptic limiter (design "WristHapticLimiter", Req 12.2)
    /// Minimum gap between pattern starts (default 1.0 s).
    public private(set) var hapticMinGapMs: Int
    /// Platform minimum between cues within a pattern (default 100 ms floor).
    public private(set) var hapticMinCueSpacingMs: Int
    /// Rear-cue base per-kind cooldown (default 3 s).
    public private(set) var rearCueCooldownMs: Int
    /// Camera-notice per-reason cooldown (default 60 s).
    public private(set) var cameraNoticeCooldownMs: Int
    /// Storm-backoff quiet-reset window (default 30 s).
    public private(set) var stormResetMs: Int

    // MARK: Alert TTLs (design "Freshness", Req 12.4)
    public private(set) var ttlRearVehicleMs: Int
    public private(set) var ttlClipNoticeMs: Int
    public private(set) var ttlCameraBatteryMs: Int
    public private(set) var ttlLinkNoticeMs: Int

    // MARK: Batteries (design "Readiness screen", Req 3.9, 20.5)
    /// Warn below this watch battery before a ride (default 40%).
    public private(set) var watchBatteryWarnPct: Int
    /// Watch low-battery notice threshold during a ride (default 15%).
    public private(set) var watchBatteryLowPct: Int
    /// End the keep-alive session early at this watch battery (default 5%).
    public private(set) var watchBatteryEndPct: Int

    // MARK: Health save (design "End of ride", Req 16.2)
    /// Default Save/Discard choice applied after this long (default 60 s).
    public private(set) var healthChoiceTimeoutMs: Int

    // MARK: Queue (design "Channel assignment", Req 20.4)
    /// Cap on outstanding queue transfers (default 20).
    public private(set) var maxOutstandingTransfers: Int

    // MARK: startWatchApp retry (design, Req 10.3)
    public private(set) var startWatchAppRetries: Int
    public private(set) var startWatchAppBackoffMs: Int

    // MARK: Notice log (design "WatchNoticeLog", Req 14.3)
    public private(set) var noticeLogSize: Int

    public init(
        statusHeartbeatActiveMs: Int = 5_000,
        statusHeartbeatIdleMs: Int = 30_000,
        statusMinLiveIntervalMs: Int = 5_000,
        statusStaleMs: Int = 15_000,
        linkLostAnnounceMs: Int = 20_000,
        phoneSilentWarnMs: Int = 60_000,
        orphanTimeoutMs: Int = 900_000,
        commandTtlMs: Int = 8_000,
        commandMinSpacingMs: Int = 500,
        commandMaxAttempts: Int = 3,
        saveClipDebounceMs: Int = 2_000,
        dedupeWindowMs: Int = 300_000,
        dedupeMaxEntries: Int = 128,
        armedExpiryMs: Int = 300_000,
        startHoldMs: Int = 800,
        stopHoldMs: Int = 1_000,
        watchAckTimeoutMs: Int = 1_500,
        hapticMinGapMs: Int = 1_000,
        hapticMinCueSpacingMs: Int = 100,
        rearCueCooldownMs: Int = 3_000,
        cameraNoticeCooldownMs: Int = 60_000,
        stormResetMs: Int = 30_000,
        ttlRearVehicleMs: Int = 3_000,
        ttlClipNoticeMs: Int = 10_000,
        ttlCameraBatteryMs: Int = 30_000,
        ttlLinkNoticeMs: Int = 20_000,
        watchBatteryWarnPct: Int = 40,
        watchBatteryLowPct: Int = 15,
        watchBatteryEndPct: Int = 5,
        healthChoiceTimeoutMs: Int = 60_000,
        maxOutstandingTransfers: Int = 20,
        startWatchAppRetries: Int = 3,
        startWatchAppBackoffMs: Int = 15_000,
        noticeLogSize: Int = 10
    ) {
        self.statusHeartbeatActiveMs = Self.clamp(statusHeartbeatActiveMs, Self.statusHeartbeatActiveRange)
        self.statusHeartbeatIdleMs = Self.clamp(statusHeartbeatIdleMs, Self.statusHeartbeatIdleRange)
        self.statusMinLiveIntervalMs = Self.clamp(statusMinLiveIntervalMs, Self.statusMinLiveIntervalRange)
        self.statusStaleMs = Self.clamp(statusStaleMs, Self.statusStaleRange)
        self.linkLostAnnounceMs = Self.clamp(linkLostAnnounceMs, Self.linkLostAnnounceRange)
        self.phoneSilentWarnMs = Self.clamp(phoneSilentWarnMs, Self.phoneSilentWarnRange)
        self.orphanTimeoutMs = Self.clamp(orphanTimeoutMs, Self.orphanTimeoutRange)
        self.commandTtlMs = Self.clamp(commandTtlMs, Self.commandTtlRange)
        self.commandMinSpacingMs = Self.clamp(commandMinSpacingMs, Self.commandMinSpacingRange)
        self.commandMaxAttempts = Self.clamp(commandMaxAttempts, Self.commandMaxAttemptsRange)
        self.saveClipDebounceMs = Self.clamp(saveClipDebounceMs, Self.saveClipDebounceRange)
        self.dedupeWindowMs = Self.clamp(dedupeWindowMs, Self.dedupeWindowRange)
        self.dedupeMaxEntries = Self.clamp(dedupeMaxEntries, Self.dedupeMaxEntriesRange)
        self.armedExpiryMs = Self.clamp(armedExpiryMs, Self.armedExpiryRange)
        self.startHoldMs = Self.clamp(startHoldMs, Self.startHoldRange)
        self.stopHoldMs = Self.clamp(stopHoldMs, Self.stopHoldRange)
        self.watchAckTimeoutMs = Self.clamp(watchAckTimeoutMs, Self.watchAckTimeoutRange)
        self.hapticMinGapMs = Self.clamp(hapticMinGapMs, Self.hapticMinGapRange)
        self.hapticMinCueSpacingMs = Self.clamp(hapticMinCueSpacingMs, Self.hapticMinCueSpacingRange)
        self.rearCueCooldownMs = Self.clamp(rearCueCooldownMs, Self.rearCueCooldownRange)
        self.cameraNoticeCooldownMs = Self.clamp(cameraNoticeCooldownMs, Self.cameraNoticeCooldownRange)
        self.stormResetMs = Self.clamp(stormResetMs, Self.stormResetRange)
        self.ttlRearVehicleMs = Self.clamp(ttlRearVehicleMs, Self.ttlRange)
        self.ttlClipNoticeMs = Self.clamp(ttlClipNoticeMs, Self.ttlRange)
        self.ttlCameraBatteryMs = Self.clamp(ttlCameraBatteryMs, Self.ttlRange)
        self.ttlLinkNoticeMs = Self.clamp(ttlLinkNoticeMs, Self.ttlRange)
        self.watchBatteryWarnPct = Self.clamp(watchBatteryWarnPct, Self.pctRange)
        self.watchBatteryLowPct = Self.clamp(watchBatteryLowPct, Self.pctRange)
        self.watchBatteryEndPct = Self.clamp(watchBatteryEndPct, Self.pctRange)
        self.healthChoiceTimeoutMs = Self.clamp(healthChoiceTimeoutMs, Self.healthChoiceTimeoutRange)
        self.maxOutstandingTransfers = Self.clamp(maxOutstandingTransfers, Self.maxOutstandingTransfersRange)
        self.startWatchAppRetries = Self.clamp(startWatchAppRetries, Self.startWatchAppRetriesRange)
        self.startWatchAppBackoffMs = Self.clamp(startWatchAppBackoffMs, Self.startWatchAppBackoffRange)
        self.noticeLogSize = Self.clamp(noticeLogSize, Self.noticeLogSizeRange)
    }

    // MARK: - Valid ranges (inclusive)

    public static let statusHeartbeatActiveRange = 1_000...30_000
    public static let statusHeartbeatIdleRange = 5_000...120_000
    public static let statusMinLiveIntervalRange = 1_000...30_000
    public static let statusStaleRange = 5_000...60_000
    public static let linkLostAnnounceRange = 5_000...60_000
    public static let phoneSilentWarnRange = 20_000...300_000
    public static let orphanTimeoutRange = 300_000...1_800_000
    public static let commandTtlRange = 2_000...30_000
    public static let commandMinSpacingRange = 100...2_000
    public static let commandMaxAttemptsRange = 1...5
    public static let saveClipDebounceRange = 500...10_000
    public static let dedupeWindowRange = 60_000...600_000
    public static let dedupeMaxEntriesRange = 32...512
    public static let armedExpiryRange = 60_000...900_000           // 1–15 min
    public static let startHoldRange = 300...2_000
    public static let stopHoldRange = 500...3_000
    public static let watchAckTimeoutRange = 500...5_000
    public static let hapticMinGapRange = 300...5_000
    public static let hapticMinCueSpacingRange = 100...1_000
    public static let rearCueCooldownRange = 1_000...30_000
    public static let cameraNoticeCooldownRange = 10_000...300_000
    public static let stormResetRange = 10_000...120_000
    public static let ttlRange = 1_000...120_000
    public static let pctRange = 0...100
    public static let healthChoiceTimeoutRange = 10_000...300_000
    public static let maxOutstandingTransfersRange = 1...100
    public static let startWatchAppRetriesRange = 0...10
    public static let startWatchAppBackoffRange = 5_000...60_000
    public static let noticeLogSizeRange = 1...50

    /// Clamp `value` into the inclusive `range`.
    public nonisolated static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }
}
