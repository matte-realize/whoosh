import Foundation

/// Scriptable `ClipThumbnailing` for tests and SwiftUI previews. Records each
/// request and returns a scripted result, so `ClipPinner` can be exercised
/// without AVFoundation.
///
/// Lives under `Services/Camera/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// An `actor` so it is `Sendable` with safe mutable state: the pinner is on the
/// main actor and `await`s `generateThumbnail`; tests read the recorded requests
/// with `await`.
actor FakeClipThumbnailer: ClipThumbnailing {
    /// One recorded request.
    struct Request: Equatable, Sendable {
        let sourceURLs: [URL]
        let atOffset: TimeInterval
        let destinationURL: URL
    }

    /// When `true`, `generateThumbnail` returns the destination URL (success);
    /// when `false`, it returns `nil` (a generation failure the pinner tolerates).
    private let succeeds: Bool
    /// Every request made, in order.
    private(set) var requests: [Request] = []

    init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    func generateThumbnail(
        sourceURLs: [URL],
        atOffset: TimeInterval,
        destinationURL: URL
    ) async -> URL? {
        requests.append(Request(sourceURLs: sourceURLs, atOffset: atOffset, destinationURL: destinationURL))
        return succeeds ? destinationURL : nil
    }

    /// Number of recorded requests (test convenience).
    var requestCount: Int { requests.count }
}
