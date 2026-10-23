import MapKit
import UIKit

/// Draws a shared route: a map snapshot with one polyline per continuous stretch. Pass the
/// points from `RouteSharePrivacy.shareableRoute`, never the full route.
enum RouteSnapshotRenderer {
    static let imageSize = CGSize(width: 640, height: 400)

    /// Region that holds every point with some padding. Pure so it can be tested.
    static func region(for points: [RunRoutePoint]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.4)
            )
        )
    }

    /// Nil when the map cannot be drawn, for example when map tiles cannot load offline.
    static func render(points: [RunRoutePoint], size: CGSize = imageSize) async -> UIImage? {
        let segments = RoutePointSegments.drawableSegments(points)
        guard !segments.isEmpty, let region = region(for: points) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            let cgContext = context.cgContext
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.setLineWidth(5)
            cgContext.setStrokeColor(UIColor(red: 0.20, green: 0.90, blue: 0.62, alpha: 1).cgColor)
            for segment in segments {
                let path = UIBezierPath()
                for (index, point) in segment.enumerated() {
                    let drawn = snapshot.point(for: point.coordinate)
                    if index == 0 { path.move(to: drawn) } else { path.addLine(to: drawn) }
                }
                cgContext.addPath(path.cgPath)
                cgContext.strokePath()
            }
        }
    }
}
