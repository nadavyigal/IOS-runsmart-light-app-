import SwiftUI
import MapKit

struct RouteMapView: View {
    var points: [RunRoutePoint]
    var title: String?
    var isLive = false
    @State private var position: MapCameraPosition = .region(Self.defaultRegion)

    private var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    /// One polyline per continuous stretch. A pause or a recovered-run resume starts a new
    /// segment (`startsNewSegment`), and the runner may have moved while recording was off, so
    /// the gap must not be drawn as a straight line. Stretches of a single point cannot be drawn.
    static func lineSegments(for points: [RunRoutePoint]) -> [[CLLocationCoordinate2D]] {
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        for point in points {
            if point.startsNewSegment == true, !current.isEmpty {
                segments.append(current)
                current = []
            }
            current.append(point.coordinate)
        }
        if !current.isEmpty { segments.append(current) }
        return segments.filter { $0.count >= 2 }
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    )

    /// Live span (~800 m) the camera keeps while following the runner.
    static let liveFollowSpanDegrees: CLLocationDegrees = 0.008

    /// Live camera: centered on the latest fix with a fixed span.
    static func liveFollowRegion(for last: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: last,
            span: MKCoordinateSpan(latitudeDelta: liveFollowSpanDegrees, longitudeDelta: liveFollowSpanDegrees)
        )
    }

    /// Changes whenever the camera should move. Live: the last coordinate (the display route is
    /// capped, so a point count would stop changing). Post-run: the point count bucket.
    struct CameraKey: Equatable {
        var count: Int
        var lastLatitude: Double?
        var lastLongitude: Double?
    }

    static func cameraKey(for coordinates: [CLLocationCoordinate2D], isLive: Bool) -> CameraKey {
        if isLive {
            return CameraKey(count: min(coordinates.count, 2), lastLatitude: coordinates.last?.latitude, lastLongitude: coordinates.last?.longitude)
        }
        let bucket = coordinates.count < 3 ? coordinates.count : coordinates.count / 20
        return CameraKey(count: bucket, lastLatitude: nil, lastLongitude: nil)
    }

    private var region: MKCoordinateRegion {
        if isLive, let last = coordinates.last {
            return Self.liveFollowRegion(for: last)
        }
        guard !coordinates.isEmpty else {
            return Self.defaultRegion
        }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? coordinates[0].latitude
        let maxLat = latitudes.max() ?? coordinates[0].latitude
        let minLon = longitudes.min() ?? coordinates[0].longitude
        let maxLon = longitudes.max() ?? coordinates[0].longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.7), longitudeDelta: max(0.01, (maxLon - minLon) * 1.7))
        )
    }

    private var cameraKey: CameraKey {
        Self.cameraKey(for: coordinates, isLive: isLive)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if coordinates.count >= 2 {
                Map(position: $position) {
                    ForEach(Array(Self.lineSegments(for: points).enumerated()), id: \.offset) { _, segment in
                        MapPolyline(coordinates: segment)
                            .stroke(Color.accentPrimary, lineWidth: 5)
                    }
                    if let first = coordinates.first {
                        Marker("Start", systemImage: "play.fill", coordinate: first)
                            .tint(.green)
                    }
                    if isLive, let last = coordinates.last {
                        Annotation("", coordinate: last, anchor: .center) {
                            LivePositionMarker()
                        }
                    } else if let last = coordinates.last {
                        Marker("Finish", systemImage: "flag.fill", coordinate: last)
                            .tint(.red)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onAppear {
                    position = .region(region)
                }
                .onChange(of: cameraKey) { _, _ in
                    position = .region(region)
                }
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.title)
                            .foregroundStyle(Color.accentPrimary)
                        Text("Map appears when GPS points are available")
                            .font(.caption)
                            .foregroundStyle(Color.mutedText)
                    }
                }
            }

            if let title {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LivePositionMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentPrimary.opacity(0.22))
                .frame(width: 24, height: 24)
            Circle()
                .fill(Color.accentPrimary)
                .frame(width: 12, height: 12)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}
