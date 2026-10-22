import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class LiveRunPresentationTests: XCTestCase {
    func testMapTargetFollowsLatestFixAfterDisplayRouteCap() throws {
        let points = (0..<240).map { point(latitude: 32 + Double($0) * 0.0006, longitude: 34) }
        let before = try XCTUnwrap(LiveRunMapPresentation.target(for: points))
        let moved = Array(points.dropFirst()) + [point(latitude: 32.15, longitude: 34.01)]
        let after = try XCTUnwrap(LiveRunMapPresentation.target(for: moved))
        XCTAssertEqual(after.latitude, 32.15)
        XCTAssertEqual(after.longitude, 34.01)
        XCTAssertNotEqual(before, after)
    }

    func testMapFollowsEastwardTravelHeading() throws {
        let target = try XCTUnwrap(LiveRunMapPresentation.target(for: [
            point(latitude: 32, longitude: 34),
            point(latitude: 32, longitude: 34.001)
        ]))
        XCTAssertEqual(target.heading, 90, accuracy: 0.01)
    }

    func testMapDoesNotConnectPauseWalkingGap() {
        let first = point(latitude: 32, longitude: 34)
        let second = point(latitude: 32.001, longitude: 34)
        var resumed = point(latitude: 32.004, longitude: 34)
        resumed.startsNewSegment = true
        let fourth = point(latitude: 32.005, longitude: 34)
        let segments = LiveRunMapPresentation.segments(in: [first, second, resumed, fourth])
        XCTAssertEqual(segments, [[first, second], [resumed, fourth]])
    }

    func testDisplaySimplificationPreservesSkippedPauseBoundaries() throws {
        var raw = (0..<1_000).map { point(latitude: 32 + Double($0) * 0.0001, longitude: 34) }
        // Indices 2 and 998 fall between retained samples at the 240-point cap.
        raw[2].startsNewSegment = true
        raw[998].startsNewSegment = true
        let display = RunRecorder.simplifiedDisplayRoute(from: raw)
        let segments = LiveRunMapPresentation.segments(in: display)
        XCTAssertEqual(display.count, 240)
        XCTAssertEqual(display.first?.id, raw.first?.id)
        XCTAssertEqual(display.last?.id, raw.last?.id)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.first?.last?.id, raw[0].id)
        XCTAssertEqual(segments.dropFirst().first?.first?.id, raw[4].id)
        XCTAssertEqual(segments.last?.first?.id, raw[999].id)
        XCTAssertNil(raw[4].startsNewSegment, "Display metadata must not mutate the raw GPS route")
    }

    func testNoMapTargetBeforeGPSAndNoHeadingAcrossPauseGap() throws {
        XCTAssertNil(LiveRunMapPresentation.target(for: []))
        var resumed = point(latitude: 32, longitude: 34.1)
        resumed.startsNewSegment = true
        let target = try XCTUnwrap(LiveRunMapPresentation.target(for: [
            point(latitude: 32, longitude: 34), resumed
        ]))
        XCTAssertEqual(target.heading, 0)
    }

    private func point(latitude: Double, longitude: Double) -> RunRoutePoint {
        RunRoutePoint(latitude: latitude, longitude: longitude, timestamp: Date(), horizontalAccuracy: 5)
    }
}
