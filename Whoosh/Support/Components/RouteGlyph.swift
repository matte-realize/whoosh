import SwiftUI

/// A tiny route thumbnail that draws a normalized mini-polyline from a ride's
/// `[RoutePoint]`, used as the leading square on each `RideRow` (matches the
/// "thumb" glyphs in the Home and History mockups).
///
/// Pure drawing: it normalizes the points' longitude/latitude into the unit
/// square, flips Y so north is up, and strokes a lime path on a dark tile. It is
/// safe for empty and single-point routes — those render a small centered dot
/// instead of a line, so a ride with no usable track never produces an empty or
/// crashing glyph. This is a lightweight stand-in that does **not** import
/// MapKit (keeping MapKit isolated to `RouteMapView`).
struct RouteGlyph: View {
    let points: [RoutePoint]
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Theme.Colors.rideBackground)
            GeometryReader { proxy in
                let inset: CGFloat = 8
                let rect = CGRect(origin: .zero, size: proxy.size)
                    .insetBy(dx: inset, dy: inset)
                let normalized = Self.normalizedPoints(points, in: rect)

                if normalized.count >= 2 {
                    Path { path in
                        path.move(to: normalized[0])
                        for point in normalized.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        Theme.Palette.lime,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    // Empty or single-point route: a small centered dot.
                    Circle()
                        .fill(Theme.Palette.lime)
                        .frame(width: 5, height: 5)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Map geographic points into screen coordinates inside `rect`, preserving
    /// aspect by centering, and flipping Y so increasing latitude points up.
    /// Returns an empty array for fewer than two points.
    static func normalizedPoints(_ points: [RoutePoint], in rect: CGRect) -> [CGPoint] {
        guard points.count >= 2 else { return [] }

        let lons = points.map(\.longitude)
        let lats = points.map(\.latitude)
        guard let minLon = lons.min(), let maxLon = lons.max(),
              let minLat = lats.min(), let maxLat = lats.max() else {
            return []
        }

        let spanLon = max(maxLon - minLon, 1e-9)
        let spanLat = max(maxLat - minLat, 1e-9)
        // Uniform scale so the route keeps its shape; center within rect.
        let scale = min(rect.width / spanLon, rect.height / spanLat)
        let drawnWidth = spanLon * scale
        let drawnHeight = spanLat * scale
        let offsetX = rect.minX + (rect.width - drawnWidth) / 2
        let offsetY = rect.minY + (rect.height - drawnHeight) / 2

        return points.map { point in
            let x = offsetX + (point.longitude - minLon) * scale
            // Flip Y: higher latitude → smaller y (towards the top).
            let y = offsetY + (maxLat - point.latitude) * scale
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview("RouteGlyph") {
    let base = Date()
    let points: [RoutePoint] = (0..<8).map { i in
        let lat: Double = 42.36 + Double(i) * 0.001 + (i % 2 == 0 ? 0.0005 : 0)
        let lon: Double = -71.09 + Double(i) * 0.0012
        let time = base.addingTimeInterval(Double(i) * 10)
        return RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: time,
            speedMetersPerSecond: 5,
            horizontalAccuracyMeters: 5
        )
    }
    return HStack(spacing: 12) {
        RouteGlyph(points: points)
        RouteGlyph(points: [])
        RouteGlyph(points: Array(points.prefix(1)))
    }
    .padding()
    .background(Theme.Colors.screenBackground)
}
