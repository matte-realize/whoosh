import SwiftUI
import MessageUI

/// A thin SwiftUI wrapper around `MFMessageComposeViewController` (spec
/// Requirement 12.1/12.9, design `Support/Representables/`).
///
/// This is the **only** file in the app allowed to import `MessageUI`
/// (privacy-check rule 9): the native composer is a **rider-initiated fallback
/// only**. It is pre-filled with the recipients and the message built by the
/// shared `CrashMessageBuilder`, and it **never** sends without the rider
/// tapping Send — iOS owns that interaction. The app never claims to send
/// silently from the rider's number.
///
/// Present this only when `MessageComposeView.canSendText` is `true`; otherwise
/// the caller offers Copy / Share instead (Requirement 12.8). `onFinish` reports
/// the composer's result so the caller can record `fallbackAction`.
struct MessageComposeView: UIViewControllerRepresentable {
    /// E.164 (or raw) recipient numbers to pre-fill.
    let recipients: [String]
    /// The message body, built by the shared `CrashMessageBuilder`.
    let body: String
    /// Called with the composer's result when it is dismissed.
    var onFinish: (MessageComposeResult) -> Void = { _ in }

    /// Whether this device can send a text at all (`iPad`, Simulator, or a
    /// device with no Messages/SIM returns `false`). Callers must check this
    /// before presenting and fall back to Copy / Share when it is `false`.
    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMessageComposeViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// Bridges `MFMessageComposeViewControllerDelegate` to the SwiftUI closure.
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish(result)
        }
    }
}
