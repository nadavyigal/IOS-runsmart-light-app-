import SwiftUI
import MapKit

struct RouteMapView: View {
    var points: [RunRoutePoint]
    var title: String?
    @State private var position: MapCameraPosition = .region(Self.defaultRegion)

    private var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    )

    private var region: MKCoordinateRegion {
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

    private var cameraUpdateToken: Int {
        if coordinates.count < 3 { return coordinates.count }
        return coordinates.count / 20
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if coordinates.count >= 2 {
                Map(position: $position) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.accentPrimary, lineWidth: 5)
                    if let first = coordinates.first {
                        Marker("Start", systemImage: "play.fill", coordinate: first)
                            .tint(.green)
                    }
                    if let last = coordinates.last {
                        Marker("Finish", systemImage: "flag.fill", coordinate: last)
                            .tint(.red)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onAppear {
                    position = .region(region)
                }
                .onChange(of: cameraUpdateToken) { _, _ in
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
