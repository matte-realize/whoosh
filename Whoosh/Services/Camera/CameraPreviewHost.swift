import UIKit

/// A small seam that lets the Mount & frame screen show a live camera preview
/// **without importing AVFoundation** (rear-camera spec Requirement 3/9, task
/// 17; design "CameraPreviewHost: a UIKit view that attaches to the session").
///
/// The capture service vends a `CameraPreviewHost`; a `UIViewRepresentable`
/// (`CameraPreviewView`, task 22) wraps the returned `UIView`. The view layer
/// knows only about `UIView` — the `AVCaptureVideoPreviewLayer` and the session
/// live entirely inside `Services/Camera/`, so the privacy-check capture-API
/// rule (only `Services/Camera/`) holds and views stay framework-free.
///
/// ## Contract
/// - `makePreviewView()` returns a `UIView` whose backing layer renders the
///   session's video. Calling it before the session is configured is safe (the
///   preview simply shows nothing until frames flow).
/// - The host keeps a weak link to the session; tearing down the service
///   detaches the preview so no session is leaked.
/// - Main actor: preview views are UIKit view objects.
@MainActor
protocol CameraPreviewHost: AnyObject {
    /// Create a `UIView` that renders the live capture preview. The caller owns
    /// the returned view's lifetime (SwiftUI via a representable).
    func makePreviewView() -> UIView
}
