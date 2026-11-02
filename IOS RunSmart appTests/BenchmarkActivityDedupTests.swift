import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class BenchmarkActivityDedupTests: XCTestCase {
    private let routeID = UUID()

    func testFreshCurrentRunWinsOverStoredVariantWithTheSameUUID() throws {
        let current = makeRun(day: 2, duration: 1_600)
        var stale = current
        stale.movingTimeSeconds = 1_700
        stale.averagePaceSecondsPerKm = 340
        stale.routeMatchResult?.confidence = .routeVariant
        let result = try XCTUnwrap(compare(current, history: [stale]))

        XCTAssertEqual(result.currentPerformance.runID, current.id)
        XCTAssertEqual(result.currentPerformance.durationSeconds, 1_600)
        XCTAssertEqual(result.currentPerformance.matchConfidence, .matched)
        XCTAssertEqual(result.allTimeAverage.runCount, 1)
    }

    func testNativeAndHealthCopiesCountOnceForPreviousPBAndAverages() throws {
        let previous = makeRun(day: 1, duration: 1_800)
        let current = makeRun(day: 2, duration: 1_600)
        let oldHealthCopy = healthCopy(of: previous, timeOffset: 5)
        let currentHealthCopy = healthCopy(of: current, timeOffset: -5)

        let result = try XCTUnwrap(compare(current, history: [previous, oldHealthCopy, currentHealthCopy, current]))

        XCTAssertEqual(result.currentPerformance.runID, current.id, "Preserve the explicitly opened run even when Health is richer")
        XCTAssertEqual(result.previousPerformance?.durationSeconds, 1_800, "The current run's Health copy is not a previous run")
        XCTAssertEqual(result.personalBest.runID, current.id)
        XCTAssertEqual(result.allTimeAverage.runCount, 2)
        XCTAssertEqual(result.allTimeAverage.averageDurationSeconds, 1_700, accuracy: 0.001)
        XCTAssertEqual(result.allTimeAverage.averagePaceSecondsPerKm, 340, accuracy: 0.001)
        XCTAssertEqual(result.monthlyAverage.runCount, 2)
        XCTAssertEqual(result.monthlyAverage.averagePaceSecondsPerKm, 340, accuracy: 0.001)
    }

    func testAnOlderPersonalBestIsCountedOnceAcrossProviders() throws {
        let previous = makeRun(day: 1, duration: 1_500)
        let current = makeRun(day: 2, duration: 1_800)
        let result = try XCTUnwrap(compare(current, history: [previous, healthCopy(of: previous), current]))

        XCTAssertEqual(result.personalBest.durationSeconds, 1_500)
        XCTAssertEqual(result.previousPerformance?.durationSeconds, 1_500)
        XCTAssertEqual(result.allTimeAverage.runCount, 2)
        XCTAssertEqual(result.allTimeAverage.averageDurationSeconds, 1_650, accuracy: 0.001)
    }

    func testCurrentProviderIdentitySurvivesAReimportWithAnotherUUID() throws {
        var current = makeRun(day: 2, duration: 1_600)
        current.source = .healthKit
        current.providerActivityID = "health-workout-42"
        var reimported = current
        reimported.id = UUID()
        reimported.averageHeartRateBPM = 145

        let result = try XCTUnwrap(compare(current, history: [reimported]))
        XCTAssertEqual(result.currentPerformance.runID, current.id)
        XCTAssertEqual(result.allTimeAverage.runCount, 1)
    }

    private func compare(_ run: RecordedRun, history: [RecordedRun]) -> BenchmarkRouteComparison? {
        let route = SavedRoute(
            id: routeID, name: "Neighborhood loop", distanceMeters: 5_000,
            elevationGainMeters: 0, points: [], source: .recorded,
            tags: [], notes: "", isFavorite: false,
            createdAt: run.startedAt, updatedAt: run.startedAt
        )
        let benchmark = BenchmarkRoute(
            id: UUID(), savedRouteID: routeID, enabledAt: run.startedAt,
            historicalRunCount: 0, personalBestSeconds: nil, personalBestDate: nil,
            averagePaceSecondsPerKm: nil, averageDurationSeconds: nil
        )
        return BenchmarkRouteAnalyticsService.comparison(
            for: run, runs: history, savedRoutes: [route], benchmarkRoutes: [benchmark]
        )
    }

    private func makeRun(day: Int, duration: Double) -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400)
        var run = RecordedRun(
            id: UUID(), providerActivityID: nil, source: .runSmart,
            startedAt: start, endedAt: start.addingTimeInterval(duration),
            distanceMeters: 5_000, movingTimeSeconds: duration,
            averagePaceSecondsPerKm: duration / 5, averageHeartRateBPM: nil,
            routePoints: [], syncedAt: nil
        )
        run.routeMatchResult = RouteMatchingService.exactMatch(routeID: routeID)
        return run
    }

    private func healthCopy(of run: RecordedRun, timeOffset: Double = 0) -> RecordedRun {
        var copy = run
        copy.id = UUID()
        copy.providerActivityID = UUID().uuidString
        copy.source = .healthKit
        copy.averageHeartRateBPM = 145
        copy.startedAt = run.startedAt.addingTimeInterval(timeOffset)
        copy.endedAt = run.endedAt.addingTimeInterval(timeOffset)
        return copy
    }
}
