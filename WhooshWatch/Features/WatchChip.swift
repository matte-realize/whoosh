import SwiftUI
import WhooshWire

/// A small icon + text chip used on the Ride page for state (ride, camera,
/// link). Icon + text for every state (product principle). Reduced-luminance
/// shows the glyph and short text only.
struct WatchChip: View {
    let systemImage: String
    let text: String
    var tint: Color = WatchTheme.mistDim

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(tint)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
    }
}

/// Short, honest text for wire codes shown on the watch. No free text crosses
/// the wire; all strings are rendered here from codes.
enum WatchText {
    static func rideState(_ state: WireRideState) -> String {
        switch state {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .signalLost: return "Signal lost"
        case .finished: return "Finished"
        case .unknown: return "—"
        }
    }

    static func rideGlyph(_ state: WireRideState) -> String {
        switch state {
        case .recording: return "record.circle"
        case .paused: return "pause.circle"
        case .signalLost: return "location.slash"
        case .finished: return "flag.checkered"
        default: return "circle"
        }
    }

    static func cameraState(_ state: WireCameraState) -> String {
        switch state {
        case .off: return "Camera off"
        case .preparing: return "Camera starting"
        case .recording: return "Camera on"
        case .degraded: return "Camera reduced"
        case .interrupted: return "Camera paused"
        case .stopped: return "Camera stopped"
        case .failed: return "Camera failed"
        case .unknown: return "Camera —"
        }
    }

    static func cameraGlyph(_ state: WireCameraState) -> String {
        switch state {
        case .recording, .degraded: return "video.fill"
        case .interrupted, .stopped, .failed: return "video.slash.fill"
        default: return "video"
        }
    }

    static func cameraTint(_ state: WireCameraState) -> Color {
        switch state {
        case .recording: return WatchTheme.lime
        case .degraded, .interrupted: return WatchTheme.amber
        case .stopped, .failed: return WatchTheme.alert
        default: return WatchTheme.mistDim
        }
    }

    static func cameraReason(_ reason: WireCameraReason?) -> String? {
        guard let reason else { return nil }
        switch reason {
        case .thermal: return "too hot"
        case .storage: return "storage full"
        case .battery: return "low battery"
        case .permission: return "no permission"
        case .interrupted: return "interrupted"
        case .failed: return "failed"
        case .lockedScreen: return "phone locked"
        case .unknown: return nil
        }
    }

    /// Why a control is disabled, as a short rider instruction.
    static func controlReason(_ reason: WatchRideReducer.ControlReason) -> String {
        switch reason {
        case .ok: return ""
        case .noRide: return "No active ride"
        case .notRecording: return "Camera is off"
        case .linkDown: return "iPhone not responding"
        case .notArmed: return "Tap Ready on iPhone"
        case .stale: return "Reconnecting…"
        }
    }

    static func startReasonCodes(_ reasons: [WireStartReasonCode]?) -> String {
        guard let reasons, !reasons.isEmpty else { return "Set up on your iPhone" }
        return reasons.map(startReason).joined(separator: " · ")
    }

    static func startReason(_ code: WireStartReasonCode) -> String {
        switch code {
        case .notArmed: return "Tap Ready on iPhone"
        case .camera: return "Frame the camera"
        case .location: return "Allow location"
        case .rideActive: return "Ride in progress"
        case .crashActive: return "Handling alert"
        case .linkNotReady: return "Connecting…"
        case .appNotActive: return "Open Whoosh on iPhone"
        case .unknown: return "Set up on iPhone"
        }
    }
}
