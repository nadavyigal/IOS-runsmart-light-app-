import XCTest
import CoreLocation
import MapKit
@testable import IOS_RunSmart_app

/// Feed and Story posters. Set TEST_RUNNER_RUN_SHARE_RENDER_DIR to write review PNGs
/// (map renders need network, so they run only when that folder is set).
@MainActor
final class RunSharePosterRenderTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_793_001_600) // 26 Oct 2026, 06:00 UTC
    private let insight = "Even pace from the first kilometre to the last. That is aerobic base."
    private let longInsight = "Even pace from the first kilometre to the last, a relaxed effort that builds aerobic base, and a strong finish along the beach that shows your easy pace is getting faster every week."

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return calendar
    }

    private var renderFolder: URL? {
        ProcessInfo.processInfo.environment["RUN_SHARE_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// A 6.6 km loop through central Tel Aviv: Habima, Dizengoff, the port, the beach promenade, Allenby.
    private func telAvivLoop() -> [RunRoutePoint] {
        let vertices: [(Double, Double)] = [
            (32.0726, 34.7790), (32.0779, 34.7746), (32.0858, 34.7741), (32.0931, 34.7748),
            (32.0978, 34.7727), (32.0967, 34.7697), (32.0890, 34.7686), (32.0815, 34.7666),
            (32.0745, 34.7638), (32.0690, 34.7637), (32.0668, 34.7695), (32.0690, 34.7752),
            (32.0726, 34.7790)
        ]
        var coordinates: [(Double, Double)] = []
        for index in 1..<vertices.count {
            let a = vertices[index - 1], b = vertices[index]
            for step in 0..<24 {
                let t = Double(step) / 24
                coordinates.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
            }
        }
        coordinates.append(vertices.last!)
        return coordinates.enumerated().map { index, coordinate in
            RunRoutePoint(latitude: coordinate.0, longitude: coordinate.1,
                          timestamp: startedAt.addingTimeInterval(Double(index) * 2_178 / Double(coordinates.count - 1)),
                          horizontalAccuracy: 5, altitude: nil)
        }
    }

    private func snapshot(points: [RunRoutePoint], insight: String, distance: Double = 6_600) -> RunShareSnapshot {
        let run = RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart, startedAt: startedAt,
                              endedAt: startedAt.addingTimeInterval(2_300), distanceMeters: distance,
                              movingTimeSeconds: 2_178, averagePaceSecondsPerKm: 330, averageHeartRateBPM: nil,
                              routePoints: points, syncedAt: nil, title: "Morning run")
        return RunShareSnapshot.make(run: run, includeMap: true, insight: insight,
                                     locale: Locale(identifier: "en_US_POSIX"), calendar: calendar)
    }

    private func write(_ image: UIImage, _ name: String) throws {
        guard let folder = renderFolder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
    }

    func testRouteFillsItsBoxOnEachPoster() {
        let bounds = MKMapRect(x: 1_000, y: 2_000, width: 400, height: 1_000)
        for format in [RunShareAssetFormat.feed, .story] {
            let canvas = format.pixelSize
            let box = RunSharePosterRenderer.routeBox(for: format)
            let rect = RunSharePosterRenderer.posterMapRect(routeBounds: bounds, canvas: canvas, target: box, minimumSpan: 0)
            XCTAssertEqual(rect.width / rect.height, Double(canvas.width / canvas.height), accuracy: 0.0001)
            // Project the route bounds onto the canvas: inside the box, centered, touching it on one axis.
            let scale = Double(canvas.width) / rect.width
            let projected = CGRect(x: (bounds.minX - rect.minX) * scale, y: (bounds.minY - rect.minY) * scale,
                                   width: bounds.width * scale, height: bounds.height * scale)
            XCTAssertTrue(box.insetBy(dx: -0.5, dy: -0.5).contains(projected))
            XCTAssertTrue(abs(projected.width - box.width) < 0.5 || abs(projected.height - box.height) < 0.5)
            XCTAssertEqual(projected.midX, box.midX, accuracy: 0.5)
            XCTAssertEqual(projected.midY, box.midY, accuracy: 0.5)
        }
    }

    func testTinyRouteIsNotZoomedPastTheMinimumSpan() {
        let canvas = RunShareAssetFormat.story.pixelSize
        let box = RunSharePosterRenderer.routeBox(for: .story)
        let rect = RunSharePosterRenderer.posterMapRect(routeBounds: MKMapRect(x: 0, y: 0, width: 10, height: 10),
                                                        canvas: canvas, target: box, minimumSpan: 5_000)
        let boxSpan = rect.width / Double(canvas.width) * Double(min(box.width, box.height))
        XCTAssertEqual(boxSpan, 5_000, accuracy: 0.01)
    }

    /// Lowest row (as a fraction of height) holding anything brighter than the ink background.
    private func lowestContentRow(_ image: UIImage) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for row in stride(from: height - 1, through: 0, by: -1) {
            for column in stride(from: 0, to: width, by: 4) where pixels[(row * width + column) * 4 + 1] > 60 {
                return Double(row + 1) / Double(height)
            }
        }
        return 0
    }

    func testStatsOnlyStoryHasNoEmptyBottomQuarter() throws {
        let image = RunSharePosterRenderer.image(snapshot: snapshot(points: [], insight: insight), format: .story,
                                                 map: nil, logo: RunSharePosterRenderer.logoImage())
        XCTAssertGreaterThan(try lowestContentRow(image), 0.72)
    }

    func testVideoLastFrameIsTheStoryImage() throws {
        let share = snapshot(points: [], insight: insight)
        let logo = RunSharePosterRenderer.logoImage()
        let story = RunSharePosterRenderer.image(snapshot: share, format: .story, map: nil, logo: logo)
        let lastFrame = RunSharePosterRenderer.image(snapshot: share, format: .video, map: nil, logo: logo,
                                                     time: RunShareMediaRenderer.videoDuration)
        XCTAssertEqual(try XCTUnwrap(lastFrame.pngData()), try XCTUnwrap(story.pngData()))
    }

    func testVideoDistanceCountsUpToTheExactLabel() {
        let share = snapshot(points: [], insight: "")
        XCTAssertEqual(RunSharePosterRenderer.countedDistance(share, progress: 0), "0.0")
        XCTAssertEqual(RunSharePosterRenderer.countedDistance(share, progress: 0.5), "3.3")
        XCTAssertEqual(RunSharePosterRenderer.countedDistance(share, progress: 1), share.distanceLabel)
        let run = RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart, startedAt: startedAt,
                              endedAt: startedAt, distanceMeters: 6_600, movingTimeSeconds: 2_178,
                              averagePaceSecondsPerKm: 330, averageHeartRateBPM: nil, routePoints: [], syncedAt: nil,
                              title: nil)
        let german = RunShareSnapshot.make(run: run, includeMap: false, locale: Locale(identifier: "de_DE"), calendar: calendar)
        XCTAssertEqual(german.distanceLabel, "6,6")
        XCTAssertEqual(RunSharePosterRenderer.countedDistance(german, progress: 0.5), "3,3")
    }

    func testStatsOnlyPostersRenderAtExportSize() throws {
        for format in [RunShareAssetFormat.feed, .story] {
            for (suffix, text, distance) in [("", insight, 6_600.0), ("-no-insight", "", 6_600), ("-long", longInsight, 42_195)] {
                let image = RunSharePosterRenderer.image(snapshot: snapshot(points: [], insight: text, distance: distance),
                                                         format: format, map: nil, logo: RunSharePosterRenderer.logoImage())
                XCTAssertEqual(image.size, format.pixelSize)
                try write(image, "\(format.rawValue)-no-map\(suffix)")
            }
        }
    }

    func testMapPostersRenderAtExportSize() async throws {
        guard renderFolder != nil else { throw XCTSkip("Map renders need network; set TEST_RUNNER_RUN_SHARE_RENDER_DIR.") }
        for (suffix, text, distance) in [("", insight, 6_600.0), ("-no-insight", "", 6_600), ("-long", longInsight, 42_195)] {
            let share = snapshot(points: telAvivLoop(), insight: text, distance: distance)
            XCTAssertFalse(share.routePoints.isEmpty)
            for format in [RunShareAssetFormat.feed, .story] {
                let image = try await RunShareMediaRenderer.poster(snapshot: share, format: format)
                XCTAssertEqual(image.size, format.pixelSize)
                try write(image, "\(format.rawValue)-map\(suffix)")
            }
        }
        // Video frames for review: early replay, mid replay, pull-back, final.
        let share = snapshot(points: telAvivLoop(), insight: insight)
        let plate = try await RunSharePosterRenderer.prepareMap(snapshot: share, format: .video)
        XCTAssertNotNil(plate)
        for time in [1.5, 4.0, 7.3, 10.0] {
            let frame = RunSharePosterRenderer.image(snapshot: share, format: .video, map: plate,
                                                     logo: RunSharePosterRenderer.logoImage(), time: time)
            try write(frame, String(format: "Video-%04.1fs", time))
        }
        if let folder = renderFolder {
            let url = try await RunShareMediaRenderer.video(snapshot: share) { _ in }
            let copy = folder.appendingPathComponent("Video.mp4")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.moveItem(at: url, to: copy)
        }
    }
}
