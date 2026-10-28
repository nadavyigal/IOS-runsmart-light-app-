import AVFoundation
import CoreLocation
import CoreImage
import MapKit
import XCTest
import UIKit
@testable import IOS_RunSmart_app

@MainActor
final class RunShareRendererTests: XCTestCase {
    private var privateSnapshot: RunShareSnapshot {
        RunShareSnapshot(
            title: "Morning Run", dateLabel: "23 Oct 2026", distanceLabel: "6.8", distanceUnit: "km",
            durationLabel: "40:39", paceLabel: "5:59 /km", sourceLabel: "RunSmart",
            insight: "One more run in the bank.", privacyNote: "No location data is included.",
            distanceMeters: 6_800, movingTimeSeconds: 2_439, routePoints: []
        )
    }

    func testOutAndBackHeadRevisitsTheSamePositionInChronologicalOrder() throws {
        let points = [
            RunShareProjectedPoint(position: CGPoint(x: 100, y: 900), startsNewSegment: true, cumulativeMeters: 0),
            RunShareProjectedPoint(position: CGPoint(x: 100, y: 100), startsNewSegment: false, cumulativeMeters: 3_400),
            RunShareProjectedPoint(position: CGPoint(x: 100, y: 900), startsNewSegment: false, cumulativeMeters: 6_800)
        ]
        XCTAssertEqual(try XCTUnwrap(RunSharePosterRenderer.routeHead(points, progress: 0)).y, 900, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RunSharePosterRenderer.routeHead(points, progress: 0.5)).y, 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RunSharePosterRenderer.routeHead(points, progress: 1)).y, 900, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RunSharePosterRenderer.routeHead(points, progress: 0.25)).y, 500, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RunSharePosterRenderer.routeHead(points, progress: 0.75)).y, 500, accuracy: 0.001)
    }

    func testHeadDoesNotInterpolateAcrossAPauseGap() throws {
        let points = [
            RunShareProjectedPoint(position: CGPoint(x: 0, y: 0), startsNewSegment: true, cumulativeMeters: 0),
            RunShareProjectedPoint(position: CGPoint(x: 10, y: 0), startsNewSegment: false, cumulativeMeters: 10),
            RunShareProjectedPoint(position: CGPoint(x: 500, y: 0), startsNewSegment: true, cumulativeMeters: 10),
            RunShareProjectedPoint(position: CGPoint(x: 600, y: 0), startsNewSegment: false, cumulativeMeters: 110)
        ]
        let head = try XCTUnwrap(RunSharePosterRenderer.routeHead(points, progress: 0.5))
        XCTAssertEqual(head.x, 545, accuracy: 0.001)
    }

    func testRenderedPathDoesNotBridgeAPauseGapAtTheExactBoundary() {
        let points = pauseGapPoints
        let boundary = RunSharePosterRenderer.visibleRoutePath(points, distanceMeters: 10)
        let edges = renderedEdges(boundary)
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges.first?.0.x, 0)
        XCTAssertEqual(edges.first?.1.x, 10)
        XCTAssertFalse(edges.contains { abs($0.1.x - $0.0.x) > 100 })
    }

    func testRenderedPathContinuesInsideTheNewSegmentJustAfterBoundary() {
        let path = RunSharePosterRenderer.visibleRoutePath(pauseGapPoints, distanceMeters: 10.01)
        let edges = renderedEdges(path)
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[1].0.x, 500, accuracy: 0.001)
        XCTAssertEqual(edges[1].1.x, 500.01, accuracy: 0.001)
        XCTAssertFalse(edges.contains { abs($0.1.x - $0.0.x) > 100 })
    }

    func testRenderedPathDoesNotConnectAnUnexplainedZeroLengthEdge() {
        let points = [
            RunShareProjectedPoint(position: CGPoint(x: 0, y: 0), startsNewSegment: true, cumulativeMeters: 0),
            RunShareProjectedPoint(position: CGPoint(x: 10, y: 0), startsNewSegment: false, cumulativeMeters: 10),
            RunShareProjectedPoint(position: CGPoint(x: 500, y: 0), startsNewSegment: false, cumulativeMeters: 10),
            RunShareProjectedPoint(position: CGPoint(x: 600, y: 0), startsNewSegment: false, cumulativeMeters: 110)
        ]
        for distance in [0.0, 10.0, 10.01, 110.0] {
            let edges = renderedEdges(RunSharePosterRenderer.visibleRoutePath(points, distanceMeters: distance))
            XCTAssertFalse(edges.contains { abs($0.1.x - $0.0.x) > 100 }, "Unexpected connector at \(distance)m")
        }
    }

    private var pauseGapPoints: [RunShareProjectedPoint] {
        [
            RunShareProjectedPoint(position: CGPoint(x: 0, y: 0), startsNewSegment: true, cumulativeMeters: 0),
            RunShareProjectedPoint(position: CGPoint(x: 10, y: 0), startsNewSegment: false, cumulativeMeters: 10),
            RunShareProjectedPoint(position: CGPoint(x: 500, y: 0), startsNewSegment: true, cumulativeMeters: 10),
            RunShareProjectedPoint(position: CGPoint(x: 600, y: 0), startsNewSegment: false, cumulativeMeters: 110)
        ]
    }

    private func renderedEdges(_ path: CGPath) -> [(CGPoint, CGPoint)] {
        var edges: [(CGPoint, CGPoint)] = []
        var current: CGPoint?
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
            case .addLineToPoint:
                let end = element.points[0]
                if let current { edges.append((current, end)) }
                current = end
            default:
                break
            }
        }
        return edges
    }

    func testFollowCameraNeverExposesBlankPlateEdgesAndEndsAtOverview() {
        let points = [
            RunShareProjectedPoint(position: CGPoint(x: 10, y: 10), startsNewSegment: true, cumulativeMeters: 0),
            RunShareProjectedPoint(position: CGPoint(x: 1_070, y: 1_220), startsNewSegment: false, cumulativeMeters: 1_000)
        ]
        let size = CGSize(width: 1_080, height: 1_230)
        for time in stride(from: 0.0, through: 10.0, by: 0.25) {
            let transform = RunSharePosterRenderer.cameraTransform(points: points, contentSize: size, time: time)
            let bounds = CGRect(origin: .zero, size: size).applying(transform)
            XCTAssertLessThanOrEqual(bounds.minX, 0.001)
            XCTAssertLessThanOrEqual(bounds.minY, 0.001)
            XCTAssertGreaterThanOrEqual(bounds.maxX, size.width - 0.001)
            XCTAssertGreaterThanOrEqual(bounds.maxY, size.height - 0.001)
        }
        XCTAssertEqual(RunSharePosterRenderer.cameraTransform(points: points, contentSize: size, time: 10), .identity)
    }

    func testMapExtentWrapsAtTheDateLineInsteadOfShowingTheWholeWorld() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [179.99, -179.99].map {
            RunRoutePoint(latitude: 32, longitude: $0, timestamp: time, horizontalAccuracy: 5, altitude: nil)
        }
        let rect = RunSharePosterRenderer.routeBounds(points)
        XCTAssertLessThan(rect.size.width, MKMapRect.world.size.width / 10)
        XCTAssertTrue(rect.size.width.isFinite)
    }

    func testPrivateImageExportsHaveExactPixelsWithoutRequiringMapTiles() async throws {
        for format in [RunShareAssetFormat.story, .feed] {
            let image = try await RunShareMediaRenderer.poster(snapshot: privateSnapshot, format: format)
            let cgImage = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cgImage.width, 1_080)
            XCTAssertEqual(cgImage.height, format == .feed ? 1_350 : 1_920)
            XCTAssertEqual(image.scale, 1)
        }
    }

    func testPrivateVideoIsPlayableTenSecondPortraitMP4WithoutAudio() async throws {
        var lastProgress = 0.0
        let url = try await RunShareMediaRenderer.video(snapshot: privateSnapshot) { lastProgress = $0 }
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertEqual(lastProgress, 1)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(size.width, 1_080)
        XCTAssertEqual(size.height, 1_920)
        XCTAssertEqual(CMTimeGetSeconds(duration), 10, accuracy: 0.1)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
    }

    func testAlreadyCancelledExportDoesNotStartRendering() async {
        let snapshot = privateSnapshot
        let task = Task { try await RunShareMediaRenderer.video(snapshot: snapshot) { _ in } }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled render unexpectedly produced a video")
        } catch is CancellationError {
            // Expected: neither map loading nor a writer starts after cancellation.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
