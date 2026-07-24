import XCTest
@testable import IOS_RunSmart_app

/// Pins the demo/QA service route library loop: save → benchmark → match →
/// comparison. Before the route-feature fix, DemoRunSmartServices hardcoded
/// `saveRoute` to false and `matchRoute`/`benchmarkComparison` to nil, so the
/// entire benchmark feature was dead in every simulator/demo session and
/// could never be QA'd.
final class RouteLibraryDemoServiceTests: XCTestCase {

    // DemoRunSmartServices persists through RunSmartLocalStore, which is bound
    // to UserDefaults.standard. Rather than wiping those production-backed keys
    // (which would destroy a neighbouring test's route state and leave the
    // forced-seeded flag behind), snapshot every key touched here and restore
    // the exact prior values in tearDown.
    private let touchedKeys = [
        "runsmart.savedRoutes",
        "runsmart.benchmarkRoutes",
        "runsmart.demo.routesSeeded",
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
        // Mark seeded so tests start from an empty, deterministic library
        // instead of the preview fixtures.
        defaults.set(true, forKey: "runsmart.demo.routesSeeded")
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

    func testDemoSaveRoutePersistsToLibrary() async {
        let services = DemoRunSmartServices()
        let route = Self.makeRoute(name: "Test Loop")

        let saved = await services.saveRoute(route)
        XCTAssertTrue(saved, "Demo saveRoute must persist the route; returning false makes SaveRouteSheet always fail in demo mode")

        let library = await services.savedRoutes()
        XCTAssertTrue(library.contains { $0.id == route.id }, "Saved route must appear in the library")
    }

    func testDemoBenchmarkLoopMatchesRunAndBuildsComparison() async {
        let services = DemoRunSmartServices()
        let route = Self.makeRoute(name: "Benchmark Loop")

        _ = await services.saveRoute(route)
        let benchmarked = await services.enableBenchmark(for: route.id)
        XCTAssertTrue(benchmarked, "enableBenchmark must succeed for a saved route")

        let run = Self.makeRun(over: route)
        let match = await services.matchRoute(for: run)
        XCTAssertEqual(match?.confidence, .matched, "A run recorded exactly on the saved route must match it")
        XCTAssertEqual(match?.routeID, route.id)

        let comparison = await services.benchmarkComparison(for: run)
        XCTAssertNotNil(comparison, "A matched run on a benchmark route must produce a comparison")
        XCTAssertEqual(comparison?.routeID, route.id)
        XCTAssertEqual(comparison?.currentPerformance.runID, run.id)
    }

    func testDemoRouteSuggestionsCarryMapPointsAndSavedRouteID() async {
        let services = DemoRunSmartServices()
        let route = Self.makeRoute(name: "Card Loop")
        _ = await services.saveRoute(route)
        _ = await services.enableBenchmark(for: route.id)

        let suggestions = await services.rankedRouteSuggestions(targetDistanceKm: nil)
        guard let suggestion = suggestions.first(where: { $0.savedRouteID == route.id }) else {
            XCTFail("Saved route must surface as a suggestion with its savedRouteID; without it the Details action and benchmark badge cannot work")
            return
        }
        XCTAssertEqual(suggestion.kind, .benchmark, "A benchmarked saved route must surface in the Benchmarks bucket")
        XCTAssertFalse(suggestion.points.isEmpty, "Suggestion must carry map points so the route card does not render a blank map")
    }

    // MARK: - Fixtures

    /// A straight ~1.1 km route far from any preview fixture coordinates,
    /// with enough points to clear RouteMatchingService.minimumRoutePoints.
    private static func makeRoute(name: String) -> SavedRoute {
        let points = makePoints()
        let now = Date()
        return SavedRoute(
            id: UUID(),
            name: name,
            distanceMeters: 1_100,
            elevationGainMeters: 5,
            points: points,
            source: .recorded,
            tags: [],
            notes: "",
            isFavorite: false,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func makeRun(over route: SavedRoute) -> RecordedRun {
        let start = Date().addingTimeInterval(-1_800)
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(360),
            distanceMeters: route.distanceMeters,
            movingTimeSeconds: 360,
            averagePaceSecondsPerKm: 360 / (route.distanceMeters / 1_000),
            averageHeartRateBPM: 150,
            routePoints: route.points,
            syncedAt: nil
        )
    }

    private static func makePoints() -> [RunRoutePoint] {
        // 12 points spaced ~100 m apart heading north from a remote anchor.
        let baseLat = 10.0
        let baseLon = 10.0
        let latStepPer100m = 0.0009
        return (0..<12).map { index in
            RunRoutePoint(
                latitude: baseLat + Double(index) * latStepPer100m,
                longitude: baseLon,
                timestamp: Date().addingTimeInterval(Double(index) * 30),
                horizontalAccuracy: 5,
                altitude: nil
            )
        }
    }
}
