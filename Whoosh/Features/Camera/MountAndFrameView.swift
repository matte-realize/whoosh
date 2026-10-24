import SwiftUI

/// The Mount & frame screen (rear-camera spec task 22, Requirement 9, 1.2,
/// 18.2). Shown after the rider taps Start Ride while rear camera recording is
/// on: a live preview, a framing hint, a simple level indicator, a camera choice
/// (Back / Front), a big "Start ride" that begins the ride and enters ride mode,
/// and a "Ride without camera" path that keeps the normal ride.
///
/// The view is dumb: it observes `MountAndFrameViewModel` and sends intents. It
/// shows the live preview through `CameraPreviewView` (which wraps the capture
/// service's `CameraPreviewHost`), so it imports no AVFoundation or Core Motion.
///
/// Honesty (privacy steering): the copy says recording is for the rider's own
/// records and may fail; it never calls footage evidence or claims assured
/// capture, and it says Whoosh cannot guarantee detection or delivery.
struct MountAndFrameView: View {
    @Bindable var viewModel: MountAndFrameViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                preview
                controls
            }
        }
        .onAppear { viewModel.startLevel() }
        .task { await viewModel.startPreview() }
        .onDisappear {
            viewModel.stopLevel()
            viewModel.stopPreviewIfNeeded()
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            CameraPreviewView(host: viewModel.host)
                .ignoresSafeArea(edges: .top)

            if viewModel.permissionStatus == .denied || viewModel.permissionStatus == .restricted {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 32))
                    Text("Camera access is off")
                        .font(.headline)
                    Text("Allow Camera for Whoosh in Settings to record and detect vehicles behind you.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
                .padding(24)
            }

            // Framing guide: the road behind should fill the lower two-thirds.
            VStack {
                Rectangle()
                    .fill(.white.opacity(0.0))
                    .frame(height: 1)
                    .overlay(alignment: .center) {
                        Text("Aim the camera at the road behind you")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, Theme.Spacing.xl)
                    }
                Spacer()
            }

            // Level indicator (top-right).
            VStack {
                HStack {
                    Spacer()
                    levelPill
                        .padding(Theme.Spacing.md)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var levelPill: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.isLevel ? "level.fill" : "level")
                .font(.system(size: 13, weight: .semibold))
            Text(viewModel.levelLabel)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(viewModel.isLevel ? Theme.Palette.ink : .white)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(viewModel.isLevel ? Theme.Palette.lime : Color.white.opacity(0.2))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mount level: \(viewModel.levelLabel)")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Theme.Spacing.md) {
            cameraChoice

            Text("Recording is for your own records. It may fail — heat, a locked phone, or low storage can stop it — and Whoosh cannot guarantee detection or delivery.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.lg)

            Button {
                viewModel.startWithCamera()
            } label: {
                Text("Start ride")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Size.minTouchTarget)
                    .background(Theme.Palette.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts the ride and dims the screen while the camera and GPS run.")

            Button {
                viewModel.skipCamera()
            } label: {
                Text("Ride without camera")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Size.minTouchTarget)
                    .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a normal ride without recording video.")
        }
        .padding(Theme.Spacing.lg)
        .background(Color.black)
    }

    private var cameraChoice: some View {
        HStack {
            Text("Camera")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Picker("Camera", selection: Binding(
                get: { viewModel.settings.cameraPosition },
                set: { viewModel.setCameraPosition($0) }
            )) {
                ForEach(CameraDevicePosition.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera, \(viewModel.settings.cameraPosition.displayName)")
    }
}
