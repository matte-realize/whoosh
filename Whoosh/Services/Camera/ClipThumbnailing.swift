import Foundation

/// Generates a still thumbnail for a saved clip (rear-camera spec task 16;
/// Requirement 8.1, design "Clip playback, thumbnails, export"). Put behind a
/// small protocol so `ClipPinner` and its tests never touch AVFoundation: the
/// live implementation (`AssetImageClipThumbnailer`) uses `AVAssetImageGenerator`
/// over the clip's segment files; `FakeClipThumbnailer` records requests and
/// returns a scripted result.
///
/// ## Contract
/// - On-device only: the thumbnail is written beside the clip's footage
///   (`clips/<clipID>/thumb.jpg`) and is never uploaded, linked, or logged.
/// - Non-throwing in the success/failure sense: a generation failure returns
///   `nil` so a missing thumbnail never blocks saving the clip (the list shows a
///   placeholder). "Never block a ride."
///
/// `Sendable` so the thumbnailer can be held by the main-actor pinner and used
/// from an async context.
protocol ClipThumbnailing: Sendable {
    /// Generate a thumbnail for the footage at `sourceURLs` (the clip's ordered
    /// segment files), sampling at `atOffset` seconds from the first segment,
    /// and write it to `destinationURL`. Returns `destinationURL` on success, or
    /// `nil` if a thumbnail could not be produced (the clip still saves).
    func generateThumbnail(
        sourceURLs: [URL],
        atOffset: TimeInterval,
        destinationURL: URL
    ) async -> URL?
}
