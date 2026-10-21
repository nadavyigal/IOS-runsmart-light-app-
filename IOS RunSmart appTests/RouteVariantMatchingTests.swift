import XCTest
@testable import IOS_RunSmart_app

/// Pins coverage-based matching and the route-variant state.
///
/// Founder device test, 2026-10-18 and 2026-10-21: the same loop, the second run with a short
/// detour (+9.8%). The index-sampled shape score (0.653) and the 8% distance limit both
/// rejected it, so the two runs could not be compared. Measured on the real traces at 35 m:
/// each run covers 96 to 97% of the other's route.
final class RouteVariantMatchingTests: XCTestCase {

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

    // MARK: - Matching

    func testLoopWithDetourIsRouteVariantOfThePlainLoop() {
        let route = Self.makeRoute(points: Self.plainLoop(), distanceMeters: 4_000)
        let run = Self.makeRun(day: 2, distanceMeters: 4_500, points: Self.detourLoop())

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertEqual(match?.confidence, .routeVariant)
        XCTAssertEqual(match?.routeID, route.id, "A route variant counts toward the route")
        XCTAssertGreaterThanOrEqual(match?.routeCoverage ?? 0, 0.95)
    }

    func testLoopThatSkipsTheDetourIsRouteVariantOfTheDetourRoute() {
        let route = Self.makeRoute(points: Self.detourLoop(), distanceMeters: 4_500)
        let run = Self.makeRun(day: 2, distanceMeters: 4_000, points: Self.plainLoop())

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertEqual(match?.confidence, .routeVariant)
        XCTAssertEqual(match?.routeID, route.id)
    }

    /// Start and finish alone are not enough: every run from the front door shares them.
    func testDifferentLoopFromTheSameStartDoesNotCountTowardTheRoute() {
        let route = Self.makeRoute(points: Self.plainLoop(), distanceMeters: 4_000)
        let run = Self.makeRun(day: 2, distanceMeters: 4_000, points: Self.westLoop())

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertLessThanOrEqual(match?.startDeltaMeters ?? .infinity, 1)
        XCTAssertLessThanOrEqual(match?.endDeltaMeters ?? .infinity, 1)
        XCTAssertFalse(match?.confidence.countsTowardRoute ?? true)
        XCTAssertNil(match?.routeID)
        XCTAssertLessThan(match?.routeCoverage ?? 1, 0.5)
    }

    /// Codex finding on #161: on an out-and-back route, the outbound leg alone covers both
    /// legs. A run that returns by another street must not count, as a match or a variant.
    func testOutAndBackRouteNeedsTheRunToComeBackTheSameWay() {
        let outAndBack = Self.trace([(0, 0), (0, 1_000), (0, 0)])
        let route = Self.makeRoute(points: outAndBack, distanceMeters: 2_000)

        let sameWayBack = Self.makeRun(day: 2, distanceMeters: 2_000, points: outAndBack)
        XCTAssertEqual(RouteMatchingService.match(run: sameWayBack, savedRoutes: [route])?.confidence, .matched)

        let nearbyStreetBack = Self.makeRun(day: 2, distanceMeters: 2_044, points: Self.trace([(0, 0), (0, 1_000), (150, 500), (0, 0)]))
        let nearbyMatch = RouteMatchingService.match(run: nearbyStreetBack, savedRoutes: [route])
        XCTAssertGreaterThanOrEqual(nearbyMatch?.routeCoverage ?? 0, 0.95, "The outbound leg alone covers the route")
        XCTAssertFalse(nearbyMatch?.confidence.countsTowardRoute ?? true)

        let farStreetBack = Self.makeRun(day: 2, distanceMeters: 2_281, points: Self.trace([(0, 0), (0, 1_000), (400, 500), (0, 0)]))
        XCTAssertFalse(RouteMatchingService.match(run: farStreetBack, savedRoutes: [route])?.confidence.countsTowardRoute ?? true)
    }

    func testRunMuchLongerThanTheRouteIsNotAVariant() {
        let route = Self.makeRoute(points: Self.plainLoop(), distanceMeters: 4_000)
        let run = Self.makeRun(day: 2, distanceMeters: 5_400, points: Self.detourLoop())

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertFalse(match?.confidence.countsTowardRoute ?? true, "+35% is a different workout, not a variant")
    }

    func testBenchmarkRouteWinsOverTheRunsOwnSavedRoute() {
        let plain = Self.makeRoute(points: Self.plainLoop(), distanceMeters: 4_000)
        let detour = Self.makeRoute(points: Self.detourLoop(), distanceMeters: 4_500)
        let run = Self.makeRun(day: 2, distanceMeters: 4_500, points: Self.detourLoop())

        let withoutBenchmark = RouteMatchingService.match(run: run, savedRoutes: [plain, detour])
        XCTAssertEqual(withoutBenchmark?.routeID, detour.id)
        XCTAssertEqual(withoutBenchmark?.confidence, .matched)

        let withBenchmark = RouteMatchingService.match(run: run, savedRoutes: [plain, detour], benchmarkRouteIDs: [plain.id])
        XCTAssertEqual(withBenchmark?.routeID, plain.id)
        XCTAssertEqual(withBenchmark?.confidence, .routeVariant)
    }

    func testRematchMovesRunFromItsOwnRouteToTheBenchmark() {
        let plain = Self.makeRoute(points: Self.plainLoop(), distanceMeters: 4_000)
        let detour = Self.makeRoute(points: Self.detourLoop(), distanceMeters: 4_500)
        let existing = RouteMatchingService.exactMatch(routeID: detour.id)
        let candidate = RouteMatchResult(
            routeID: plain.id,
            candidateRouteID: plain.id,
            confidence: .routeVariant,
            distanceDeltaMeters: 500,
            startDeltaMeters: 0,
            endDeltaMeters: 0,
            shapeSimilarity: 0.6,
            isReversed: false,
            routeCoverage: 1
        )

        let preferred = RouteRematchService.preferredResult(
            existing: existing,
            candidate: candidate,
            savedRouteIDs: [plain.id, detour.id],
            benchmarkRouteIDs: [plain.id]
        )
        XCTAssertEqual(preferred, candidate)

        let noBenchmark = RouteRematchService.preferredResult(
            existing: existing,
            candidate: candidate,
            savedRouteIDs: [plain.id, detour.id]
        )
        XCTAssertEqual(noBenchmark, existing, "Without a benchmark a full match is not replaced by a variant")
    }

    // MARK: - Founder flow, end to end

    /// Oct 18: plain loop, route saved. Oct 21: loop with a detour, route saved from it too.
    /// Benchmarking the Oct 18 route must bring both runs into one comparison, by pace.
    func testBenchmarkOnPlainLoopComparesBothRunsByPace() async {
        let services = ProductionRunSmartServices()
        let oct18 = Self.makeRun(day: 1, distanceMeters: 4_000, movingTime: 1_540, points: Self.plainLoop())
        let oct21 = Self.makeRun(day: 4, distanceMeters: 4_500, movingTime: 1_710, points: Self.detourLoop())
        _ = await services.saveRouteMatch(for: oct18)
        let plainRoute = SavedRoute.from(run: oct18, name: "Park loop")
        _ = await services.saveRoute(plainRoute, fromRun: oct18)

        _ = await services.saveRouteMatch(for: oct21)
        let detourRoute = SavedRoute.from(run: oct21, name: "Park loop + detour")
        _ = await services.saveRoute(detourRoute, fromRun: oct21)
        let beforeBenchmark = await Self.storedRun(oct21.id)
        XCTAssertEqual(beforeBenchmark?.routeMatchResult?.routeID, detourRoute.id)

        _ = await services.enableBenchmark(for: plainRoute.id)

        let oct21Stored = await Self.storedRun(oct21.id)
        XCTAssertEqual(oct21Stored?.routeMatchResult?.routeID, plainRoute.id)
        XCTAssertEqual(oct21Stored?.routeMatchResult?.confidence, .routeVariant)

        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == plainRoute.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 2)
        XCTAssertEqual(benchmark?.personalBestSeconds, 1_540, "Route PB is a time, so only the full-route run sets it")

        guard let oct21Stored else { return XCTFail("Run missing from store") }
        let comparison = await services.benchmarkComparison(for: oct21Stored)
        XCTAssertEqual(comparison?.previousPerformance?.runID, oct18.id)
        XCTAssertEqual(comparison?.comparesPace, true)
        XCTAssertEqual(comparison?.currentDistanceDeltaMeters ?? 0, 500, accuracy: 0.5)
    }

    func testBenchmarkOnDetourLoopAlsoComparesBothRuns() async {
        let services = ProductionRunSmartServices()
        let oct18 = Self.makeRun(day: 1, distanceMeters: 4_000, movingTime: 1_540, points: Self.plainLoop())
        let oct21 = Self.makeRun(day: 4, distanceMeters: 4_500, movingTime: 1_710, points: Self.detourLoop())
        _ = await services.saveRouteMatch(for: oct18)
        _ = await services.saveRoute(SavedRoute.from(run: oct18, name: "Park loop"), fromRun: oct18)
        _ = await services.saveRouteMatch(for: oct21)
        let detourRoute = SavedRoute.from(run: oct21, name: "Park loop + detour")
        _ = await services.saveRoute(detourRoute, fromRun: oct21)

        _ = await services.enableBenchmark(for: detourRoute.id)

        let oct18Stored = await Self.storedRun(oct18.id)
        XCTAssertEqual(oct18Stored?.routeMatchResult?.routeID, detourRoute.id)
        XCTAssertEqual(oct18Stored?.routeMatchResult?.confidence, .routeVariant)
        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == detourRoute.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 2)
    }

    /// Codex finding on #161: with both loops benchmarked, the detour run sits on its own route.
    /// Turning that benchmark off must move it to the remaining one.
    func testDisablingABenchmarkMovesItsRunsToTheRemainingBenchmark() async {
        let services = ProductionRunSmartServices()
        let oct18 = Self.makeRun(day: 1, distanceMeters: 4_000, movingTime: 1_540, points: Self.plainLoop())
        let oct21 = Self.makeRun(day: 4, distanceMeters: 4_500, movingTime: 1_710, points: Self.detourLoop())
        _ = await services.saveRouteMatch(for: oct18)
        let plainRoute = SavedRoute.from(run: oct18, name: "Park loop")
        _ = await services.saveRoute(plainRoute, fromRun: oct18)
        _ = await services.saveRouteMatch(for: oct21)
        let detourRoute = SavedRoute.from(run: oct21, name: "Park loop + detour")
        _ = await services.saveRoute(detourRoute, fromRun: oct21)
        _ = await services.enableBenchmark(for: plainRoute.id)
        _ = await services.enableBenchmark(for: detourRoute.id)
        let bothBenchmarked = await Self.storedRun(oct21.id)
        XCTAssertEqual(bothBenchmarked?.routeMatchResult?.routeID, detourRoute.id)

        _ = await services.disableBenchmark(for: detourRoute.id)

        let stored = await Self.storedRun(oct21.id)
        XCTAssertEqual(stored?.routeMatchResult?.routeID, plainRoute.id)
        XCTAssertEqual(stored?.routeMatchResult?.confidence, .routeVariant)
        let benchmark = await RunSmartLocalStore.shared.loadBenchmarkRoutes().first { $0.savedRouteID == plainRoute.id }
        XCTAssertEqual(benchmark?.historicalRunCount, 2)
    }

    func testDeletingARouteMovesItsRunsToTheBenchmark() async {
        let services = ProductionRunSmartServices()
        let oct18 = Self.makeRun(day: 1, distanceMeters: 4_000, movingTime: 1_540, points: Self.plainLoop())
        let oct21 = Self.makeRun(day: 4, distanceMeters: 4_500, movingTime: 1_710, points: Self.detourLoop())
        _ = await services.saveRouteMatch(for: oct18)
        let plainRoute = SavedRoute.from(run: oct18, name: "Park loop")
        _ = await services.saveRoute(plainRoute, fromRun: oct18)
        _ = await services.saveRouteMatch(for: oct21)
        let detourRoute = SavedRoute.from(run: oct21, name: "Park loop + detour")
        _ = await services.saveRoute(detourRoute, fromRun: oct21)
        _ = await services.enableBenchmark(for: plainRoute.id)
        _ = await services.enableBenchmark(for: detourRoute.id)

        _ = await services.deleteRoute(detourRoute.id)

        let stored = await Self.storedRun(oct21.id)
        XCTAssertEqual(stored?.routeMatchResult?.routeID, plainRoute.id)
    }

    /// Codex finding on #161: a run can count toward any saved route, but the post-run card and
    /// its analytics only call it a benchmark run when that route is an enabled benchmark.
    func testPostRunCardCallsItABenchmarkRunOnlyForAnEnabledBenchmark() {
        let routeID = UUID()
        var run = Self.makeRun(day: 1, distanceMeters: 4_500, points: Self.detourLoop())
        run.routeMatchResult = RouteMatchResult(
            routeID: routeID,
            candidateRouteID: routeID,
            confidence: .routeVariant,
            distanceDeltaMeters: 500,
            startDeltaMeters: 0,
            endDeltaMeters: 0,
            shapeSimilarity: 0.6,
            isReversed: false,
            routeCoverage: 1
        )

        XCTAssertFalse(PostRunLearningCardModel.countsTowardBenchmark(run, benchmarkRouteIDs: []))
        XCTAssertTrue(PostRunLearningCardModel.countsTowardBenchmark(run, benchmarkRouteIDs: [routeID]))

        let plainSaved = PostRunLearningCardModel.make(run: run, outcome: nil, report: nil, activePlan: nil)
        XCTAssertFalse(plainSaved.happened.contains("benchmark route"))
        let benchmarked = PostRunLearningCardModel.make(run: run, outcome: nil, report: nil, activePlan: nil, benchmarkRouteIDs: [routeID])
        XCTAssertTrue(benchmarked.happened.contains("benchmark route"))
    }

    // MARK: - Stats and copy

    func testStatRefreshCountsVariantsButTakesTimesFromFullRouteRunsOnly() {
        let routeID = UUID()
        var full = Self.makeRun(day: 1, distanceMeters: 4_000, movingTime: 1_600, points: Self.plainLoop())
        full.routeMatchResult = RouteMatchingService.exactMatch(routeID: routeID)
        var variant = Self.makeRun(day: 2, distanceMeters: 3_500, movingTime: 1_300, points: Self.plainLoop())
        variant.routeMatchResult = RouteMatchResult(
            routeID: routeID,
            candidateRouteID: routeID,
            confidence: .routeVariant,
            distanceDeltaMeters: 500,
            startDeltaMeters: 0,
            endDeltaMeters: 0,
            shapeSimilarity: 0.6,
            isReversed: false,
            routeCoverage: 0.88
        )
        let benchmark = BenchmarkRoute(
            id: UUID(),
            savedRouteID: routeID,
            enabledAt: Date(timeIntervalSince1970: 0),
            historicalRunCount: 0,
            personalBestSeconds: nil,
            personalBestDate: nil,
            averagePaceSecondsPerKm: nil,
            averageDurationSeconds: nil
        )

        let updated = BenchmarkStatRefresh.refresh([benchmark], from: [full, variant])

        XCTAssertEqual(updated.first?.historicalRunCount, 2)
        XCTAssertEqual(updated.first?.personalBestSeconds, 1_600, "The shorter variant's 1,300 s must not become the route PB")
        XCTAssertEqual(updated.first?.averageDurationSeconds, 1_600)
    }

    func testVariantInsightsCompareDistanceAndPaceNotTime() {
        let routeID = UUID()
        let previous = BenchmarkRunPerformance(
            runID: UUID(),
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 1_000),
            durationSeconds: 1_540,
            paceSecondsPerKm: 385,
            averageHeartRateBPM: nil,
            distanceMeters: 4_000,
            matchConfidence: .matched
        )
        let current = BenchmarkRunPerformance(
            runID: UUID(),
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 90_000),
            durationSeconds: 1_710,
            paceSecondsPerKm: 380,
            averageHeartRateBPM: nil,
            distanceMeters: 4_490,
            matchConfidence: .routeVariant
        )
        let comparison = BenchmarkRouteComparison(
            routeID: routeID,
            routeName: "Park loop",
            matchConfidence: .routeVariant,
            currentPerformance: current,
            previousPerformance: previous,
            personalBest: previous,
            allTimeAverage: BenchmarkPerformanceAverage(
                routeID: routeID,
                runCount: 2,
                averageDurationSeconds: 1_625,
                averagePaceSecondsPerKm: 382.5,
                bestPaceSecondsPerKm: 380,
                averageHeartRateBPM: nil
            ),
            monthlyAverage: MonthlyBenchmarkAverage(
                routeID: routeID,
                monthStart: Date(timeIntervalSince1970: 0),
                runCount: 2,
                averageDurationSeconds: 1_625,
                averagePaceSecondsPerKm: 382.5,
                bestPaceSecondsPerKm: 380,
                averageHeartRateBPM: nil,
                hasEnoughData: true
            ),
            recentTrend: .notEnoughData,
            routeDistanceMeters: 4_000
        )

        XCTAssertEqual(BenchmarkComparisonPresentation.insights(for: comparison), [
            "This run was 0.49 km longer than Park loop, so RunSmart compares pace, not time.",
            "Your pace was 0:05 /km faster than your previous run on this route.",
            "This is your best pace on Park loop.",
        ])
        let shared = ProgressSharePayload.benchmark(comparison).metrics
        XCTAssertEqual(shared.map(\.title), ["This Run", "Best Pace", "Month Avg"], "A variant shares pace, never its total time against the route PB")
        XCTAssertEqual(shared.first?.value, "6:20 /km")
        XCTAssertEqual(BenchmarkComparisonPresentation.paceDeltaLabel(current: 380, baseline: 385), "-0:05 /km")
        XCTAssertEqual(BenchmarkComparisonPresentation.distanceDeltaLabel(490), "+0.49 km")
    }

    /// Plain loop, then a detour, then the plain loop again: the third run is a full match, so
    /// it keeps its route time PB even though its previous run was a variant.
    func testFullRouteRunAfterAVariantKeepsItsRoutePB() async {
        let services = ProductionRunSmartServices()
        let first = Self.makeRun(day: 1, distanceMeters: 4_000, movingTime: 1_600, points: Self.plainLoop())
        let detour = Self.makeRun(day: 2, distanceMeters: 4_500, movingTime: 1_750, points: Self.detourLoop())
        let third = Self.makeRun(day: 3, distanceMeters: 4_000, movingTime: 1_540, points: Self.plainLoop())
        _ = await services.saveRouteMatch(for: first)
        let route = SavedRoute.from(run: first, name: "Park loop")
        _ = await services.saveRoute(route, fromRun: first)
        _ = await services.enableBenchmark(for: route.id)
        _ = await services.saveRouteMatch(for: detour)
        let thirdStored = await services.saveRouteMatch(for: third)

        let comparison = await services.benchmarkComparison(for: thirdStored)

        XCTAssertEqual(comparison?.previousPerformance?.runID, detour.id)
        XCTAssertEqual(comparison?.comparesPace, true, "Against a variant the previous-run delta is by pace")
        XCTAssertEqual(comparison?.currentPerformance.isRouteVariant, false)
        XCTAssertEqual(comparison?.personalBest.runID, third.id)
        guard let comparison else { return XCTFail("No comparison") }
        XCTAssertTrue(BenchmarkComparisonPresentation.insights(for: comparison).contains("This is your personal best on Park loop."))
    }

    // MARK: - Fixtures

    @MainActor
    private static func storedRun(_ id: UUID) -> RecordedRun? {
        RunSmartLocalStore.shared.loadRuns().first { $0.id == id }
    }

    /// 1 km square loop, counter-clockwise from the start: north, east, south, west.
    private static func plainLoop() -> [RunRoutePoint] {
        trace([(0, 0), (0, 1_000), (1_000, 1_000), (1_000, 0), (0, 0)])
    }

    /// The same loop with a 250 m out-and-back spur from the middle of the top edge (+500 m).
    private static func detourLoop() -> [RunRoutePoint] {
        trace([(0, 0), (0, 1_000), (500, 1_000), (500, 1_250), (500, 1_000), (1_000, 1_000), (1_000, 0), (0, 0)])
    }

    /// A different 1 km square from the same start: it shares only the first (north) edge.
    private static func westLoop() -> [RunRoutePoint] {
        trace([(0, 0), (0, 1_000), (-1_000, 1_000), (-1_000, 0), (0, 0)])
    }

    /// Points every 25 m along the corners, given in meters east and north of a remote origin.
    private static func trace(_ corners: [(Double, Double)]) -> [RunRoutePoint] {
        let originLatitude = -20.0
        let originLongitude = -20.0
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(originLatitude * .pi / 180)
        var meters: [(Double, Double)] = [corners[0]]
        for (a, b) in zip(corners, corners.dropFirst()) {
            let length = hypot(b.0 - a.0, b.1 - a.1)
            let steps = max(1, Int((length / 25).rounded()))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                meters.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
            }
        }
        let start = Date(timeIntervalSince1970: 1_000)
        return meters.enumerated().map { index, point in
            RunRoutePoint(
                latitude: originLatitude + point.1 / metersPerDegreeLatitude,
                longitude: originLongitude + point.0 / metersPerDegreeLongitude,
                timestamp: start.addingTimeInterval(Double(index) * 9),
                horizontalAccuracy: 6,
                altitude: nil
            )
        }
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

    private static func makeRoute(points: [RunRoutePoint], distanceMeters: Double) -> SavedRoute {
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
}
