import XCTest
@testable import IOS_RunSmart_app

/// Pins the benchmark loop for runs that exist before their route does.
///
/// Founder device test, 2026-10-18 and 2026-10-21: the same loop was run twice and a route
/// was saved from each run, but no comparison was possible. Matches were computed once, at
/// run-processing time, so the run a route was saved from never counted on its own route
/// and earlier runs never counted toward a later benchmark.
final class RouteRematchTests: XCTestCase {

    // RunSmartLocalStore is bound to UserDefaults.standard. Snapshot every key these tests
    // write and restore the exact prior values so neighbouring tests and the simulator's
    // app state are untouched.
    private let touchedKeys = [
        "runsmart.runs",
        "runsmart.savedRoutes",
        "runsmart.benchmarkRoutes",
        "runsmart.hiddenRuns",
    ]
    private var defaultsSnapshot: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaultsSnapshot = [:]
        for key in touchedKeys {
            if let value = defaults.object(forKey: key) {
                defaultsSnapshot[key] = value
            }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in touchedKeys {
            if let value = defaultsSnapshot[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaultsSnapshot = [:]
        super.tearDown()
    }

    // MARK: - Run saved before its route existed

    func testRunSavedBeforeItsRouteExistedMatchesWhenRouteIsSaved() async {
        let services = ProductionRunSmartServices()
        let earlierRun = Self.makeRun(day: 1, distanceMeters: 5_000, points: Self.loopPoints(offset: 0.00002))
        let processed = await services.saveRouteMatch(for: earlierRun)
        XCTAssertNil(processed.routeMatchResult, "With no saved routes, processing stores no match")

        let route = Self.makeRoute(distanceMeters: 5_050, points: Self.loopPoints())
        let saved = await services.saveRoute(route)
        XCTAssertTrue(saved)

        let stored = await Self.storedRun(earlierRun.id)
        XCTAssertEqual(stored?.routeMatchResult?.confidence, .matched)
        XCTAssertEqual(stored?.routeMatchResult?.routeID, route.id)
    }

    // MARK: - Route saved from a run

    func testRouteSavedFromRunStoresThatRunAsAnExactMatch() async {
        let services = ProductionRunSmartServices()
        let run = Self.makeRun(day: 1, distanceMeters: 5_030, points: Self.loopPoints())
        _ = await services.saveRouteMatch(for: run)

        let route = SavedRoute.from(run: run, name: "5.0 km run")
        let saved = await services.saveRoute(route, fromRun: run)
        XCTAssertTrue(saved)

        let stored = await Self.storedRun(run.id)
        XCTAssertEqual(stored?.routeMatchResult, RouteMatchingService.exactMatch(routeID: route.id))
    }

    func testRouteSavedFromRunKeepsNewerStoredFieldsOfThatRun() async {
        let services = ProductionRunSmartServices()
        let staleCopy = Self.makeRun(day: 1, distanceMeters: 5_030, points: Self.loopPoints())
        var newer = staleCopy
        newer.rpe = 7
        await RunSmartLocalStore.shared.saveRun(newer)

        let route = SavedRoute.from(run: staleCopy, name: "5.0 km run")
        _ = await services.saveRoute(route, fromRun: staleCopy)

        let stored = await Self.storedRun(staleCopy.id)
        XCTAssertEqual(stored?.rpe, 7, "Attaching the route must update the stored run, not overwrite it with the sheet's copy")
        XCTAssertEqual(stored?.routeMatchResult?.routeID, route.id)
    }

    func testRouteSavedFromRunCountsOnItsOwnBenchmark() async {
        let services = ProductionRunSmartServices()
        let run = Self.makeRun(day: 1, distanceMeters: 5_030, points: Self.loopPoints())
        _ = await services.saveRouteMatch(for: run)

        let route = SavedRoute.from(run: run, name: "5.0 km run")
        _ = await services.saveRoute(route, fromRun: run)
        _ = await services.enableBenchmark(for: route.id)

        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == route.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 1)

        guard let stored = await Self.storedRun(run.id) else { return XCTFail("Run missing from store") }
        let comparison = await services.benchmarkComparison(for: stored)
        XCTAssertEqual(comparison?.routeID, route.id)
        XCTAssertEqual(comparison?.currentPerformance.runID, run.id)
    }

    // MARK: - Benchmark enabled after both runs

    func testBenchmarkEnabledAfterBothRunsComparesThem() async {
        let services = ProductionRunSmartServices()
        let first = Self.makeRun(day: 1, distanceMeters: 5_000, movingTime: 1_560, points: Self.loopPoints())
        let second = Self.makeRun(day: 4, distanceMeters: 5_200, movingTime: 1_590, points: Self.loopPoints(offset: 0.00002))
        _ = await services.saveRouteMatch(for: first)
        _ = await services.saveRouteMatch(for: second)

        // A route already in the library that never triggered a re-match: synced from
        // another device, or saved by a build without this fix.
        let route = SavedRoute.from(run: first, name: "Park loop")
        await RunSmartLocalStore.shared.saveSavedRoute(route)
        let secondBefore = await Self.storedRun(second.id)
        XCTAssertNil(secondBefore?.routeMatchResult)

        let enabled = await services.enableBenchmark(for: route.id)
        XCTAssertTrue(enabled)

        let firstStored = await Self.storedRun(first.id)
        let secondStored = await Self.storedRun(second.id)
        XCTAssertEqual(firstStored?.routeMatchResult?.routeID, route.id)
        XCTAssertEqual(secondStored?.routeMatchResult?.confidence, .matched)
        XCTAssertEqual(secondStored?.routeMatchResult?.routeID, route.id)

        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == route.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 2)

        guard let secondStored else { return XCTFail("Run missing from store") }
        let comparison = await services.benchmarkComparison(for: secondStored)
        XCTAssertEqual(comparison?.previousPerformance?.runID, first.id)
        XCTAssertEqual(comparison?.personalBest.runID, first.id)
    }

    /// The founder's numbers: 5.03 km on Oct 18, 5.52 km on Oct 21 (9.8% longer). With the 8%
    /// distance gate unchanged the longer run stays a possible match, so it is not compared.
    func testLoopRunMoreThanEightPercentLongerStaysPossibleMatchWithGateUnchanged() async {
        let services = ProductionRunSmartServices()
        let oct18 = Self.makeRun(day: 1, distanceMeters: 5_030, points: Self.loopPoints())
        let oct21 = Self.makeRun(day: 4, distanceMeters: 5_522, points: Self.loopPoints())
        _ = await services.saveRouteMatch(for: oct18)
        _ = await services.saveRouteMatch(for: oct21)

        let route = SavedRoute.from(run: oct18, name: "5.0 km run")
        _ = await services.saveRoute(route, fromRun: oct18)
        _ = await services.enableBenchmark(for: route.id)

        let oct21Stored = await Self.storedRun(oct21.id)
        XCTAssertEqual(oct21Stored?.routeMatchResult?.confidence, .possibleMatch)
        XCTAssertNil(oct21Stored?.routeMatchResult?.routeID)
        XCTAssertEqual(oct21Stored?.routeMatchResult?.candidateRouteID, route.id)

        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == route.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 1)
    }

    /// "Save + benchmark" re-matches twice in a row and the second pass is skipped when
    /// nothing changed. A run stored in between must still be scored.
    func testBenchmarkAfterSaveStillMatchesRunStoredInBetween() async {
        let services = ProductionRunSmartServices()
        let first = Self.makeRun(day: 1, distanceMeters: 5_000, points: Self.loopPoints())
        _ = await services.saveRouteMatch(for: first)
        let route = SavedRoute.from(run: first, name: "Park loop")
        _ = await services.saveRoute(route, fromRun: first)

        let unprocessed = Self.makeRun(day: 2, distanceMeters: 5_100, points: Self.loopPoints(offset: 0.00002))
        await RunSmartLocalStore.shared.saveRun(unprocessed)
        _ = await services.enableBenchmark(for: route.id)

        let stored = await Self.storedRun(unprocessed.id)
        XCTAssertEqual(stored?.routeMatchResult?.routeID, route.id)
        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == route.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 2)
    }

    // MARK: - Re-match policy

    func testRematchKeepsExistingMatchWhenNewResultIsWeaker() {
        let keptRouteID = UUID()
        let existing = RouteMatchingService.exactMatch(routeID: keptRouteID)
        let weaker = RouteMatchResult(
            routeID: nil,
            candidateRouteID: UUID(),
            confidence: .possibleMatch,
            distanceDeltaMeters: 300,
            startDeltaMeters: 40,
            endDeltaMeters: 40,
            shapeSimilarity: 0.6,
            isReversed: false
        )

        let preferred = RouteRematchService.preferredResult(
            existing: existing,
            candidate: weaker,
            savedRouteIDs: [keptRouteID]
        )
        XCTAssertEqual(preferred, existing)
    }

    func testRematchReplacesMatchWhoseRouteWasDeleted() {
        let existing = RouteMatchingService.exactMatch(routeID: UUID())
        let candidate = RouteMatchResult(
            routeID: nil,
            candidateRouteID: UUID(),
            confidence: .noMatch,
            distanceDeltaMeters: 2_000,
            startDeltaMeters: 900,
            endDeltaMeters: 900,
            shapeSimilarity: 0.1,
            isReversed: false
        )

        let preferred = RouteRematchService.preferredResult(
            existing: existing,
            candidate: candidate,
            savedRouteIDs: []
        )
        XCTAssertEqual(preferred, candidate)
    }

    func testRematchIsBoundedToNewestRunsAndSkipsRunsWithoutRoutePoints() {
        let route = Self.makeRoute(distanceMeters: 5_000, points: Self.loopPoints())
        let older = Self.makeRun(day: 1, distanceMeters: 5_000, points: Self.loopPoints())
        let newer = Self.makeRun(day: 2, distanceMeters: 5_000, points: Self.loopPoints())
        let manual = Self.makeRun(day: 3, distanceMeters: 5_000, points: [])

        let updates = RouteRematchService.updatedMatches(
            runs: [older, manual, newer],
            savedRoutes: [route],
            limit: 1
        )

        XCTAssertEqual(Set(updates.keys), [newer.id])
        XCTAssertEqual(updates[newer.id]?.routeID, route.id)
    }

    func testRematchReturnsNothingWhenStoredResultIsUnchanged() {
        let route = Self.makeRoute(distanceMeters: 5_000, points: Self.loopPoints())
        var run = Self.makeRun(day: 1, distanceMeters: 5_000, points: Self.loopPoints())
        run.routeMatchResult = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertTrue(RouteRematchService.updatedMatches(runs: [run], savedRoutes: [route]).isEmpty)
    }

    // MARK: - Fixtures

    @MainActor
    private static func storedRun(_ id: UUID) -> RecordedRun? {
        RunSmartLocalStore.shared.loadRuns().first { $0.id == id }
    }

    private static func makeRun(
        day: Int,
        distanceMeters: Double,
        movingTime: TimeInterval = 1_560,
        points: [RunRoutePoint]
    ) -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400)
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(movingTime),
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingTime,
            averagePaceSecondsPerKm: movingTime / (distanceMeters / 1_000),
            averageHeartRateBPM: 150,
            routePoints: points,
            syncedAt: nil
        )
    }

    private static func makeRoute(distanceMeters: Double, points: [RunRoutePoint]) -> SavedRoute {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return SavedRoute(
            id: UUID(),
            name: "Loop",
            distanceMeters: distanceMeters,
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

    /// 16 points on a line far from any preview fixture; `offset` shifts every point
    /// north (0.00002 degrees is about 2 m of GPS noise).
    private static func loopPoints(offset: Double = 0) -> [RunRoutePoint] {
        let start = Date(timeIntervalSince1970: 1_000)
        return (0..<16).map { index in
            RunRoutePoint(
                latitude: -20.0 + offset + Double(index) * 0.00045,
                longitude: -20.0 + Double(index) * 0.00035,
                timestamp: start.addingTimeInterval(Double(index) * 20),
                horizontalAccuracy: 8,
                altitude: nil
            )
        }
    }
}
