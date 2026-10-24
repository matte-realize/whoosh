import Foundation

/// The wire protocol version (watch-companion design "Versioning and
/// negotiation", Requirement 5.4).
///
/// `current` is the version this build writes; `minSupported` is the oldest
/// version it can still read. A current release supports the immediately
/// previous wire version (N−1). Within a version only additive changes are
/// allowed; a breaking change bumps `current` and updates the golden fixtures
/// in the same commit.
public enum WireVersion {
    /// The version this build writes.
    public static let current = 1
    /// The oldest version this build can read (N−1 support).
    public static let minSupported = 1

    /// Negotiate the highest common version between two inclusive `[min, max]`
    /// ranges. Returns `nil` when the ranges do not overlap (the link is then
    /// `incompatible`; design link-state row 9).
    public nonisolated static func negotiate(
        local: ClosedRange<Int>,
        remote: ClosedRange<Int>
    ) -> Int? {
        let low = Swift.max(local.lowerBound, remote.lowerBound)
        let high = Swift.min(local.upperBound, remote.upperBound)
        return low <= high ? high : nil
    }
}
