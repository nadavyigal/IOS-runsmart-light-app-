import CoreLocation
import CoreImage
import CoreImage.CIFilterBuiltins
import MapKit
import SwiftUI
import UIKit

/// Projected points retain their original order. A repeated coordinate on an out-and-back
/// remains a second visit; a pause/hidden section remains a break, never a connecting line.
struct RunShareProjectedPoint {
    var position: CGPoint
    var startsNewSegment: Bool
    var cumulativeMeters: Double
}

struct RunShareMapPlate {
    var image: UIImage
    var attribution: UIImage?
    var points: [RunShareProjectedPoint]
    var contentSize: CGSize
}

@MainActor
enum RunSharePosterRenderer {
    static let ink = UIColor(red: 6 / 255, green: 6 / 255, blue: 10 / 255, alpha: 1)
    static let lime = UIColor(red: 0.8, green: 1, blue: 0, alpha: 1)
    static let white = UIColor(red: 0.95, green: 0.95, blue: 1, alpha: 1)
    static let muted = UIColor(red: 0.71, green: 0.75, blue: 0.80, alpha: 1)

    static func mapHeight(for format: RunShareAssetFormat) -> CGFloat {
        format == .feed ? 940 : 1_280
    }

    /// A map uses only the already-private snapshot route. No demo or route service is consulted.
    static func prepareMap(snapshot: RunShareSnapshot, format: RunShareAssetFormat) async throws -> RunShareMapPlate? {
        guard !snapshot.routePoints.isEmpty else { return nil }
        try Task.checkCancellation()
        let points = snapshot.routePoints
        guard points.count >= 2,
              points.allSatisfy({ CLLocationCoordinate2DIsValid($0.coordinate) }) else {
            throw RunShareMediaError.invalidRoute
        }

        let size = CGSize(width: 1_080, height: mapHeight(for: format))
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = 1.5
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = true
        let bounds = boundingMapRect(points)
        options.mapRect = bounds
        if format == .video { options.camera = videoCamera(for: bounds) }

        var map = try await captureMap(options: options)
        // Pitch can project a very unusual shape outside the original plate. Back away once
        // before accepting it; this is preparation, never a per-frame tile request.
        if format == .video, !projectedRouteFits(points, snapshot: map, size: size) {
            let fartherCamera = videoCamera(for: bounds)
            fartherCamera.centerCoordinateDistance *= 1.65
            options.camera = fartherCamera
            map = try await captureMap(options: options)
            guard projectedRouteFits(points, snapshot: map, size: size) else {
                throw RunShareMediaError.mapUnavailable
            }
        }
        try Task.checkCancellation()

        // The animation may crop/translate the map. Preserve MapKit's original logo/legal strip
        // separately and draw it, untransformed and unobscured, on every output frame.
        let attributionHeight: CGFloat = 50
        let contentHeight = size.height - attributionHeight
        let tonedImage = toneMapImage(map.image)
        guard let cgImage = tonedImage.cgImage,
              let mapCG = cgImage.cropping(to: CGRect(
                x: 0, y: 0, width: CGFloat(cgImage.width), height: contentHeight * map.image.scale
              )),
              let creditsCG = cgImage.cropping(to: CGRect(
                x: 0, y: contentHeight * map.image.scale,
                width: CGFloat(cgImage.width), height: attributionHeight * map.image.scale
              )) else { throw RunShareMediaError.mapUnavailable }

        var projected: [RunShareProjectedPoint] = []
        var cumulative = 0.0
        for (index, point) in points.enumerated() {
            if index > 0, point.startsNewSegment != true {
                let previous = points[index - 1]
                cumulative += CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            }
            let position = map.point(for: point.coordinate)
            guard position.x.isFinite, position.y.isFinite else { throw RunShareMediaError.invalidRoute }
            projected.append(RunShareProjectedPoint(
                position: position,
                startsNewSegment: index == 0 || point.startsNewSegment == true,
                cumulativeMeters: cumulative
            ))
        }
        return RunShareMapPlate(
            image: UIImage(cgImage: mapCG, scale: map.image.scale, orientation: .up),
            attribution: UIImage(cgImage: creditsCG, scale: map.image.scale, orientation: .up),
            points: projected,
            contentSize: CGSize(width: size.width, height: contentHeight)
        )
    }

    private static let toneContext = CIContext(options: [.cacheIntermediates: false])

    /// Brighten native dark geography without converting it to a pale daylight basemap.
    /// Applying this before the attribution split keeps the original legal strip consistent.
    static func toneMapImage(_ image: UIImage) -> UIImage {
        guard let source = image.cgImage else { return image }
        let controls = CIFilter.colorControls()
        controls.inputImage = CIImage(cgImage: source)
        controls.saturation = 0.70
        controls.brightness = 0.08
        controls.contrast = 1.04
        guard let controlled = controls.outputImage else { return image }
        let grade = CIFilter.colorMatrix()
        grade.inputImage = controlled
        grade.rVector = CIVector(x: 0.88, y: 0, z: 0, w: 0)
        grade.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        grade.bVector = CIVector(x: 0, y: 0, z: 1.08, w: 0)
        grade.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        grade.biasVector = CIVector(x: 0, y: 0.006, z: 0.022, w: 0)
        guard let output = grade.outputImage,
              let cgImage = toneContext.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// A fixed native perspective, with the full privacy-trimmed extent inside the plate.
    /// The video then follows the projected chronological path on this one bounded snapshot.
    static func videoCamera(for bounds: MKMapRect) -> MKMapCamera {
        let center = MKMapPoint(x: bounds.midX, y: bounds.midY).coordinate
        let pointsPerMeter = max(0.001, MKMapPointsPerMeterAtLatitude(center.latitude))
        let spanMeters = max(bounds.width, bounds.height) / pointsPerMeter
        return MKMapCamera(lookingAtCenter: center, fromDistance: max(1_500, spanMeters * 1.5),
                           pitch: 36, heading: 0)
    }

    private static func projectedRouteFits(_ points: [RunRoutePoint], snapshot: MKMapSnapshotter.Snapshot, size: CGSize) -> Bool {
        let content = CGRect(x: 36, y: 36, width: size.width - 72, height: size.height - 122)
        return points.allSatisfy { content.contains(snapshot.point(for: $0.coordinate)) }
    }

    private static func captureMap(options: MKMapSnapshotter.Options) async throws -> MKMapSnapshotter.Snapshot {
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await withTaskCancellationHandler {
                try await snapshotter.start()
            } onCancel: {
                snapshotter.cancel()
            }
            try Task.checkCancellation()
            return snapshot
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw RunShareMediaError.mapUnavailable
        }
    }

    /// Uses a wrapped Mercator extent, rather than a longitude min/max, for date-line routes.
    static func boundingMapRect(_ points: [RunRoutePoint]) -> MKMapRect {
        guard let first = points.first else { return .world }
        let width = MKMapRect.world.size.width
        let referenceX = MKMapPoint(first.coordinate).x
        var minX = referenceX, maxX = referenceX
        var minY = MKMapPoint(first.coordinate).y, maxY = minY
        for point in points {
            var p = MKMapPoint(point.coordinate)
            if p.x - referenceX > width / 2 { p.x -= width }
            if referenceX - p.x > width / 2 { p.x += width }
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let minimumSpan = 750 * MKMapPointsPerMeterAtLatitude(first.latitude)
        let w = max(minimumSpan, maxX - minX)
        let h = max(minimumSpan, maxY - minY)
        // Room for the hero typography and a complete-route finish, including narrow out-and-backs.
        return MKMapRect(x: (minX + maxX - w) / 2, y: (minY + maxY - h) / 2, width: w, height: h)
            .insetBy(dx: -w * 0.32, dy: -h * 0.32)
    }

    static func image(
        snapshot: RunShareSnapshot,
        format: RunShareAssetFormat,
        map: RunShareMapPlate?,
        logo: UIImage?,
        time: Double? = nil
    ) -> UIImage {
        let configuration = UIGraphicsImageRendererFormat()
        configuration.scale = 1
        configuration.opaque = true
        let size = format.pixelSize
        return UIGraphicsImageRenderer(size: size, format: configuration).image { renderer in
            draw(snapshot: snapshot, format: format, map: map, logo: logo,
                 time: time, context: renderer.cgContext, size: size)
        }
    }

    static func logoImage() -> UIImage? {
        let renderer = ImageRenderer(content: RunSmartLogoMark(size: 64, filled: true, glow: false))
        renderer.scale = 2
        return renderer.uiImage
    }

    static func draw(
        snapshot: RunShareSnapshot,
        format: RunShareAssetFormat,
        map: RunShareMapPlate?,
        logo: UIImage?,
        time: Double?,
        context: CGContext,
        size: CGSize
    ) {
        let feed = format == .feed
        let video = time != nil
        let mapHeight = mapHeight(for: format)
        ink.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        if let map {
            context.saveGState()
            context.clip(to: CGRect(origin: .zero, size: map.contentSize))
            let transform = cameraTransform(points: map.points, contentSize: map.contentSize, time: time)
            context.concatenate(transform)
            map.image.draw(in: CGRect(origin: .zero, size: map.contentSize))
            // The plate and legal strip receive the same dark blue-gray tone treatment.
            drawRoute(map.points, progress: time.map(replayProgress) ?? 1, context: context,
                      width: 8 / max(transform.a, 1))
            context.restoreGState()
            // Credits are copied from the actual map snapshot, not recreated or obscured.
            map.attribution?.draw(in: CGRect(x: 0, y: mapHeight - 50, width: size.width, height: 50))
        }

        drawGradient(context, rect: CGRect(x: 0, y: 0, width: size.width, height: feed ? 420 : 660),
                     colors: [ink.withAlphaComponent(0.82), ink.withAlphaComponent(0.02)])
        if map != nil {
            // A restrained, continuous fade crosses the join, so the legal strip does not
            // become a differently colored band. Native logo/legal text remains visible.
            drawGradient(context,
                         rect: CGRect(x: 0, y: mapHeight - 280, width: size.width, height: 280),
                         colors: [ink.withAlphaComponent(0), ink.withAlphaComponent(0.26)])
        }

        let headerY: CGFloat = feed ? 120 : 300
        logo?.draw(in: CGRect(x: 74, y: headerY - 48, width: 62, height: 62))
        drawText("RUN", at: CGPoint(x: 155, y: headerY - 43), size: 43, weight: .black)
        let runWidth = textSize("RUN", size: 43, weight: .black).width
        drawText("SMART", at: CGPoint(x: 155 + runWidth + 2, y: headerY - 43), size: 43, weight: .black, color: lime)
        drawFittedText(snapshot.dateLabel, in: CGRect(x: 720, y: headerY - 36, width: 286, height: 40),
                       size: 26, weight: .semibold, color: muted, alignment: .right)

        let heroY: CGFloat = feed ? 175 : 350
        var heroSize: CGFloat = feed ? 220 : 260
        while heroSize > 48, textSize(snapshot.distanceLabel, size: heroSize, weight: .heavy).width > 720 { heroSize -= 2 }
        drawText(snapshot.distanceLabel, at: CGPoint(x: 70, y: heroY), size: heroSize, weight: .heavy)
        let numberWidth = textSize(snapshot.distanceLabel, size: heroSize, weight: .heavy).width
        drawText(snapshot.distanceUnit, at: CGPoint(x: 88 + numberWidth, y: heroY + heroSize * 0.60),
                 size: min(64, heroSize * 0.35), weight: .bold, color: lime)

        if map == nil {
            drawFittedText(snapshot.title, in: CGRect(x: 76, y: feed ? 490 : 760, width: 928, height: 110),
                           size: 48, weight: .bold)
            drawText("YOUR RUN. YOUR PROGRESS.", at: CGPoint(x: 77, y: feed ? 650 : 940),
                     size: 25, weight: .semibold, color: lime)
        }

        let metricsY: CGFloat = feed ? 1_035 : 1_395
        let metricAlpha = time.map { smooth(($0 - 7.0) / 0.65) } ?? 1
        context.saveGState(); context.setAlpha(metricAlpha)
        drawText("MOVING TIME", at: CGPoint(x: 78, y: metricsY - 86), size: 23, weight: .semibold, color: muted)
        drawFittedText(snapshot.durationLabel, in: CGRect(x: 74, y: metricsY - 52, width: 420, height: 90), size: 68, weight: .bold)
        drawText("AVG PACE", at: CGPoint(x: 594, y: metricsY - 86), size: 23, weight: .semibold, color: muted)
        drawFittedText(snapshot.paceLabel, in: CGRect(x: 590, y: metricsY - 52, width: 418, height: 90), size: 62, weight: .bold)
        context.restoreGState()

        let finishAlpha = time.map { smooth(($0 - 7.4) / 0.65) } ?? 1
        context.saveGState(); context.setAlpha(finishAlpha)
        if !snapshot.insight.isEmpty {
            drawFittedText(snapshot.insight,
                           in: CGRect(x: 77, y: feed ? 1_130 : 1_480, width: 928, height: 78),
                           size: 40, weight: .bold, color: lime)
        }
        drawText(RunShareSnapshot.appStoreCallToAction, at: CGPoint(x: 77, y: feed ? 1_240 : 1_580),
                 size: 30, weight: .semibold, color: lime)
        context.restoreGState()
        drawFittedText(snapshot.sourceLabel, in: CGRect(x: 77, y: feed ? 1_085 : 1_445, width: 928, height: 36),
                       size: 18, weight: .medium, color: muted)
        if video {
            let phase = (time ?? 0) < 6.8 ? "ROUTE REPLAY" : "RUN COMPLETE"
            drawText(map == nil ? "RUN RECAP" : phase,
                     at: CGPoint(x: 77, y: 1_178), size: 22, weight: .semibold, color: lime)
        }
    }

    /// Camera follows the chronological head and pulls back. Bounds prevent blank map edges.
    static func cameraTransform(points: [RunShareProjectedPoint], contentSize: CGSize, time: Double?) -> CGAffineTransform {
        guard let time, let head = routeHead(points, progress: replayProgress(time)) else { return .identity }
        let pullback = smooth((time - 6.8) / 1.2)
        let zoom = (1.22 + 0.43 * smooth(time / 0.7)) * (1 - pullback) + pullback
        let targetX = contentSize.width * 0.5
        let targetY = contentSize.height * 0.61
        let rawX = targetX - head.x * zoom
        let rawY = targetY - head.y * zoom
        let x = min(0, max(contentSize.width * (1 - zoom), rawX)) * (1 - pullback)
        let y = min(0, max(contentSize.height * (1 - zoom), rawY)) * (1 - pullback)
        return CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: x, ty: y)
    }

    static func replayProgress(_ time: Double) -> Double { min(1, max(0, (time - 0.6) / 6.2)) }
    static func smooth(_ value: Double) -> Double {
        let p = min(1, max(0, value)); return p * p * (3 - 2 * p)
    }

    static func routeHead(_ points: [RunShareProjectedPoint], progress: Double) -> CGPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        let target = last.cumulativeMeters * min(1, max(0, progress))
        guard target > 0 else { return first.position }
        for index in 1..<points.count {
            let previous = points[index - 1], current = points[index]
            if current.cumulativeMeters >= target {
                guard !current.startsNewSegment else { return current.position }
                let distance = current.cumulativeMeters - previous.cumulativeMeters
                guard distance > 0 else { return current.position }
                let p = CGFloat((target - previous.cumulativeMeters) / distance)
                return CGPoint(x: previous.position.x + (current.position.x - previous.position.x) * p,
                               y: previous.position.y + (current.position.y - previous.position.y) * p)
            }
        }
        return last.position
    }

    /// The exact path used by the raster renderer. A partial endpoint is interpolated only
    /// within its current continuous edge, never by searching another segment's head.
    static func visibleRoutePath(_ points: [RunShareProjectedPoint], distanceMeters: Double) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        let target = distanceMeters.isFinite ? min(last.cumulativeMeters, max(0, distanceMeters)) : 0
        path.move(to: first.position)
        guard target > first.cumulativeMeters else { return path }
        for index in 1..<points.count {
            let previous = points[index - 1], current = points[index]
            if current.startsNewSegment {
                // Equal distance belongs to the end of the preceding visible stretch. Do not
                // enter the next stretch until the replay has genuinely progressed into it.
                guard current.cumulativeMeters < target else { break }
                path.move(to: current.position)
                continue
            }
            let edgeMeters = current.cumulativeMeters - previous.cumulativeMeters
            guard edgeMeters > 0 else {
                // Duplicate fixes have no drawable length. If their projected positions differ,
                // be conservative and break instead of inventing a zero-distance connector.
                path.move(to: current.position)
                continue
            }
            if current.cumulativeMeters <= target {
                path.addLine(to: current.position)
                if current.cumulativeMeters == target { break }
            } else {
                if previous.cumulativeMeters < target {
                    let fraction = CGFloat((target - previous.cumulativeMeters) / edgeMeters)
                    path.addLine(to: CGPoint(
                        x: previous.position.x + (current.position.x - previous.position.x) * fraction,
                        y: previous.position.y + (current.position.y - previous.position.y) * fraction
                    ))
                }
                break
            }
        }
        return path
    }

    private static func drawRoute(_ points: [RunShareProjectedPoint], progress: Double, context: CGContext, width: CGFloat) {
        guard let last = points.last else { return }
        let target = last.cumulativeMeters * min(1, max(0, progress))
        let path = visibleRoutePath(points, distanceMeters: target)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.addPath(path); context.setStrokeColor(ink.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(width + 6); context.strokePath()
        context.addPath(path); context.setStrokeColor(lime.cgColor)
        context.setLineWidth(width); context.strokePath()
        if let head = routeHead(points, progress: progress) {
            context.setFillColor(white.cgColor); context.setStrokeColor(lime.cgColor); context.setLineWidth(4)
            context.fillEllipse(in: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18))
            context.strokeEllipse(in: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18))
        }
    }

    private static func drawGradient(_ context: CGContext, rect: CGRect, colors: [UIColor]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1]) else { return }
        context.saveGState(); context.clip(to: rect)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        context.restoreGState()
    }

    private static func textSize(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGSize {
        (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)])
    }

    private static func drawText(_ text: String, at point: CGPoint, size: CGFloat, weight: UIFont.Weight, color: UIColor? = nil) {
        (text as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color ?? white])
    }

    private static func drawFittedText(_ text: String, in rect: CGRect, size: CGFloat, weight: UIFont.Weight,
                                       color: UIColor? = nil, alignment: NSTextAlignment = .left) {
        var fittedSize = size
        while fittedSize > 16, textSize(text, size: fittedSize, weight: weight).width > rect.width { fittedSize -= 1 }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: fittedSize, weight: weight), .foregroundColor: color ?? white, .paragraphStyle: paragraph])
    }
}
