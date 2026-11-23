import XCTest
@testable import IOS_RunSmart_app

// C7.6 AC5: a tapped evening summary opens Coach Today filtered to "Missed today" (T2), with
// "Show all", and the A.5 copy once everyone on the 20:00 list has logged a run.

@MainActor
final class CoachEveningSummaryTests: XCTestCase {
    private let yoni = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    private let maya = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!
    private let roi = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000003")!
    private let noa = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000004")!

    private func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func summary(_ id: UUID, _ name: String) -> CoachAthleteSummary {
        CoachAthleteSummary(athleteID: id, displayName: name, linkedAt: iso("2026-01-01T00:00:00Z"), hasActivePlan: true)
    }

    private func workout(_ id: UUID, _ athlete: UUID, _ date: String, type: String = "easy") throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(id)","athlete_id":"\(athlete)","plan_id":"\(UUID())","scheduled_date":"\(date)",
        "type":"\(type)","planned_distance":10,"planned_duration_minutes":50,"completed":false}
        """.utf8))
    }

    private func run(_ id: Int, _ athlete: UUID, linkedTo workout: UUID, at stamp: String, km: Double) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":"\(workout)","completed_at":"\(stamp)",
        "distance_km":\(km),"duration_seconds":\(Int(km * 340))}
        """.utf8))
    }

    /// Mon 23 Nov 2026 in UTC. Yoni has no run (missed), Maya ran 5 of 10 km (partial), Roi ran it all
    /// (done), Noa rests. A run passed in `late` is Yoni's, logged after the summary.
    private func snapshot(
        now: String = "2026-11-23T20:30:00Z", late: Bool = false, runsLoaded: Bool = true
    ) throws -> CoachTodaySnapshot {
        let yoniWorkout = UUID(), mayaWorkout = UUID(), roiWorkout = UUID()
        var runs = try [
            run(1, maya, linkedTo: mayaWorkout, at: "2026-11-23T07:00:00Z", km: 5),
            run(2, roi, linkedTo: roiWorkout, at: "2026-11-23T07:00:00Z", km: 10),
        ]
        if late { runs.append(try run(3, yoni, linkedTo: yoniWorkout, at: "2026-11-23T20:40:00Z", km: 10)) }
        let date = iso(now)
        let week = CoachAthleteWeek(now: date, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        return CoachTodaySnapshot.make(
            athletes: [summary(yoni, "Yoni"), summary(maya, "Maya"), summary(roi, "Roi"), summary(noa, "Noa")],
            workouts: try [
                workout(yoniWorkout, yoni, "2026-11-23"), workout(mayaWorkout, maya, "2026-11-23"),
                workout(roiWorkout, roi, "2026-11-23"), workout(UUID(), noa, "2026-11-23", type: "rest"),
            ],
            runs: runs, runsLoaded: runsLoaded, now: date, week: week, locale: Locale(identifier: "en_US")
        )
    }

    // MARK: Filter

    func testMissedTodayListsMissedAndPartialInScreenOrder() throws {
        let result = try snapshot().missedRows(for: CoachTodayFilter(dayISO: "2026-11-23"))
        XCTAssertFalse(result.yesterday)
        XCTAssertEqual(Set(result.rows.map(\.id)), [yoni, maya])
        XCTAssertEqual(CoachTodayFilterCopy.chip(yesterday: result.yesterday, count: result.rows.count), "Missed today · 2")
        let snapshot = try snapshot()
        let order = snapshot.rows.map(\.id).filter { [yoni, maya].contains($0) }
        XCTAssertEqual(result.rows.map(\.id), order)
    }

    func testOpenedAfterMidnightItIsYesterdaysList() throws {
        // The summary for the 23rd, held through quiet hours and tapped on the 24th at 07:10.
        let result = try snapshot(now: "2026-11-24T07:10:00Z").missedRows(for: CoachTodayFilter(dayISO: "2026-11-23"))
        XCTAssertTrue(result.yesterday)
        XCTAssertEqual(Set(result.rows.map(\.id)), [yoni, maya])
        XCTAssertEqual(CoachTodayFilterCopy.chip(yesterday: true, count: 2), "Missed yesterday · 2")
    }

    func testALateRunLeavesTheListAndAnEmptyListUsesTheSpecCopy() throws {
        let late = try snapshot(now: "2026-11-23T21:00:00Z", late: true)
        XCTAssertEqual(late.missedRows(for: CoachTodayFilter(dayISO: "2026-11-23")).rows.map(\.id), [maya])
        XCTAssertEqual(CoachTodayFilterCopy.emptied, "Everyone on the 20:00 list has logged a run since.")
        XCTAssertEqual(CoachTodayFilterCopy.showAll, "Show all")
    }

    func testNoDayOrAnUnknownDayMeansToday() throws {
        let snapshot = try snapshot()
        XCTAssertEqual(Set(snapshot.missedRows(for: CoachTodayFilter(dayISO: nil)).rows.map(\.id)), [yoni, maya])
        XCTAssertEqual(Set(snapshot.missedRows(for: CoachTodayFilter(dayISO: "2025-01-01")).rows.map(\.id)), [yoni, maya])
    }

    func testRunsNotLoadedNamesNobody() throws {
        XCTAssertTrue(try snapshot(runsLoaded: false).missedRows(for: CoachTodayFilter(dayISO: "2026-11-23")).rows.isEmpty)
    }

    // MARK: Tap routing

    func testEveningSummaryRoutesToTheFilteredToday() {
        let coach = RemotePushRouteContext(v2Enabled: true, isCoach: true, activeAthletes: nil)
        XCTAssertEqual(
            RemotePushRouter.route(RemotePushPayload(kind: .coachEveningSummary, day: "2026-11-23"), context: coach),
            RemotePushRoute(destination: .coachTodayMissed(dayISO: "2026-11-23"))
        )
        let parsed = RemotePushPayload(userInfo: ["rs": ["v": 1, "kind": "coachEveningSummary", "day": "2026-11-23"]])
        XCTAssertEqual(parsed, RemotePushPayload(kind: .coachEveningSummary, day: "2026-11-23"))
        // Flag off: home, no v2 screen.
        XCTAssertEqual(
            RemotePushRouter.route(RemotePushPayload(kind: .coachEveningSummary), context: RemotePushRouteContext(v2Enabled: false)),
            RemotePushRoute(destination: .today)
        )
    }

    func testAppRouterOpensTheCoachTabWithTheFilter() {
        let router = AppRouter(coachModeEnabled: true)
        router.pendingCoachDestination = CoachAthleteDestination(athleteID: yoni, name: "Yoni", focusDayISO: nil, coachV2: true)
        router.openRemotePush(.coachTodayMissed(dayISO: "2026-11-23"))
        XCTAssertEqual(router.selectedTab, .coach)
        XCTAssertNil(router.pendingCoachDestination)
        XCTAssertEqual(router.pendingCoachTodayFilter, CoachTodayFilter(dayISO: "2026-11-23"))

        let off = AppRouter(coachModeEnabled: false)
        off.openRemotePush(.coachTodayMissed(dayISO: "2026-11-23"))
        XCTAssertEqual(off.selectedTab, .today)
        XCTAssertNil(off.pendingCoachTodayFilter)
    }

    func testAnotherAccountStartsWithoutTheFilter() {
        let model = CoachAthleteListModel()
        model.reset(for: UUID())
        model.todayFilter = CoachTodayFilter(dayISO: "2026-11-23")
        model.reset(for: UUID())
        XCTAssertNil(model.todayFilter)
    }
}
