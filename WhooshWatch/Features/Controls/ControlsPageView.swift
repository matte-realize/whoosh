import SwiftUI
import WhooshWire

/// The Controls page (watch-companion design "Pages → Controls"): Pause/Resume
/// and Save clip as large tap targets (≥ 60 pt), Stop as a deliberate
/// press-and-hold (~1.0 s) with a progress ring and a VoiceOver "Stop ride"
/// action. Disabled controls show a short reason. A scrollable page so Stop sits
/// below the fold and is reached on purpose. Pending commands show a spinner;
/// a confirmed/not-confirmed reply updates the label.
struct ControlsPageView: View {
    let model: WatchSessionModel

    private var controls: WatchRideReducer.Controls { model.view.controls }
    private var isRecording: Bool { model.view.rideState == .recording || model.view.rideState == .signalLost }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                pauseResumeButton
                saveClipButton
                stopButton
            }
            .padding(.vertical, 6)
        }
        .background(WatchTheme.ink)
    }

    // MARK: Pause / Resume

    private var pauseResumeButton: some View {
        let enabled = controls.pauseResumeEnabled
        return VStack(spacing: 2) {
            Button {
                if isRecording { model.pause() } else { model.resume() }
            } label: {
                Label(isRecording ? "Pause" : "Resume",
                      systemImage: isRecording ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.minTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.lime)
            .disabled(!enabled)
            commandState(.pause, orKind: .resume)
            if !enabled {
                reasonText(controls.pauseResume)
            }
        }
    }

    // MARK: Save clip

    private var saveClipButton: some View {
        let enabled = controls.saveClipEnabled
        return VStack(spacing: 2) {
            Button {
                model.saveClip()
            } label: {
                Label("Save clip", systemImage: "scissors")
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.minTarget)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.mist)
            .disabled(!enabled)
            commandState(.saveClip)
            if !enabled {
                reasonText(controls.saveClip)
            }
        }
    }

    // MARK: Stop (hold)

    private var stopButton: some View {
        VStack(spacing: 4) {
            Text("Hold to stop")
                .font(.caption2)
                .foregroundStyle(WatchTheme.mistDim)
            HoldToConfirmButton(
                title: "Stop",
                systemImage: "stop.fill",
                holdSeconds: 1.0,
                tint: WatchTheme.amber,
                actionName: "Stop ride",
                onConfirm: { model.stop() },
                enabled: controls.stopEnabled
            )
            if !controls.stopEnabled {
                reasonText(controls.stop)
            }
            commandState(.stop)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: Helpers

    @ViewBuilder
    private func reasonText(_ reason: WatchRideReducer.ControlReason) -> some View {
        Text(WatchText.controlReason(reason))
            .font(.caption2)
            .foregroundStyle(WatchTheme.mistDim)
            .multilineTextAlignment(.center)
    }

    /// Shows pending / not-confirmed feedback for a command kind (and an
    /// optional alternate kind, e.g. pause vs resume share one button).
    @ViewBuilder
    private func commandState(_ kind: WireCommandKind, orKind other: WireCommandKind? = nil) -> some View {
        let state = model.commandStates[kind] ?? other.flatMap { model.commandStates[$0] }
        switch state {
        case .pending:
            Label("Sending…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2).foregroundStyle(WatchTheme.mistDim)
        case .notConfirmed:
            Label("Not confirmed", systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundStyle(WatchTheme.amber)
        case .confirmed, .idle, .none:
            EmptyView()
        }
    }
}

#Preview("Controls — riding") {
    ControlsPageView(model: WatchDemo.makeModel(scenario: .riding))
}

#Preview("Controls — camera off") {
    ControlsPageView(model: WatchDemo.makeModel(scenario: .ridingCameraTrouble))
}

#Preview("Controls — no link") {
    ControlsPageView(model: WatchDemo.makeModel(scenario: .noLink))
}
