import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachRunRouteTests: XCTestCase {
    private func row(_ state: String, route: [CoachRouteCoordinate]? = nil) -> CoachRunRouteRow {
        CoachRunRouteRow(state: state, route: route)
    }

    private let route = [CoachRouteCoordinate(lat: 32.08, lng: 34.78), CoachRouteCoordinate(lat: 32.09, lng: 34.79)]

    func testEachStateAndItsExactCopy() {
        XCTAssertEqual(CoachRunRouteMapping.state(row("map", route: route)), .map(route))
        XCTAssertEqual(CoachRunRouteMapping.state(row("hidden")), .hidden)
        XCTAssertEqual(CoachRunRouteMapping.state(row("route_hidden")), .routeHidden)
        XCTAssertEqual(CoachRunRouteMapping.state(row("no_map")), .noMap)
        XCTAssertEqual(CoachRunRouteState.hidden.copy, "Map hidden")
        XCTAssertEqual(CoachRunRouteState.routeHidden.copy, "Route hidden")
        XCTAssertEqual(CoachRunRouteState.noMap.copy, "No map")
        XCTAssertNil(CoachRunRouteState.map(route).copy, "a map shows the map, not text")
        XCTAssertEqual(CoachRunRouteMapping.caption, "Start/end hidden for privacy")
        XCTAssertEqual(CoachRunRouteMapping.loadFailed, "Couldn't load the map.")
    }

    func testUnknownOrIncompleteRowsRevealNothing() {
        XCTAssertEqual(CoachRunRouteMapping.state(row("syncing")), .noMap, "an unknown state never hints at the setting")
        XCTAssertEqual(CoachRunRouteMapping.state(row("map", route: nil)), .noMap)
        XCTAssertEqual(CoachRunRouteMapping.state(row("map", route: [route[0]])), .noMap, "one point can't be drawn")
    }

    func testDecodesTheServerRowWithTheRouteCoordinates() throws {
        let json = #"[{"state":"map","route":[{"lat":32.08,"lng":34.78},{"lat":32.09,"lng":34.79}]},{"state":"hidden","route":null}]"#
        let rows = try JSONDecoder().decode([CoachRunRouteRow].self, from: Data(json.utf8))
        XCTAssertEqual(CoachRunRouteMapping.state(rows[0]), .map(route))
        XCTAssertEqual(CoachRunRouteMapping.state(rows[1]), .hidden)
        let points = CoachRunRouteMapping.points(route)
        XCTAssertEqual(points.map(\.latitude), [32.08, 32.09])
        XCTAssertEqual(points.map(\.longitude), [34.78, 34.79])
    }

    func testAltTextNamesTheDayAndDistance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let saturday = ISO8601DateFormatter().date(from: "2026-11-14T07:00:00Z")!
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(CoachRunRouteMapping.altText(completedAt: saturday, distanceKm: 8.2, calendar: calendar, locale: locale),
                       "Route map for Saturday's run, 8.2 kilometres")
        XCTAssertEqual(CoachRunRouteMapping.altText(completedAt: saturday, distanceKm: 5, calendar: calendar, locale: locale),
                       "Route map for Saturday's run, 5 kilometres")
    }

    func testLoadingThenEachOutcome() async {
        let service = MockCoachRunRouteService()
        service.rows[1] = row("map", route: route)
        service.rows[2] = row("no_map")
        let mapped = CoachRunMapModel(runID: 1, service: service)
        XCTAssertEqual(mapped.phase, .loading)
        await mapped.load()
        XCTAssertEqual(mapped.phase, .loaded(.map(route)))

        let none = CoachRunMapModel(runID: 2, service: service)
        await none.load()
        XCTAssertEqual(none.phase, .loaded(.noMap), "No map is a state, not an error")

        let revoked = CoachRunMapModel(runID: 3, service: service)
        await revoked.load()
        XCTAssertEqual(revoked.phase, .revoked, "no row means the link is gone")
    }

    func testErrorThenRetryRecovers() async {
        let service = MockCoachRunRouteService()
        service.rows[1] = row("hidden")
        service.failure = URLError(.notConnectedToInternet)
        let model = CoachRunMapModel(runID: 1, service: service)
        await model.load()
        XCTAssertEqual(model.phase, .failed)
        service.failure = nil
        await model.load()
        XCTAssertEqual(model.phase, .loaded(.hidden))
        XCTAssertEqual(service.calls, 2, "Retry reloads only this block")
    }
}
