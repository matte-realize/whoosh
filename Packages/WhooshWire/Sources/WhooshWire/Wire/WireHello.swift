import Foundation

/// The handshake message exchanged both directions at reachability
/// (watch-companion design "Versioning and negotiation"; Requirement 5.4).
///
/// Carries the sender's supported version range `[minVersion, maxVersion]`, the
/// app build, a per-launch `sessionNonce` (so a relaunch is detected), and
/// capability codes (for example `startFromWatch`, `crashCancel`,
/// `haptics.v1`). The link negotiates `min(maxA, maxB)` when it is ≥
/// `max(minA, minB)`; otherwise it is `incompatible`.
public struct WireHello: Equatable, Codable, Sendable {
    public var minVersion: Int
    public var maxVersion: Int
    public var appBuild: String
    public var sessionNonce: String
    /// Sorted capability codes (short codes, not free text).
    public var capabilities: [String]

    public init(
        minVersion: Int,
        maxVersion: Int,
        appBuild: String,
        sessionNonce: String,
        capabilities: [String] = []
    ) {
        self.minVersion = minVersion
        self.maxVersion = maxVersion
        self.appBuild = appBuild
        self.sessionNonce = sessionNonce
        self.capabilities = capabilities.sorted()
    }

    /// The `[min, max]` range as a `ClosedRange` for negotiation.
    public var versionRange: ClosedRange<Int> {
        let lo = Swift.min(minVersion, maxVersion)
        let hi = Swift.max(minVersion, maxVersion)
        return lo...hi
    }
}
