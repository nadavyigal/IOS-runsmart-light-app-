import SwiftUI
import MapKit

/// Geometry comes from the latest fix rather than route count, which is capped.
/// Travel bearing is derived from accepted fixes; it does not require compass access.
enum LiveRunMapPresentation {
    struct Target: Equatable {
        var latitude: Double
        var longitude: Double
        var heading: Double
    }

    /// Camera distance in metres when the runner has not zoomed yet.
    static let defaultDistance = 800.0
    /// Path length behind the latest fix that the travel bearing is measured over.
    static let headingLookback = 30.0
    /// The bearing is held until the latest fix is at least this far from the lookback point.
    static let headingMinimumTravel = 10.0

    /// `previousHeading` is kept while the runner has not moved far enough for a steady bearing,
    /// so the map does not spin while standing still or on a GPS jitter.
    static func target(for points: [RunRoutePoint], previousHeading: Double? = nil) -> Target? {
        guard let last = points.last else { return nil }
        return Target(
            latitude: last.latitude,
            longitude: last.longitude,
            heading: heading(for: points) ?? previousHeading ?? 0
        )
    }

    /// Bearing from the point about `headingLookback` metres back along the current segment to the
    /// latest fix. Nil when there is no history in the segment or the runner moved under
    /// `headingMinimumTravel` metres from that point.
    static func heading(for points: [RunRoutePoint]) -> Double? {
        guard let last = points.last, points.count >= 2, last.startsNewSegment != true else { return nil }
        var anchor = last
        var pathMeters = 0.0
        var index = points.count - 1
        while index > 0, pathMeters < headingLookback {
            let current = points[index]
            if current.startsNewSegment == true { break }
            let previous = points[index - 1]
            pathMeters += meters(from: previous, to: current)
            anchor = previous
            index -= 1
        }
        guard meters(from: anchor, to: last) >= headingMinimumTravel else { return nil }
        let latitude1 = anchor.latitude * .pi / 180
        let latitude2 = last.latitude * .pi / 180
        let deltaLongitude = (last.longitude - anchor.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Camera distances outside this range are not a runner's zoom (the initial automatic camera
    /// frames far more than a run), so they never replace the remembered distance.
    static func rememberedDistance(from cameraDistance: Double, current: Double) -> Double {
        (50.0...50_000.0).contains(cameraDistance) ? cameraDistance : current
    }

    private static func meters(from a: RunRoutePoint, to b: RunRoutePoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

struct LiveRunMapPage: View {
    var points: [RunRoutePoint]
    var metrics: [MetricTile]
    var isPaused: Bool
    var isAutoPaused: Bool
    @State private var position: MapCameraPosition = .automatic
    /// Follows the runner's own pinch zoom; the camera keeps this distance on every new fix.
    @State private var cameraDistance = LiveRunMapPresentation.defaultDistance
    @State private var lastHeading: Double?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let last = points.last {
                Map(position: $position, interactionModes: [.zoom]) {
                    // Same splitter as the post-run map: a pause gap is never drawn as a line.
                    ForEach(Array(RouteMapView.lineSegments(for: points).enumerated()), id: \.offset) { _, segment in
                        MapPolyline(coordinates: segment)
                            .stroke(Color.accentPrimary, lineWidth: 5)
                    }
                    Annotation("", coordinate: last.coordinate, anchor: .center) {
                        ZStack {
                            Circle().fill(Color.accentPrimary.opacity(0.25)).frame(width: 30, height: 30)
                            Circle().fill(Color.accentPrimary).frame(width: 15, height: 15)
                            Circle().stroke(.white, lineWidth: 3).frame(width: 15, height: 15)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .onMapCameraChange(frequency: .onEnd) { context in
                    cameraDistance = LiveRunMapPresentation.rememberedDistance(from: context.camera.distance, current: cameraDistance)
                }
                .onAppear { followLatestFix() }
                .onChange(of: points.last?.id) { _, _ in followLatestFix() }
                .accessibilityLabel("Live route map, following your latest GPS position")
            } else {
                Rectangle().fill(Color.surfaceElevated)
                    .overlay {
                        Label("Waiting for GPS", systemImage: "location")
                            .foregroundStyle(Color.textSecondary)
                    }
            }

            VStack(spacing: 10) {
                if isPaused {
                    Text(isAutoPaused ? "Auto-paused · Move to resume" : "Paused")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentEnergy)
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(metrics.prefix(3))) { metric in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(metric.title)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text(metric.value)
                                .font(.metricSM)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            Text(metric.unit)
                                .font(.caption)
                                .foregroundStyle(metric.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(14)
            .background(Color.surfaceCard.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
    }

    private func followLatestFix() {
        guard let target = LiveRunMapPresentation.target(for: points, previousHeading: lastHeading) else { return }
        lastHeading = target.heading
        position = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            distance: cameraDistance,
            heading: target.heading,
            pitch: 0
        ))
    }
}
