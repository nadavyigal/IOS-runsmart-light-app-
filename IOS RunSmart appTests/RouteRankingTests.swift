import XCTest
@testable import IOS_RunSmart_app

final class RouteRankingTests: XCTestCase {

    // MARK: - reason string helpers

    func testBenchmarkReasonMatchesDistance() {
        let reason = RouteSuggestionRanker.reason(
            kind: .benchmark,
            distanceKm: 8.1,
            targetDistanceKm: 8.0,
            isFavorite: false,
            daysSinceLastRun: nil
        )
        XCTAssertTrue(reason.contains("8"), "Expected distance in reason, got: \(reason)")
    }

    func testSavedFavoriteReason() {
        let reason = RouteSuggestionRanker.reason(
            kind: .saved,
            distanceKm: 5.0,
            targetDistanceKm: nil,
            isFavorite: true,
            daysSinceLastRun: nil
        )
        XCTAssertTrue(reason.lowercased().contains("favorite"), "Got: \(reason)")
    }

    func testPastRouteReasonIncludesDays() {
        let reason = RouteSuggestionRanker.reason(
            kind: .past,
            distanceKm: 5.0,
            targetDistanceKm: nil,
            isFavorite: false,
            daysSinceLastRun: 3
        )
        XCTAssertTrue(reason.contains("3"), "Got: \(reason)")
    }

    func testGeneratedRouteReason() {
        let reason = RouteSuggestionRanker.reason(
            kind: .generated,
            distanceKm: 8.0,
            targetDistanceKm: 8.0,
            isFavorite: false,
            daysSinceLastRun: nil
        )
        XCTAssertFalse(reason.isEmpty, "Generated reason should not be empty")
    }

    // MARK: - ranking order

    func testBenchmarkRanksAboveSavedAbovePast() {
        let benchmark = RouteSuggestion(id: "b", name: "B", distanceKm: 8.0,
            elevationGainMeters: 40, estimatedDurationMinutes: 44,
            points: [], kind: .benchmark)
        let saved = RouteSuggestion(id: "s", name: "S", distanceKm: 8.0,
            elevationGainMeters: 40, estimatedDurationMinutes: 44,
            points: [], kind: .saved)
        let past = RouteSuggestion(id: "p", name: "P", distanceKm: 8.0,
            elevationGainMeters: 40, estimatedDurationMinutes: 44,
            points: [], kind: .past)
        let ranked = RouteSuggestionRanker.rank([past, saved, benchmark], targetDistanceKm: 8.0)
        XCTAssertEqual(ranked.map(\.id), ["b", "s", "p"])
    }

    func testDistanceFilterExcludes() {
        let close = RouteSuggestion(id: "close", name: "C", distanceKm: 8.3,
            elevationGainMeters: 0, estimatedDurationMinutes: 0, points: [], kind: .past)
        let far = RouteSuggestion(id: "far", name: "F", distanceKm: 5.0,
            elevationGainMeters: 0, estimatedDurationMinutes: 0, points: [], kind: .past)
        let filtered = RouteSuggestionRanker.filter([close, far], targetDistanceKm: 8.0)
        XCTAssertTrue(filtered.contains(where: { $0.id == "close" }))
        XCTAssertFalse(filtered.contains(where: { $0.id == "far" }))
    }

    func testNilTargetDistanceReturnsAll() {
        let r1 = RouteSuggestion(id: "1", name: "", distanceKm: 3.0,
            elevationGainMeters: 0, estimatedDurationMinutes: 0, points: [], kind: .past)
        let r2 = RouteSuggestion(id: "2", name: "", distanceKm: 15.0,
            elevationGainMeters: 0, estimatedDurationMinutes: 0, points: [], kind: .past)
        XCTAssertEqual(RouteSuggestionRanker.filter([r1, r2], targetDistanceKm: nil).count, 2)
    }

    // MARK: - Elevation preference ranking

    func testFlatPreferenceRanksFlatRouteFirst() {
        // flat = ≤50 m gain, rolling = 51-150 m, hilly = >150 m
        let flat = RouteSuggestion(id: "flat", name: "Flat", distanceKm: 8.0,
            elevationGainMeters: 20, estimatedDurationMinutes: 44,
            points: [], kind: .saved)
        let hilly = RouteSuggestion(id: "hilly", name: "Hilly", distanceKm: 8.0,
            elevationGainMeters: 200, estimatedDurationMinutes: 55,
            points: [], kind: .saved)
        let ranked = RouteSuggestionRanker.rank([hilly, flat], targetDistanceKm: 8.0, elevationPreference: "Flat")
        XCTAssertEqual(ranked.first?.id, "flat", "Flat route should rank first with Flat preference")
    }

    func testHillyPreferenceRanksHighElevationFirst() {
        let flat = RouteSuggestion(id: "flat", name: "Flat", distanceKm: 8.0,
            elevationGainMeters: 20, estimatedDurationMinutes: 44,
            points: [], kind: .saved)
        let hilly = RouteSuggestion(id: "hilly", name: "Hilly", distanceKm: 8.0,
            elevationGainMeters: 200, estimatedDurationMinutes: 55,
            points: [], kind: .saved)
        let ranked = RouteSuggestionRanker.rank([flat, hilly], targetDistanceKm: 8.0, elevationPreference: "Hilly")
        XCTAssertEqual(ranked.first?.id, "hilly", "Hilly route should rank first with Hilly preference")
    }

    func testRollingPreferenceRanksRollingRouteFirst() {
        let flat = RouteSuggestion(id: "flat", name: "Flat", distanceKm: 8.0,
            elevationGainMeters: 20, estimatedDurationMinutes: 44,
            points: [], kind: .saved)
        let rolling = RouteSuggestion(id: "rolling", name: "Rolling", distanceKm: 8.0,
            elevationGainMeters: 100, estimatedDurationMinutes: 48,
            points: [], kind: .saved)
        let ranked = RouteSuggestionRanker.rank([flat, rolling], targetDistanceKm: 8.0, elevationPreference: "Rolling")
        XCTAssertEqual(ranked.first?.id, "rolling", "Rolling route should rank first with Rolling preference")
    }

    func testElevationPreferenceDoesNotOverrideKindPriority() {
        // Benchmark must always rank above saved regardless of elevation preference
        let hillyBenchmark = RouteSuggestion(id: "bench", name: "Benchmark", distanceKm: 8.0,
            elevationGainMeters: 250, estimatedDurationMinutes: 60,
            points: [], kind: .benchmark)
        let flatSaved = RouteSuggestion(id: "saved", name: "Saved", distanceKm: 8.0,
            elevationGainMeters: 10, estimatedDurationMinutes: 44,
            points: [], kind: .saved)
        let ranked = RouteSuggestionRanker.rank([flatSaved, hillyBenchmark], targetDistanceKm: 8.0, elevationPreference: "Flat")
        XCTAssertEqual(ranked.first?.id, "bench", "Benchmark must rank above saved even with mismatched elevation")
    }

    func testGeneratedReasonReflectsElevationPreference() {
        let flat = RouteSuggestionRanker.reason(kind: .generated, distanceKm: 8.0,
            targetDistanceKm: 8.0, isFavorite: false, daysSinceLastRun: nil, elevationPreference: "Flat")
        let hilly = RouteSuggestionRanker.reason(kind: .generated, distanceKm: 8.0,
            targetDistanceKm: 8.0, isFavorite: false, daysSinceLastRun: nil, elevationPreference: "Hilly")
        XCTAssertTrue(flat.lowercased().contains("flat"), "Flat reason should mention flat: \(flat)")
        XCTAssertTrue(hilly.lowercased().contains("hill") || hilly.lowercased().contains("elevation"), "Hilly reason should mention elevation: \(hilly)")
    }

    // MARK: - Today route recommendation

    func testRouteRecommendationPrefersWorkoutDistanceOverKindPriorityWhenFitIsBetter() {
        let benchmarkTooLong = RouteSuggestion(
            id: "benchmark",
            name: "Benchmark Long",
            distanceKm: 14.0,
            elevationGainMeters: 60,
            estimatedDurationMinutes: 78,
            points: makePoints(),
            kind: .benchmark
        )
        let savedMatch = RouteSuggestion(
            id: "saved",
            name: "Saved Match",
            distanceKm: 8.1,
            elevationGainMeters: 35,
            estimatedDurationMinutes: 44,
            points: makePoints(),
            kind: .saved,
            isFavorite: true
        )
        let workout = makeWorkout(kind: .tempo, distance: "8 km")

        let recommendation = RouteSuggestionRanker.recommendation(
            from: [benchmarkTooLong, savedMatch],
            workout: workout
        )

        XCTAssertEqual(recommendation.route?.id, "saved")
        XCTAssertGreaterThan(recommendation.fitScore, 70)
        XCTAssertNil(recommendation.warning)
        XCTAssertTrue(recommendation.reason.lowercased().contains("pace"))
    }

    func testRouteRecommendationWarnsWhenRouteHasNoPoints() {
        let garminBucket = RouteSuggestion(
            id: "garmin",
            name: "5K from Garmin",
            distanceKm: 5.0,
            elevationGainMeters: 20,
            estimatedDurationMinutes: 30,
            points: [],
            kind: .past
        )

        let recommendation = RouteSuggestionRanker.recommendation(
            from: [garminBucket],
            workout: makeWorkout(kind: .easy, distance: "5 km")
        )

        XCTAssertEqual(recommendation.route?.id, "garmin")
        XCTAssertTrue(recommendation.warning?.contains("No route map points") == true)
    }

    func testRouteRecommendationEmptyStateIsUseful() {
        let recommendation = RouteSuggestionRanker.recommendation(
            from: [],
            workout: makeWorkout(kind: .easy, distance: "5 km")
        )

        XCTAssertFalse(recommendation.isAvailable)
        XCTAssertEqual(recommendation.unavailableReason, .noRoutes)
        XCTAssertTrue(recommendation.reason.contains("GPS run"))
    }

    func testDistanceParserHandlesMilesAndKilometers() {
        XCTAssertEqual(RouteSuggestionRanker.distanceKm(from: "8 km"), 8.0)
        XCTAssertEqual(RouteSuggestionRanker.distanceKm(from: "3.1 miles") ?? 0, 4.989, accuracy: 0.01)
    }

    private func makeWorkout(kind: WorkoutKind, distance: String) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            scheduledDate: Date(),
            planID: nil,
            weekday: "Mon",
            date: "Today",
            kind: kind,
            title: kind.rawValue,
            distance: distance,
            detail: "",
            isToday: true,
            isComplete: false
        )
    }

    private func makePoints() -> [RunRoutePoint] {
        (0..<8).map { index in
            RunRoutePoint(
                latitude: 32.0 + Double(index) * 0.001,
                longitude: 34.0 + Double(index) * 0.001,
                timestamp: Date().addingTimeInterval(Double(index) * 60),
                horizontalAccuracy: 8,
                altitude: nil
            )
        }
    }
}
