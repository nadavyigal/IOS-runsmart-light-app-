import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class BenchmarkComparisonLoadingTests: XCTestCase {
    func testMissingOriginalRunShowsExplanationInsteadOfDisappearing() async {
        let state = await BenchmarkComparisonLoading.load(
            run: nil,
            matchRoute: { _ in XCTFail("Missing runs cannot be matched"); return nil },
            comparison: { _ in XCTFail("Missing runs cannot be compared"); return nil }
        )
        XCTAssertEqual(state, .status(.runUnavailable))
    }

    func testRunWithoutGPSShowsNoRouteDataWithoutMatching() async {
        let state = await BenchmarkComparisonLoading.load(
            run: makeRun(pointCount: 0),
            matchRoute: { _ in XCTFail("Missing GPS cannot be matched"); return nil },
            comparison: { _ in XCTFail("Missing GPS cannot be compared"); return nil }
        )
        XCTAssertEqual(state, .status(.noRouteData))
    }

    func testSparseGPSShowsLowConfidenceWithoutMatching() async {
        let state = await BenchmarkComparisonLoading.load(
            run: makeRun(pointCount: RouteMatchingService.minimumRoutePoints - 1),
            matchRoute: { _ in XCTFail("Sparse GPS cannot be matched"); return nil },
            comparison: { _ in XCTFail("Sparse GPS cannot be compared"); return nil }
        )
        XCTAssertEqual(state, .status(.weakGPS))
    }

    func testStaleNoMatchIsReplacedBeforeComparison() async {
        var run = makeRun()
        run.routeMatchResult = noMatch()
        let freshMatch = RouteMatchingService.exactMatch(routeID: UUID())
        var comparisonCalled = false
        _ = await BenchmarkComparisonLoading.load(
            run: run,
            matchRoute: { _ in freshMatch },
            comparison: { current in
                comparisonCalled = true
                XCTAssertEqual(current.routeMatchResult, freshMatch)
                return nil
            }
        )
        XCTAssertTrue(comparisonCalled, "An old no-match must not suppress comparison after a route is saved")
    }

    func testReloadAfterRouteChangeRescoresTheSameRun() async {
        let run = makeRun()
        var savedRouteID: UUID?
        var matches = 0
        var comparisons = 0
        let match: (RecordedRun) async -> RouteMatchResult? = { _ in
            matches += 1
            return savedRouteID.map(RouteMatchingService.exactMatch(routeID:))
        }
        let compare: (RecordedRun) async -> BenchmarkRouteComparison? = { current in
            comparisons += 1
            XCTAssertEqual(current.routeMatchResult?.routeID, savedRouteID)
            return nil
        }
        let initial = await BenchmarkComparisonLoading.load(run: run, matchRoute: match, comparison: compare)
        XCTAssertEqual(initial, .status(.noBenchmark))
        XCTAssertEqual(comparisons, 0)

        savedRouteID = UUID()
        _ = await BenchmarkComparisonLoading.load(run: run, matchRoute: match, comparison: compare)
        XCTAssertEqual(matches, 2)
        XCTAssertEqual(comparisons, 1)
    }

    func testDeletedRouteDoesNotKeepAnOldMatch() async {
        var run = makeRun()
        run.routeMatchResult = RouteMatchingService.exactMatch(routeID: UUID())
        let state = await BenchmarkComparisonLoading.load(
            run: run,
            matchRoute: { _ in nil },
            comparison: { _ in XCTFail("A deleted route must not be compared"); return nil }
        )
        XCTAssertEqual(state, .status(.noBenchmark))
    }

    private func makeRun(pointCount: Int = 10) -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return RecordedRun(
            id: UUID(), providerActivityID: nil, source: .runSmart,
            startedAt: start, endedAt: start.addingTimeInterval(1_800),
            distanceMeters: 5_000, movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360, averageHeartRateBPM: nil,
            routePoints: (0..<pointCount).map { index in
                RunRoutePoint(latitude: 32 + Double(index) * 0.0001,
                              longitude: 34.8, timestamp: start.addingTimeInterval(Double(index)),
                              horizontalAccuracy: 8, altitude: nil)
            }, syncedAt: nil
        )
    }

    private func noMatch() -> RouteMatchResult {
        RouteMatchResult(routeID: nil, candidateRouteID: UUID(), confidence: .noMatch,
                         distanceDeltaMeters: 500, startDeltaMeters: 500, endDeltaMeters: 500,
                         shapeSimilarity: 0, isReversed: false)
    }
}
