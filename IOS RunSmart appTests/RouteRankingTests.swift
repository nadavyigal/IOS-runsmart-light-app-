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
}
