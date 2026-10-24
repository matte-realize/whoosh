import SwiftUI
import MapKit

/// The single MapKit touchpoint in the app (Requirement 5.1 / 5.6; design
/// "MapKit isolation"). Every map in Whoosh — the live active-ride map, the
/// summary map, and the history-detail map — goes through this one wrapper, so a
/// future renderer swap touches only this file. No other view imports MapKit;
/// the only other MapKit-adjacent file is the Core Location tracker.
///
/// Renders the recorded route as a **lime polyline with a dark casing** (a
/// wider ink stroke beneath a narrower lime stroke, for contrast on any map
/// style) plus start/end markers, and supports two modes:
///
/// - `.live` — a growing route that auto-follows the current location. Manual
///   panning pauses auto-follow and reveals a recenter button; tapping it
///   resumes following. Uses a dark map style, matching the dark ride screen.
/// - `.static` — fits the full route in view with padding; no follow. Used by
///   the summary and history detail.
///
/// Empty and single-point routes are handled without crashing: with no points
/// the map simply shows the region (current location if known, else a sensible
/// default); a single point drops one marker.
struct RouteMapView: View {
    enum Mode {
        /// Growing route with auto-follow and a recenter affordance (ride screen).
        case live
        /// Full-route fit with padding, no follow (summary / history detail).
        case `static`
    }

    let points: [RoutePoint]
    var mode: Mode = .static
    /// The current location for the live user indicator (optional; `nil` hides it).
    var currentLocation: RoutePoint?

    @State private var cameraPosition: MapCameraPosition = .automatic
    /// `true` once the user manually pans in live mode, pausing auto-follow.
    @State private var followPaused = false
    /// Tracks whether we have performed the initial static fit.
    @State private var didFitStatic = false

    var body: some View {
        Map(position: $cameraPosition) {
            if let polyline {
                // Dark casing beneath the lime line for contrast on any basemap.
                MapPolyline(coordinates: polyline)
                    .stroke(Theme.Palette.ink, style: casingStyle)
                MapPolyline(coordinates: polyline)
                    .stroke(Theme.Palette.lime, style: lineStyle)
            }

            if let start = points.first {
                Annotation("Start", coordinate: start.coordinate) {
                    StartMarker()
                }
                .annotationTitles(.hidden)
            }

            if points.count >= 2, let end = points.last {
                Annotation("End", coordinate: end.coordinate) {
                    EndMarker()
                }
                .annotationTitles(.hidden)
            }

            if mode == .live, let current = currentLocation {
                Annotation("You", coordinate: current.coordinate) {
                    UserDot()
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        .onMapCameraChange(frequency: .onEnd) { _ in
            // In live mode a manual pan pauses auto-follow until recenter.
            if mode == .live, isFollowing {
                followPaused = true
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if mode == .live && followPaused {
                recenterButton
            }
        }
        .onAppear { configureInitialCamera() }
        .onChange(of: currentLocation) { _, _ in followIfNeeded() }
        .onChange(of: points.count) { _, _ in fitStaticIfNeeded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    // MARK: - Camera

    private var isFollowing: Bool { mode == .live && !followPaused }

    private func configureInitialCamera() {
        switch mode {
        case .live:
            followIfNeeded(force: true)
        case .static:
            fitStaticIfNeeded(force: true)
        }
    }

    private func followIfNeeded(force: Bool = false) {
        guard mode == .live, (isFollowing || force) else { return }
        guard let target = currentLocation ?? points.last else {
            cameraPosition = .automatic
            return
        }
        followPaused = false
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: target.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                )
            )
        }
    }

    private func fitStaticIfNeeded(force: Bool = false) {
        guard mode == .static else { return }
        guard force || !didFitStatic else { return }
        didFitStatic = true
        guard let region = boundingRegion(for: points) else {
            cameraPosition = .automatic
            return
        }
        cameraPosition = .region(region)
    }

    private var recenterButton: some View {
        Button {
            followIfNeeded(force: true)
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.lime)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
        .padding(Theme.Spacing.lg)
        .accessibilityLabel(Text("Recenter map on your location"))
    }

    // MARK: - Geometry

    private var polyline: [CLLocationCoordinate2D]? {
        guard points.count >= 2 else { return nil }
        return points.map(\.coordinate)
    }

    /// A region that encloses all points with padding, or `nil` if there are none.
    /// A single point yields a small region centered on it.
    private func boundingRegion(for points: [RoutePoint]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        if points.count == 1 {
            return MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            )
        }
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return nil
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // 1.4× padding, with a floor so a short route isn't over-zoomed.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.003),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.003)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var mapStyle: MapStyle {
        switch mode {
        case .live:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .static:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }

    private var lineStyle: StrokeStyle {
        StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }

    private var casingStyle: StrokeStyle {
        StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
    }

    private var accessibilityLabel: String {
        if points.isEmpty {
            return "Route map, no route recorded yet"
        }
        let distance = RideMetrics.distanceMeters(points)
        return "Route map, \(Formatters.miles(fromMeters: distance))"
    }
}

// MARK: - Markers

private struct StartMarker: View {
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Theme.Palette.ink, lineWidth: 2.5))
            .accessibilityHidden(true)
    }
}

private struct EndMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.ink).frame(width: 16, height: 16)
            Circle().fill(Theme.Palette.lime).frame(width: 7, height: 7)
        }
        .accessibilityHidden(true)
    }
}

private struct UserDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.lime.opacity(0.18)).frame(width: 44, height: 44)
            Circle().fill(.white).frame(width: 18, height: 18)
            Circle().fill(Theme.Palette.lime).frame(width: 11, height: 11)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - RoutePoint → CLLocationCoordinate2D

private extension RoutePoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview("Static route") {
    let base = Date()
    let points: [RoutePoint] = (0..<12).map { i in
        let lat: Double = 42.36 + Double(i) * 0.0012 + (i % 3 == 0 ? 0.0008 : 0)
        let lon: Double = -71.095 + Double(i) * 0.0015
        let time = base.addingTimeInterval(Double(i) * 10)
        return RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: time,
            speedMetersPerSecond: 6,
            horizontalAccuracyMeters: 5
        )
    }
    return RouteMapView(points: points, mode: .static)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
}

#Preview("Empty route") {
    RouteMapView(points: [], mode: .static)
        .frame(height: 300)
        .padding()
}
