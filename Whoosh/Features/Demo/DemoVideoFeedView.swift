import AVFoundation
import SwiftUI
import UIKit

/// Full-screen demo of the rear camera: the bundled road clip stands in for the
/// live feed, the real vision model draws its boxes over it, and each flagged
/// vehicle fires the normal rear-vehicle cue on the phone and the watch.
struct DemoVideoFeedView: View {
    @State var feed: DemoVideoFeed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                header
                Spacer()
                if feed.player != nil {
                    ZStack {
                        PlayerLayerView(player: feed.player)
                        DetectionOverlay(boxes: feed.boxes)
                    }
                    .aspectRatio(feed.videoSize, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Demo clip missing from the app bundle.")
                        .foregroundStyle(.white)
                }
                status
                Spacer()
            }
            .padding()
        }
        .onAppear { feed.start() }
        .onDisappear { feed.stop() }
    }

    private var header: some View {
        HStack {
            Text("DEMO · Rear camera")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.amber)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minHeight: Theme.Size.minTouchTarget)
        }
    }

    private var status: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            ProgressView(value: feed.proximity)
                .tint(feed.proximity > 0.6 ? Theme.Palette.alert : Theme.Palette.amber)
                .animation(.easeOut(duration: 0.2), value: feed.proximity)
                .accessibilityLabel("Approaching car closeness")
            Text("Recorded clip played through the live detector. Experimental cue — cannot guarantee detection or delivery.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var statusText: String {
        switch feed.modelState {
        case .loading: return "Loading vehicle model…"
        case .unavailable: return "Vehicle model unavailable"
        case .ready:
            return feed.alertCount == 0
                ? "Watching for vehicles behind you"
                : feed.proximity > 0 ? "Car closing in · dings: \(feed.alertCount)" : "Dings sent: \(feed.alertCount)"
        }
    }
}

/// A bare `AVPlayerLayer` host (no playback controls).
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
