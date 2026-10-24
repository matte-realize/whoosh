import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The always-dark, full-screen active-ride screen (Requirement 5, mockups 2/3).
///
/// Presented by the composition root as a **non-dismissible full-screen cover**
/// while a ride is active; the only way out is the press-and-hold Stop (or its
/// VoiceOver custom action). Shows the live route (`RouteMapView` in `.live`
/// mode), a state chip (Recording / Paused, icon + text), an inert "Rear
/// detection off" chip, and a bottom dark sheet with at most three numbers —
/// ride time (huge, ticking every second via `TimelineView`), distance, and
/// speed — plus a lime Pause/Resume pill and the red `HoldToStopButton`.
///
/// When the session's banner is `signalLost` an amber "GPS signal lost" banner
/// appears; a `permissionRevoked` banner uses the same calm styling with copy
/// that the ride is saved-and-stoppable. Keeps the screen awake while visible by
/// asking the injected `ScreenController` to hold the idle timer (the screen
/// controller is the one owner of that toggle; rear-camera task 21). State is
/// always icon + text, never color alone.
///
/// Per the layering table this view touches no framework service types — it
/// reads the injected `RideSessionViewModel` and renders maps through the
/// `RouteMapView` wrapper (the single MapKit touchpoint).
struct ActiveRideView: View {
    let viewModel: RideSessionViewModel

    /// Whether crash alerts are set up and on, for the small dark status chip
    /// on the ride screen (Requirement 18.6). `nil` hides it (feature not set
    /// up / MVP previews); it adds no fourth ride number.
    var crashAlertsOn: Bool?

    /// The current rear-camera recording state, when recording this ride
    /// (rear-camera task 23). `nil` when the camera is off — the existing
    /// "Rear detection off" chip then stays. Drives a calm Recording / trouble
    /// chip, icon + text.
    var cameraState: CameraRecordingState?

    /// The rear-vehicle **detection** state, when the detector is composed for
    /// this ride (on / model loading / unavailable / off). `nil` or `.off` keeps
    /// the existing recording/"off" chip. Honest: detection is experimental and
    /// cannot guarantee detection or delivery — this only reports readiness.
    var detectionState: DetectionState?

    /// Save a clip on an explicit rider action (rear-camera task 23). `nil` when
    /// the camera is off for this ride, which hides the control.
    var onSaveClip: (() -> ClipSaveOutcome)?

    /// The screen controller that owns the idle timer (and ride-mode
    /// brightness). Defaults to the shared production controller so the idle
    /// timer funnels through the one reason-counting owner, shared with the
    /// crash countdown. Tests/previews can inject a fake.
    var screen: ScreenController = UIKitScreenController.shared

    /// Brief, transient "Clip saved" / "Nothing to save yet" confirmation shown
    /// on the Save clip control (task 23).
    @State private var saveClipMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.rideBackground.ignoresSafeArea()

            // Live map fills the top; the sheet overlaps its bottom.
            RouteMapView(
                points: viewModel.points,
                mode: .live,
                currentLocation: viewModel.points.last
            )
            .ignoresSafeArea(edges: .top)

            topChrome
            bottomSheet
        }
        .preferredColorScheme(.dark)
        .onAppear { screen.setIdleTimerDisabled(true) }
        .onDisappear { screen.setIdleTimerDisabled(false) }
        .onChange(of: viewModel.banner) { _, banner in
            announceBanner(banner)
        }
        .onChange(of: viewModel.rideState) { _, state in
            announceRideState(state)
        }
    }

    // MARK: - VoiceOver announcements (Requirement 10.3)

    /// Post a VoiceOver announcement when a state banner appears so a
    /// non-visual user hears the signal-lost / permission-revoked change.
    private func announceBanner(_ banner: RideBanner?) {
        guard let banner else { return }
        let message: String?
        switch banner {
        case .signalLost:
            message = "GPS signal lost. Your ride continues and resumes automatically."
        case .permissionRevoked:
            message = "Location access turned off. Your ride is saved. Hold Stop to finish."
        case .permissionNeeded, .failed:
            message = nil
        }
        if let message { postAnnouncement(message) }
    }

    /// Announce pause/resume transitions (icon + text is also on-screen).
    private func announceRideState(_ state: RideState) {
        switch state {
        case .paused:
            postAnnouncement("Ride paused")
        case .recording:
            postAnnouncement("Recording")
        default:
            break
        }
    }

    private func postAnnouncement(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    // MARK: - Top chrome (chips + banner)

    private var topChrome: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let banner = viewModel.banner, banner.isBannerWorthy {
                RideBannerView(banner: banner)
            } else {
                HStack(alignment: .top) {
                    stateChip
                    Spacer()
                }
            }
            Spacer()
            HStack {
                cameraOrDetectionChip
                if let crashAlertsOn {
                    CrashAlertStateChip(isOn: crashAlertsOn, scheme: .dark)
                }
                Spacer()
            }
        }
        .padding(Theme.Spacing.lg)
        .padding(.bottom, 300) // keep chrome above the bottom sheet
    }

    /// The real camera/recording chip when recording this ride; otherwise the
    /// existing inert "Rear detection off" chip (Requirement 18.3). Icon + text,
    /// never colour alone; a trouble state shows a calm amber chip. While
    /// recording, the detector's state (on / model loading / unavailable) is
    /// surfaced so the rider knows whether experimental detection is running.
    @ViewBuilder private var cameraOrDetectionChip: some View {
        if let cameraState {
            switch cameraState {
            case .recording, .degraded:
                detectionChip
            case .off:
                StateChip(variant: .rearDetectionOff, scheme: .dark)
            case .preparing, .interrupted, .stopped, .stopping, .failed:
                StateChip(variant: .paused, scheme: .dark)
                    .accessibilityLabel("Camera attention needed")
            }
        } else {
            StateChip(variant: .rearDetectionOff, scheme: .dark)
        }
    }

    /// The detection chip shown while recording: reflects the detector's
    /// readiness. Falls back to the "Recording video" chip when no detector is
    /// composed for this ride (e.g. the model is off).
    @ViewBuilder private var detectionChip: some View {
        switch detectionState {
        case .on:
            StateChip(variant: .rearDetectionOn, scheme: .dark)
                .accessibilityLabel("Rear detection on, experimental")
        case .loading:
            StateChip(variant: .rearDetectionLoading, scheme: .dark)
                .accessibilityLabel("Rear detection loading")
        case .unavailable:
            StateChip(variant: .rearDetectionUnavailable, scheme: .dark)
                .accessibilityLabel("Rear detection unavailable")
        case .off, .none:
            StateChip(variant: .recording, scheme: .dark)
                .accessibilityLabel("Recording video")
        }
    }

    private var stateChip: some View {
        StateChip(variant: viewModel.rideState == .paused ? .paused : .recording, scheme: .dark)
    }

    // MARK: - Bottom sheet (metrics + controls)

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Theme.Spacing.md) {
                Capsule()
                    .fill(Theme.Colors.rideChipStroke)
                    .frame(width: 32, height: 4)
                    .padding(.top, Theme.Spacing.md)

                rideTime
                metricsRow
                controls

                if onSaveClip != nil {
                    saveClipControl
                }

                Text("Hold Stop to end ride")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.rideSecondaryText)
                    .padding(.bottom, Theme.Spacing.lg)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.rideCard)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Ride time ticks every second off a `TimelineView` reading the pure
    /// `activeDuration(at:)`; it freezes automatically while paused because the
    /// view model's active duration excludes paused spans.
    private var rideTime: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("RIDE TIME")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.Colors.rideSecondaryText)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Formatters.duration(viewModel.activeDuration(at: context.date)))
                    .font(Theme.Typography.metric(50))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Ride time \(Formatters.duration(viewModel.activeDuration(at: context.date)))")
            }
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            metric(
                value: milesValue,
                unit: "mi",
                label: "DISTANCE",
                accessibility: "Distance \(Formatters.miles(fromMeters: viewModel.distanceMeters))"
            )
            Rectangle()
                .fill(Theme.Colors.rideChipStroke)
                .frame(width: 1, height: 42)
            metric(
                value: speedValue,
                unit: "mph",
                label: "SPEED",
                accessibility: speedAccessibility
            )
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func metric(value: String, unit: String, label: String, accessibility: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.metric(26))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.rideSecondaryText)
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.Colors.rideSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: togglePause) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text(isPaused ? "Resume" : "Pause")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.minTouchTarget)
                .background(Theme.Palette.lime)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Resume ride" : "Pause ride")

            HoldToStopButton(onStop: { viewModel.stop() })
                .frame(width: 78, height: Theme.Size.minTouchTarget)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    /// The "Save clip" control shown on the ride screen when recording (task 23).
    /// Tapping saves a clip from the ring buffer and shows a brief confirmation;
    /// honest copy only — it never claims a moment was guaranteed to be captured.
    private var saveClipControl: some View {
        Button {
            guard let onSaveClip else { return }
            let outcome = onSaveClip()
            saveClipMessage = outcome == .nothingToSave ? "Nothing to save yet" : "Clip saved"
        } label: {
            Label(saveClipMessage ?? "Save clip", systemImage: "bookmark.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.minTouchTarget)
                .background(Theme.Palette.lime)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.lg)
        .accessibilityLabel(saveClipMessage ?? "Save clip")
        .accessibilityHint("Saves a clip of the last moments to this phone.")
        .onChange(of: saveClipMessage) { _, message in
            guard message != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                saveClipMessage = nil
            }
        }
    }

    // MARK: - Derived display values

    private var isPaused: Bool { viewModel.rideState == .paused }

    /// Distance always has a value; shown in miles.
    private var milesValue: String {
        numberOnly(Formatters.miles(fromMeters: viewModel.distanceMeters), unit: "mi")
    }

    /// Speed shows an em dash while paused or signal-lost (no current fix),
    /// matching mockup 3, otherwise the latest point's instantaneous speed.
    private var speedValue: String {
        guard viewModel.rideState == .recording,
              let speed = viewModel.points.last?.speedMetersPerSecond,
              speed >= 0 else {
            return "—"
        }
        return numberOnly(Formatters.mph(fromMetersPerSecond: speed), unit: "mph")
    }

    private var speedAccessibility: String {
        if speedValue == "—" { return "Speed unavailable" }
        return "Speed \(speedValue) miles per hour"
    }

    /// Strips the trailing unit so the big number and the muted unit render
    /// separately (the formatters append the unit for single-string callers).
    private func numberOnly(_ formatted: String, unit: String) -> String {
        formatted
            .replacingOccurrences(of: " \(unit)", with: "")
    }

    private func togglePause() {
        if isPaused {
            viewModel.resume()
        } else {
            viewModel.pause()
        }
    }
}

// MARK: - Banner

/// The amber signal-lost / permission-revoked banner (mockup 3). Calm, icon +
/// text, never implies the ride stopped.
private struct RideBannerView: View {
    let banner: RideBanner

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.amber)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private var title: String {
        switch banner {
        case .signalLost: return "GPS signal lost"
        case .permissionRevoked: return "Location access turned off"
        default: return ""
        }
    }

    private var subtitle: String {
        switch banner {
        case .signalLost: return "Your ride continues. Resuming…"
        case .permissionRevoked: return "Your ride is saved. Hold Stop to finish."
        default: return ""
        }
    }
}

private extension RideBanner {
    /// Only the on-screen banner cases render in the top chrome; `.failed` and
    /// `.permissionNeeded` are handled by the composition root / Home.
    var isBannerWorthy: Bool {
        switch self {
        case .signalLost, .permissionRevoked: return true
        case .permissionNeeded, .failed: return false
        }
    }
}

#Preview("Recording") {
    ActiveRideView(viewModel: PreviewSeed.activeRideViewModel(state: .recording))
}

#Preview("Paused") {
    ActiveRideView(viewModel: PreviewSeed.activeRideViewModel(state: .paused))
}
