import SwiftUI
import WhooshWire

/// The Notices page (watch-companion design "Pages → Notices"): the last few
/// alerts for this ride (memory only), newest first, with an unread badge that
/// clears when the page appears. Kind + time + reason only — no free text.
struct NoticesPageView: View {
    let model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notices")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.mist)

                if model.notices.isEmpty {
                    Text("No notices this ride")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.mistDim)
                } else {
                    ForEach(Array(model.notices.reversed().enumerated()), id: \.offset) { _, entry in
                        noticeRow(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .background(WatchTheme.ink)
        .onAppear { model.markNoticesRead() }
    }

    private func noticeRow(_ entry: WatchNoticeLog.Entry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph(entry.kind))
                .foregroundStyle(tint(entry.tier))
            VStack(alignment: .leading, spacing: 0) {
                Text(text(entry))
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.mist)
                Text(WatchFormat.elapsed(entry.timeIntoRideMs))
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.mistDim)
            }
            Spacer()
        }
    }

    private func text(_ entry: WatchNoticeLog.Entry) -> String {
        let base = kindText(entry.kind)
        if let r = WatchText.cameraReason(entry.reason) { return "\(base): \(r)" }
        return base
    }

    private func kindText(_ kind: WireAlertKind) -> String {
        switch kind {
        case .rearVehicleCaution: return "Vehicle cue (experimental)"
        case .cameraInterrupted: return "Camera paused"
        case .cameraResumed: return "Camera recording"
        case .cameraStopped: return "Camera stopped"
        case .clipSaved: return "Clip saved"
        case .clipNotSaved: return "Clip not saved"
        case .phoneBatteryLow: return "iPhone battery low"
        case .crashCountdownStarted: return "Crash countdown"
        case .crashCountdownEnded: return "Countdown ended"
        case .hapticTest: return "Test buzz"
        case .patternPreview: return "Pattern preview"
        case .linkRestored: return "iPhone reconnected"
        case .unknown: return "Whoosh notice"
        }
    }

    private func glyph(_ kind: WireAlertKind) -> String {
        switch kind {
        case .rearVehicleCaution: return "car.rear.waves.up"
        case .cameraInterrupted, .cameraStopped, .clipNotSaved: return "video.slash"
        case .cameraResumed, .clipSaved: return "video"
        case .phoneBatteryLow: return "battery.25"
        case .crashCountdownStarted, .crashCountdownEnded: return "exclamationmark.triangle"
        case .linkRestored: return "wifi"
        default: return "bell"
        }
    }

    private func tint(_ tier: WireAlertTier) -> Color {
        switch tier {
        case .critical: return WatchTheme.alert
        case .caution: return WatchTheme.amber
        case .notice: return WatchTheme.mist
        case .confirm: return WatchTheme.lime
        case .unknown: return WatchTheme.mistDim
        }
    }
}

#Preview("Notices") {
    NoticesPageView(model: WatchDemo.makeModel(scenario: .riding))
}
