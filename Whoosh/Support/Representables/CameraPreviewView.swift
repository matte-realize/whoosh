import SwiftUI
import UIKit

/// A SwiftUI wrapper that shows the live camera preview for Mount & frame
/// (rear-camera spec Requirement 9.1, task 17/22; design "Support/Representables:
/// CameraPreviewView"). It hosts the `UIView` vended by a `CameraPreviewHost`
/// (the capture service), so **the view layer never imports AVFoundation** — the
/// `AVCaptureVideoPreviewLayer` and the session stay inside `Services/Camera/`.
///
/// Lives under `Support/Representables/` (the UIKit-wrapper home). The host is
/// supplied by the composition root / Mount & frame view model; previews and
/// tests can pass a host backed by the fake capture seam.
struct CameraPreviewView: UIViewRepresentable {
    /// The preview host (the capture service). The view asks it for a preview
    /// `UIView` once; updates are no-ops (the layer tracks the session itself).
    let host: CameraPreviewHost

    func makeUIView(context: Context) -> UIView {
        host.makePreviewView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
