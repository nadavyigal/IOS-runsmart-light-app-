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

    static func target(for points: [RunRoutePoint]) -> Target? {
        guard let last = points.last else { return nil }
        var heading = 0.0
        if points.count >= 2, last.startsNewSegment != true {
            let previous = points[points.count - 2]
            let latitude1 = previous.latitude * .pi / 180
            let latitude2 = last.latitude * .pi / 180
            let deltaLongitude = (last.longitude - previous.longitude) * .pi / 180
            let y = sin(deltaLongitude) * cos(latitude2)
            let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
            heading = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        }
        return Target(latitude: last.latitude, longitude: last.longitude, heading: heading)
    }
}

struct LiveRunMapPage: View {
    var points: [RunRoutePoint]
    var metrics: [MetricTile]
    var isPaused: Bool
    var isAutoPaused: Bool
    @State private var position: MapCameraPosition = .automatic

    private var cameraTarget: LiveRunMapPresentation.Target? {
        LiveRunMapPresentation.target(for: points)
    }

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
                .onAppear { followLatestFix() }
                .onChange(of: cameraTarget) { _, _ in followLatestFix() }
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
        guard let target = cameraTarget else { return }
        position = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            distance: 800,
            heading: target.heading,
            pitch: 0
        ))
    }
}
