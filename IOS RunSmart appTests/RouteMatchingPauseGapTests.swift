import XCTest
@testable import IOS_RunSmart_app

/// A pause or recovered-run resume starts a new route segment. The runner may have moved while
/// recording was off, so route length and coverage are measured from real segments only.
final class RouteMatchingPauseGapTests: XCTestCase {
    private let metersPerDegreeLatitude = 111_320.0

    /// A straight north-south line, one point every 50 m. `breaks` marks the first point of
    /// a new segment, by distance along the line.
    private func line(from startMeters: Double, to endMeters: Double, startsNewSegment: Bool = false) -> [RunRoutePoint] {
        stride(from: startMeters, through: endMeters, by: 50).enumerated().map { offset, meters in
            RunRoutePoint(
                latitude: -20 + meters / metersPerDegreeLatitude,
                longitude: -20,
                timestamp: Date(timeIntervalSince1970: 1_000 + meters),
                horizontalAccuracy: 6,
                altitude: nil,
                startsNewSegment: offset == 0 && startsNewSegment ? true : nil
            )
        }
    }

    private func makeRun(points: [RunRoutePoint], distanceMeters: Double = 3_000) -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_000),
            distanceMeters: distanceMeters,
            movingTimeSeconds: 1_000,
            averagePaceSecondsPerKm: 1_000 / (distanceMeters / 1_000),
            averageHeartRateBPM: nil,
            routePoints: points,
            syncedAt: nil
        )
    }

    private func makeRoute(points: [RunRoutePoint]) -> SavedRoute {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return SavedRoute(
            id: UUID(),
            name: "Line",
            distanceMeters: 3_000,
            elevationGainMeters: 0,
            points: points,
            source: .recorded,
            tags: [],
            notes: "",
            isFavorite: false,
            createdAt: now,
            updatedAt: now
        )
    }

    func testGapCrossedWhilePausedDoesNotCountAsCoveredRoute() throws {
        let route = makeRoute(points: line(from: 0, to: 3_000))
        // Recorded 0-1000 m and 2000-3000 m; the middle kilometer was covered while paused.
        let withBreak = makeRun(points: line(from: 0, to: 1_000) + line(from: 2_000, to: 3_000, startsNewSegment: true))
        // Same points without the segment flag: the old behavior bridged the gap.
        let withoutBreak = makeRun(points: line(from: 0, to: 1_000) + line(from: 2_000, to: 3_000))

        let broken = try XCTUnwrap(RouteMatchingService.match(run: withBreak, savedRoutes: [route])?.routeCoverage)
        let bridged = try XCTUnwrap(RouteMatchingService.match(run: withoutBreak, savedRoutes: [route])?.routeCoverage)

        XCTAssertEqual(bridged, 1.0, accuracy: 0.02, "control: an unflagged jump is treated as running that stretch")
        XCTAssertEqual(broken, 0.69, accuracy: 0.05, "only the two recorded kilometers (plus tolerance) are covered")
    }

    func testPauseWithoutMovingStillCoversTheWholeRoute() throws {
        let route = makeRoute(points: line(from: 0, to: 3_000))
        // Paused at 1500 m and resumed at the same spot.
        let run = makeRun(points: line(from: 0, to: 1_500) + line(from: 1_500, to: 3_000, startsNewSegment: true))

        let match = try XCTUnwrap(RouteMatchingService.match(run: run, savedRoutes: [route]))

        XCTAssertEqual(try XCTUnwrap(match.routeCoverage), 1.0, accuracy: 0.02)
        XCTAssertEqual(match.confidence, .matched)
    }

    func testSavedRouteWithAPauseGapDoesNotVouchForTheGap() throws {
        let continuous = makeRoute(points: line(from: 0, to: 3_000))
        let withGap = makeRoute(points: line(from: 0, to: 1_000) + line(from: 2_000, to: 3_000, startsNewSegment: true))
        let run = makeRun(points: line(from: 0, to: 3_000))

        XCTAssertEqual(RouteMatchingService.match(run: run, savedRoutes: [continuous])?.confidence, .matched)
        XCTAssertNotEqual(
            RouteMatchingService.match(run: run, savedRoutes: [withGap])?.confidence,
            .matched,
            "a route that was never recorded between 1 and 2 km cannot match a run that covered it"
        )
    }
}
