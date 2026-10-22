import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Release A review fixes: segment-aware map lines and the zero-distance effort label.
@MainActor
final class RunReviewFixesTests: XCTestCase {
    private func point(_ latitude: Double, second: Double, startsNewSegment: Bool? = nil) -> RunRoutePoint {
        RunRoutePoint(
            latitude: latitude,
            longitude: 34.78,
            timestamp: Date(timeIntervalSince1970: 1_000 + second),
            horizontalAccuracy: 8,
            altitude: nil,
            startsNewSegment: startsNewSegment
        )
    }

    private func run(distanceMeters: Double, movingSeconds: TimeInterval, heartRate: Int? = nil) -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_000)
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(movingSeconds),
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingSeconds,
            averagePaceSecondsPerKm: distanceMeters > 0 ? movingSeconds / (distanceMeters / 1_000) : 0,
            averageHeartRateBPM: heartRate,
            routePoints: [],
            syncedAt: nil
        )
    }

    // MARK: Map segments

    func testLineSegmentsSplitAtEverySegmentStart() {
        let points = [
            point(32.000, second: 0), point(32.001, second: 10),
            point(32.050, second: 300, startsNewSegment: true), point(32.051, second: 310),
            point(32.100, second: 600, startsNewSegment: true), point(32.101, second: 610)
        ]

        let segments = RouteMapView.lineSegments(for: points)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.count), [2, 2, 2])
        XCTAssertEqual(segments[1].first?.latitude, 32.050)
    }

    func testLineSegmentsWithoutFlagsStayOneLineAndSinglePointsAreDropped() {
        XCTAssertEqual(RouteMapView.lineSegments(for: [point(32.0, second: 0), point(32.001, second: 5)]).count, 1)
        XCTAssertTrue(RouteMapView.lineSegments(for: [point(32.0, second: 0)]).isEmpty)
        XCTAssertTrue(RouteMapView.lineSegments(for: []).isEmpty)

        let lonePoint = [point(32.0, second: 0), point(32.001, second: 5), point(32.2, second: 600, startsNewSegment: true)]
        XCTAssertEqual(RouteMapView.lineSegments(for: lonePoint).count, 1, "a lone point after a pause has nothing to connect to yet")
    }

    func testThinningKeepsSegmentStartsSoThePauseGapStaysBroken() {
        var points = (0..<500).map { point(32.0 + Double($0) * 0.0001, second: Double($0)) }
        points[251].startsNewSegment = true

        let display = RunRecorder.simplifiedDisplayRoute(from: points, maxPoints: 50)

        XCTAssertLessThan(display.count, 500)
        XCTAssertTrue(display.contains { $0.id == points[251].id })
        XCTAssertEqual(RouteMapView.lineSegments(for: display).count, 2)
    }

    // MARK: Effort label

    func testZeroDistanceRunIsNeverLabelledModerate() {
        XCTAssertEqual(SupabaseRunSmartServices.fallbackEffort(for: run(distanceMeters: 0, movingSeconds: 90)), "easy")
        XCTAssertEqual(SupabaseRunSmartServices.fallbackEffort(for: run(distanceMeters: 0, movingSeconds: 80 * 60)), "easy")
    }

    func testRealPacesKeepTheirEffortLabels() {
        XCTAssertEqual(SupabaseRunSmartServices.fallbackEffort(for: run(distanceMeters: 5_000, movingSeconds: 1_350)), "moderate")
        XCTAssertEqual(SupabaseRunSmartServices.fallbackEffort(for: run(distanceMeters: 5_000, movingSeconds: 2_400)), "easy")
        XCTAssertEqual(SupabaseRunSmartServices.fallbackEffort(for: run(distanceMeters: 5_000, movingSeconds: 1_800)), "steady")
    }

    // MARK: Elevation across pauses

    func testElevationChangedDuringAPauseIsNotCountedAsGain() throws {
        func altitudePoint(_ altitude: Double, second: Double, startsNewSegment: Bool? = nil) -> RunRoutePoint {
            RunRoutePoint(
                latitude: 32.0,
                longitude: 34.78,
                timestamp: Date(timeIntervalSince1970: 1_000 + second),
                horizontalAccuracy: 8,
                altitude: altitude,
                startsNewSegment: startsNewSegment
            )
        }
        let points = [
            altitudePoint(0, second: 0), altitudePoint(10, second: 10), altitudePoint(20, second: 20),
            altitudePoint(80, second: 900, startsNewSegment: true),  // elevator or drive while paused
            altitudePoint(80, second: 910), altitudePoint(80, second: 920)
        ]

        let gain = try XCTUnwrap(RunRecorder.elevationGainMeters(from: points))

        XCTAssertEqual(gain, 20, accuracy: 0.001)
    }

    func testElevationStillNeedsTwoAltitudeReadings() {
        XCTAssertNil(RunRecorder.elevationGainMeters(from: []))
    }
}
