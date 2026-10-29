import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Record-a-run S12: the opt-in route map on a shared run cuts the first and last 200 m.
final class RouteSharePrivacyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// One degree of latitude is about 110,850 m at 32 degrees north.
    private let degreesPerMeter = 1.0 / 110_850.0

    /// A straight north-going route with a point every `spacingMeters`.
    private func line(totalMeters: Double, spacingMeters: Double = 10, newSegmentAt: Set<Int> = []) -> [RunRoutePoint] {
        let count = Int(totalMeters / spacingMeters) + 1
        return (0..<count).map { index in
            RunRoutePoint(
                latitude: 32.0 + Double(index) * spacingMeters * degreesPerMeter,
                longitude: 34.78,
                timestamp: start.addingTimeInterval(Double(index) * 3),
                horizontalAccuracy: 5,
                altitude: nil,
                startsNewSegment: newSegmentAt.contains(index) ? true : nil
            )
        }
    }

    private func meters(from a: RunRoutePoint, to b: RunRoutePoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    func testRouteUnderFourHundredMetersOffersNoMap() {
        XCTAssertNil(RouteSharePrivacy.shareableRoute(line(totalMeters: 300)))
        XCTAssertNil(RouteSharePrivacy.shareableRoute(line(totalMeters: 399)))
    }

    func testRouteOfExactlyFourHundredMetersLeavesNothingToShow() {
        XCTAssertNil(RouteSharePrivacy.shareableRoute(line(totalMeters: 400)))
    }

    func testEmptyAndSinglePointRoutesOfferNoMap() {
        XCTAssertNil(RouteSharePrivacy.shareableRoute([]))
        XCTAssertNil(RouteSharePrivacy.shareableRoute(Array(line(totalMeters: 1_000).prefix(1))))
    }

    func testLongRouteLosesTwoHundredMetersAtEachEnd() throws {
        let route = line(totalMeters: 1_000)
        let kept = try XCTUnwrap(RouteSharePrivacy.shareableRoute(route))
        let first = try XCTUnwrap(kept.first)
        let last = try XCTUnwrap(kept.last)
        XCTAssertGreaterThanOrEqual(meters(from: route[0], to: first), 199)
        XCTAssertGreaterThanOrEqual(meters(from: last, to: route[route.count - 1]), 199)
        XCTAssertEqual(kept.count, 60, accuracy: 3)
        XCTAssertEqual(RouteSharePrivacy.pathLengthMeters(kept), 600, accuracy: 15)
    }

    func testTrimNeverKeepsAPointInsideTheHiddenEnds() throws {
        let route = line(totalMeters: 700)
        let kept = try XCTUnwrap(RouteSharePrivacy.shareableRoute(route))
        for point in kept {
            XCTAssertGreaterThanOrEqual(meters(from: route[0], to: point), 199)
            XCTAssertGreaterThanOrEqual(meters(from: point, to: route[route.count - 1]), 199)
        }
    }

    func testPauseJumpIsNotCountedAsRouteLength() {
        // Two 250 m stretches with a ~5 km jump between them: the path is 500 m, not 5.5 km.
        var first = line(totalMeters: 250)
        var second = line(totalMeters: 250).map { point -> RunRoutePoint in
            var moved = point
            moved.latitude += 0.05
            return moved
        }
        second[0].startsNewSegment = true
        first.append(contentsOf: second)
        XCTAssertEqual(RouteSharePrivacy.pathLengthMeters(first), 500, accuracy: 20)
        // 500 m of route is above 400 m + 50 m, so a short remainder can be shown.
        XCTAssertNotNil(RouteSharePrivacy.shareableRoute(first))
    }

    func testTwoShortStretchesAcrossAJumpAreNotMistakenForALongRoute() {
        var points = line(totalMeters: 150)
        var second = line(totalMeters: 150).map { point -> RunRoutePoint in
            var moved = point
            moved.latitude += 0.05
            return moved
        }
        second[0].startsNewSegment = true
        points.append(contentsOf: second)
        XCTAssertNil(RouteSharePrivacy.shareableRoute(points))
    }

    func testSegmentSplitBreaksAtSegmentStarts() {
        let route = line(totalMeters: 90, newSegmentAt: [4, 7])
        let segments = RoutePointSegments.split(route)
        XCTAssertEqual(segments.map(\.count), [4, 3, 3])
        XCTAssertEqual(segments[1].first?.startsNewSegment, true)
    }

    func testDrawableSegmentsDropSinglePointStretches() {
        let route = line(totalMeters: 60, newSegmentAt: [3, 4])
        // Stretches: 0...2 (3 points), 3 (1 point), 4...6 (3 points)
        XCTAssertEqual(RoutePointSegments.split(route).map(\.count), [3, 1, 3])
        XCTAssertEqual(RoutePointSegments.drawableSegments(route).map(\.count), [3, 3])
    }

    func testSegmentSplitOfEmptyRouteIsEmpty() {
        XCTAssertTrue(RoutePointSegments.split([]).isEmpty)
    }

    func testPrivacyNoteChangesOnlyWhenTheMapIsIncluded() {
        let payload = ProgressSharePayload(
            kind: .runReport, title: "Morning Run", subtitle: "Today", metrics: [], insight: "Nice.",
            privacyNote: "Private share: no map, GPS points, or exact route are included."
        )
        XCTAssertEqual(payload.privacyNote, "Private share: no map, GPS points, or exact route are included.")
        let withMap = payload.includingRouteMap()
        XCTAssertEqual(withMap.privacyNote, "The first and last 200 m are kept private.")
        XCTAssertEqual(withMap.title, payload.title)
        XCTAssertTrue(withMap.shareText.contains("The first and last 200 m are kept private."))
    }

    func testSnapshotRegionCoversEveryPoint() throws {
        let route = line(totalMeters: 2_000)
        let region = try XCTUnwrap(RouteSnapshotRenderer.region(for: route))
        let lats = route.map(\.latitude)
        XCTAssertLessThanOrEqual(region.center.latitude - region.span.latitudeDelta / 2, lats.min()!)
        XCTAssertGreaterThanOrEqual(region.center.latitude + region.span.latitudeDelta / 2, lats.max()!)
        XCTAssertNil(RouteSnapshotRenderer.region(for: []))
    }
}
