import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunReportRouteTests: XCTestCase {
    private let keys = ["runsmart.runs", "runsmart.hiddenRuns", "runsmart.savedRoutes", "runsmart.benchmarkRoutes"]
    private var snapshot: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            snapshot[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = snapshot[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        snapshot = [:]
        super.tearDown()
    }

    func testReportResolvesLowercaseUUIDAndPreservesGPS() {
        let run = makeRun(daysAgo: 2)
        let result = RunReportRunResolver.resolve(runID: run.id.uuidString.lowercased(), runs: [run])
        XCTAssertEqual(result?.id, run.id)
        XCTAssertEqual(result?.routePoints, run.routePoints)
    }

    func testReportResolvesStoredConsolidatedAliasAfterGroupingChanges() {
        var run = makeRun(daysAgo: 2)
        run.consolidatedActivityID = "activity-original-group"
        XCTAssertEqual(RunReportRunResolver.resolve(runID: "activity-original-group", runs: [run])?.id, run.id)
    }

    func testReportResolvesProviderIDToRichCanonicalRun() {
        let rich = makeRun(daysAgo: 2)
        var imported = rich
        imported.id = UUID()
        imported.source = .healthKit
        imported.providerActivityID = "health-workout"
        imported.routePoints = []
        let resolved = RunReportRunResolver.resolve(runID: "health-workout", runs: [rich, imported])
        XCTAssertEqual(resolved?.routePoints, rich.routePoints)
    }

    func testReportDoesNotGuessByDateOrDistanceWhenIDIsUnknown() {
        XCTAssertNil(RunReportRunResolver.resolve(runID: UUID().uuidString, runs: [makeRun(daysAgo: 2)]))
    }

    func testOpaqueProviderIDsRemainCaseSensitive() {
        var run = makeRun(daysAgo: 2)
        run.providerActivityID = "Workout-AbC"
        XCTAssertNil(RunReportRunResolver.resolve(runID: "workout-abc", runs: [run]))
        XCTAssertEqual(RunReportRunResolver.resolve(runID: "Workout-AbC", runs: [run])?.id, run.id)
    }

    func testShortRecordedRunRemainsAvailableToItsReport() async {
        var run = makeRun(daysAgo: 1)
        run.distanceMeters = 500
        run.movingTimeSeconds = 200
        RunSmartLocalStore.shared.saveRun(run)
        let resolved = await ProductionRunSmartServices().recordedRun(forReportRunID: run.id.uuidString)
        XCTAssertEqual(resolved?.routePoints.map(\.latitude), run.routePoints.map(\.latitude))
        XCTAssertEqual(resolved?.routePoints.map(\.longitude), run.routePoints.map(\.longitude))
    }

    func testReopenedReportLoadsRunOlderThanRecentListAndExcludesHiddenRun() async {
        let run = makeRun(daysAgo: 40)
        RunSmartLocalStore.shared.saveRun(run)
        let services = ProductionRunSmartServices()
        let recent = await services.recentRuns()
        XCTAssertFalse(recent.contains { $0.id == run.id })
        let resolved = await services.recordedRun(forReportRunID: run.id.uuidString.lowercased())
        XCTAssertEqual(resolved?.id, run.id)
        _ = RunSmartLocalStore.shared.removeRun(run)
        let removed = await services.recordedRun(forReportRunID: run.id.uuidString)
        XCTAssertNil(removed)
    }

    func testSaveOnceThenReopenThirdRunComparesAllThreeExistingRuns() async throws {
        let services = ProductionRunSmartServices()
        let first = makeRun(daysAgo: 6, seconds: 2_100)
        let second = makeRun(daysAgo: 4, seconds: 2_000)
        let third = makeRun(daysAgo: 1, seconds: 1_900)
        for run in [first, second, third] { RunSmartLocalStore.shared.saveRun(run) }
        let route = SavedRoute.from(run: first, name: "Neighborhood loop")
        let saved = await services.saveRoute(route, fromRun: first)
        let enabled = await services.enableBenchmark(for: route.id)
        XCTAssertTrue(saved)
        XCTAssertTrue(enabled)

        let resolved = await services.recordedRun(forReportRunID: third.id.uuidString.lowercased())
        let reopened = try XCTUnwrap(resolved)
        let result = await services.benchmarkComparison(for: reopened)
        let comparison = try XCTUnwrap(result)
        XCTAssertEqual(comparison.previousPerformance?.runID, second.id)
        XCTAssertEqual(comparison.personalBest.runID, third.id)
        XCTAssertEqual(comparison.allTimeAverage.runCount, 3)
        XCTAssertEqual(comparison.allTimeAverage.averageDurationSeconds, 2_000, accuracy: 0.01)
    }

    func testFreshCurrentRunWinsOverStaleStoredVariant() throws {
        var current = makeRun(daysAgo: 1)
        let route = SavedRoute.from(run: current, name: "Neighborhood loop")
        current.routeMatchResult = RouteMatchingService.exactMatch(routeID: route.id)
        var stale = current
        stale.routeMatchResult?.confidence = .routeVariant
        let comparison = BenchmarkRouteAnalyticsService.comparison(
            for: current, runs: [stale], savedRoutes: [route],
            benchmarkRoutes: [BenchmarkRoute(id: UUID(), savedRouteID: route.id, enabledAt: Date(), historicalRunCount: 0,
                                            personalBestSeconds: nil, personalBestDate: nil,
                                            averagePaceSecondsPerKm: nil, averageDurationSeconds: nil)]
        )
        XCTAssertFalse(try XCTUnwrap(comparison).currentPerformance.isRouteVariant)
    }

    func testOpeningExistingBenchmarkBackfillsRunsFromOlderInstall() async throws {
        let first = makeRun(daysAgo: 6, seconds: 2_100)
        let second = makeRun(daysAgo: 4, seconds: 2_000)
        let third = makeRun(daysAgo: 1, seconds: 1_900)
        let store = RunSmartLocalStore.shared
        for run in [first, second, third] { store.saveRun(run) }
        let route = SavedRoute.from(run: first, name: "Existing route")
        store.saveSavedRoute(route)
        store.saveBenchmarkRoute(BenchmarkRoute(id: UUID(), savedRouteID: route.id, enabledAt: first.startedAt,
                                              historicalRunCount: 0, personalBestSeconds: nil, personalBestDate: nil,
                                              averagePaceSecondsPerKm: nil, averageDurationSeconds: nil))
        let services = ProductionRunSmartServices()
        let resolved = await services.recordedRun(forReportRunID: third.id.uuidString)
        let run = try XCTUnwrap(resolved)
        let result = await services.benchmarkComparison(for: run)
        XCTAssertEqual(result?.allTimeAverage.runCount, 3)
        XCTAssertEqual(result?.previousPerformance?.runID, second.id)
    }

    func testHealthCanonicalDuplicateKeepsSavedRouteActionAfterGPSMerge() async throws {
        var native = makeRun(daysAgo: 1)
        let route = SavedRoute.from(run: native, name: "Saved loop")
        native.routeMatchResult = RouteMatchingService.exactMatch(routeID: route.id)
        var health = native
        health.id = UUID()
        health.source = .healthKit
        health.providerActivityID = "health-import"
        health.averageHeartRateBPM = 150
        health.syncedAt = Date()
        health.routePoints = []
        health.routeMatchResult = nil
        let store = RunSmartLocalStore.shared
        store.saveSavedRoute(route)
        store.saveRun(native)
        store.saveRun(health)
        let resolved = await ProductionRunSmartServices().recordedRun(forReportRunID: native.id.uuidString)
        let canonical = try XCTUnwrap(resolved)
        XCTAssertEqual(canonical.id, health.id)
        XCTAssertFalse(canonical.routePoints.isEmpty)
        XCTAssertEqual(canonical.routeMatchResult?.routeID, route.id,
                       "Reopened report must open the existing route rather than offer Save Route again")
    }

    private func makeRun(daysAgo: Int, seconds: Double = 2_000) -> RecordedRun {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let points = (0..<40).map { index in
            let angle = Double(index) / 39 * 2 * Double.pi
            return RunRoutePoint(latitude: 32 + 0.006 * sin(angle), longitude: 34.8 + 0.006 * cos(angle),
                                 timestamp: start.addingTimeInterval(Double(index) * seconds / 39), horizontalAccuracy: 8, altitude: nil)
        }
        return RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart, startedAt: start,
                           endedAt: start.addingTimeInterval(seconds), distanceMeters: 5_000,
                           movingTimeSeconds: seconds, averagePaceSecondsPerKm: seconds / 5,
                           averageHeartRateBPM: nil, routePoints: points, syncedAt: nil)
    }
}
