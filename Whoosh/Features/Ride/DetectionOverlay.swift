import SwiftUI

/// Draws the experimental vision detections over the live camera preview on the
/// active ride screen (owner device-testing feedback: "draw the vision
/// detections on top of it: a box per detected vehicle … with the approaching
/// vehicle highlighted in the alert color"). Pure, dumb view: it takes the
/// view-only `DetectionOverlayBox`es (normalized `0...1`, top-left origin in the
/// displayed image) and maps them into the available space with a single
/// `GeometryReader`. It imports no AVFoundation/Vision and holds no camera
/// state — the boxes are display-only and never the alert / near-miss path.
///
/// Honesty (privacy steering): the label + confidence are shown as-is; a box is
/// only what the model saw in one frame. Detection is experimental and cannot
/// guarantee detection or delivery, so the overlay never says "warning",
/// "danger", or implies a guaranteed catch.
struct DetectionOverlay: View {
    /// The latest per-frame boxes to draw (empty draws nothing).
    let boxes: [DetectionOverlayBox]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ForEach(boxes) { box in
                boxView(box, in: size)
            }
        }
        .allowsHitTesting(false) // overlay never intercepts touches
        .accessibilityHidden(true) // the chip reports detection state; boxes are visual
    }

    @ViewBuilder
    private func boxView(_ box: DetectionOverlayBox, in size: CGSize) -> some View {
        let rect = CGRect(
            x: box.x * size.width,
            y: box.y * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
        let color = box.isApproaching ? Theme.Palette.alert : Theme.Palette.lime

        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(color, lineWidth: box.isApproaching ? 3 : 2)
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .overlay(alignment: .topLeading) {
                Text(labelText(box))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .fixedSize()
                    // Sit the tag just above the box when there's room.
                    .offset(y: -18)
            }
            .position(x: rect.midX, y: rect.midY)
    }

    /// "car 82%" — the class label and confidence, shown as-is (not a promise).
    private func labelText(_ box: DetectionOverlayBox) -> String {
        let pct = Int((box.confidence * 100).rounded())
        return "\(box.label) \(pct)%"
    }
}

#Preview("Boxes") {
    ZStack {
        Color.black
        DetectionOverlay(boxes: [
            DetectionOverlayBox(label: "car", confidence: 0.82, x: 0.3, y: 0.4, width: 0.25, height: 0.2, isApproaching: true),
            DetectionOverlayBox(label: "truck", confidence: 0.61, x: 0.05, y: 0.2, width: 0.15, height: 0.12)
        ])
    }
    .ignoresSafeArea()
}
