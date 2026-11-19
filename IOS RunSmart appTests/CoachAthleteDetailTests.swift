import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachAthleteDetailTests: XCTestCase {
    private let athlete = UUID()
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!
    private lazy var week = CoachAthleteWeek(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)

    private func workout(
        _ id: UUID = UUID(), date: String, type: String = "easy", distance: Double = 10,
        minutes: Int? = 50, pace: Int? = 343, completed: Bool = false
    ) throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(id)","athlete_id":"\(athlete)","plan_id":"\(UUID())","scheduled_date":"\(date)",
        "type":"\(type)","planned_distance":\(distance),"planned_duration_minutes":\(minutes.map(String.init) ?? "null"),
        "target_pace":\(pace.map(String.init) ?? "null"),"completed":\(completed)}
        """.utf8))
    }

    private func run(
        _ id: Int, on day: String, linkedTo workout: UUID? = nil, distance: Double = 10,
        seconds: Int = 3430, heartRate: Int? = 150
    ) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":\(workout.map { "\"\($0)\"" } ?? "null"),
        "completed_at":"\(day)T07:00:00Z","distance_km":\(distance),"duration_seconds":\(seconds),
        "average_heart_rate":\(heartRate.map(String.init) ?? "null")}
        """.utf8))
    }

    private func day(_ iso: String, in result: (current: CoachAthleteWeekDays, previous: CoachAthleteWeekDays)) -> CoachDay? {
        (result.current.days + result.previous.days).first { $0.iso == iso }
    }

    func testMarkersForEveryState() throws {
        let done = UUID(), partial = UUID(), missed = UUID(), planned = UUID()
        let workouts = try [
            workout(done, date: "2026-11-16"), workout(partial, date: "2026-11-17"),
            workout(missed, date: "2026-11-11"), workout(planned, date: "2026-11-20"),
            workout(date: "2026-11-19", type: "rest", distance: 0)
        ]
        let runs = try [
            run(1, on: "2026-11-16", linkedTo: done), run(2, on: "2026-11-17", linkedTo: partial, distance: 7.99),
            run(3, on: "2026-11-15")
        ]
        let result = CoachAthleteDays.weeks(workouts: workouts, runs: runs, now: now, week: week)
        XCTAssertEqual(day("2026-11-16", in: result)?.marker, .done)
        XCTAssertEqual(day("2026-11-17", in: result)?.marker, .partial)
        XCTAssertEqual(day("2026-11-11", in: result)?.marker, .missed)
        XCTAssertEqual(day("2026-11-20", in: result)?.marker, .planned)
        XCTAssertEqual(day("2026-11-15", in: result)?.marker, .extra)
        XCTAssertEqual(day("2026-11-19", in: result)?.marker, .rest, "a rest row is a rest day, not a workout")
        XCTAssertEqual(day("2026-11-18", in: result)?.marker, .rest)
    }

    func testMatchedByDateOnlyForCompletedUnlinkedWorkouts() throws {
        let legacy = UUID(), linked = UUID()
        let workouts = try [
            workout(legacy, date: "2026-11-16", completed: true),
            workout(linked, date: "2026-11-17", completed: true),
            workout(date: "2026-11-12", completed: false)
        ]
        let runs = try [
            run(1, on: "2026-11-16"), run(2, on: "2026-11-17", linkedTo: linked),
            run(3, on: "2026-11-17"), run(4, on: "2026-11-12")
        ]
        let result = CoachAthleteDays.weeks(workouts: workouts, runs: runs, now: now, week: week)
        let monday = try XCTUnwrap(day("2026-11-16", in: result))
        XCTAssertTrue(monday.workouts[0].matchedByDate)
        XCTAssertEqual(monday.workouts[0].run?.id, 1)
        XCTAssertEqual(monday.marker, .done)
        XCTAssertTrue(monday.extraRuns.isEmpty)

        let tuesday = try XCTUnwrap(day("2026-11-17", in: result))
        XCTAssertFalse(tuesday.workouts[0].matchedByDate, "a workout another run links to is not matched by date")
        XCTAssertEqual(tuesday.extraRuns.map(\.id), [3])

        let lastThursday = try XCTUnwrap(day("2026-11-12", in: result))
        XCTAssertEqual(lastThursday.marker, .missed, "not completed, so the same-day run stays extra")
        XCTAssertEqual(lastThursday.extraRuns.map(\.id), [4])
    }

    func testWeekOrderFollowsLocaleAndPreviousWeekIsTheSevenDaysBefore() {
        let israel = CoachAthleteWeek(now: now, locale: Locale(identifier: "he_IL"), timeZone: .gmt)
        let sunday = CoachAthleteDays.weeks(workouts: [], runs: [], now: now, week: israel)
        XCTAssertEqual(sunday.current.days.map(\.iso).first, "2026-11-15")
        XCTAssertEqual(sunday.previous.days.map(\.iso).first, "2026-11-08")

        let monday = CoachAthleteDays.weeks(workouts: [], runs: [], now: now, week: week)
        XCTAssertEqual(monday.current.days.map(\.iso), (16...22).map { "2026-11-\($0)" })
        XCTAssertEqual(monday.previous.days.map(\.iso), ["2026-11-09"] + (10...15).map { "2026-11-\($0)" })
    }

    func testFormattingAndSpokenSentence() throws {
        func plain(_ text: String?) -> String? {
            text?.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        }
        XCTAssertEqual(plain(CoachMetricFormat.pace(secondsPerKm: 343)), "5:43 /km")
        XCTAssertEqual(plain(CoachMetricFormat.duration(seconds: 3725)), "1:02:05")
        XCTAssertEqual(plain(CoachMetricFormat.duration(seconds: 2900)), "48:20")
        XCTAssertEqual(plain(CoachMetricFormat.distanceDifference(planned: 8, actual: 5)), "−3.0 km")
        XCTAssertEqual(plain(CoachMetricFormat.distanceDifference(planned: 5, actual: 5.4)), "+0.4 km")
        XCTAssertNil(CoachMetricFormat.distanceDifference(planned: 5, actual: 5.01))
        XCTAssertEqual(plain(CoachMetricFormat.durationDifference(plannedMinutes: 50, actualSeconds: 2700)), "−5 min")
        XCTAssertEqual(CoachMetricFormat.paceSeconds(for: try run(1, on: "2026-11-16", distance: 10, seconds: 3430)), 343)
        XCTAssertTrue(CoachMetricFormat.distance(5).hasPrefix("\u{2068}"))

        let tempo = UUID()
        let result = CoachAthleteDays.weeks(
            workouts: [try workout(tempo, date: "2026-11-17", type: "tempo", distance: 5)],
            runs: [try run(1, on: "2026-11-17", linkedTo: tempo, distance: 3.9), try run(2, on: "2026-11-15", distance: 3)],
            now: now, week: week
        )
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(
            CoachMetricFormat.spokenDay(try XCTUnwrap(day("2026-11-17", in: result)), calendar: week.calendar, locale: locale),
            "Tuesday 17 November, tempo run, planned 5 kilometres, completed 3.9 kilometres, partial."
        )
        XCTAssertEqual(
            CoachMetricFormat.spokenDay(try XCTUnwrap(day("2026-11-15", in: result)), calendar: week.calendar, locale: locale),
            "Sunday 15 November, extra run, 3 kilometres."
        )
    }

    func testRevokedNoPlanAndNoRunsStates() async throws {
        let revoked = CoachAthleteDetailModel(athleteID: athlete, service: MockCoachReadService())
        await revoked.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        XCTAssertTrue(revoked.revoked)
        XCTAssertNil(revoked.current)

        var service = MockCoachReadService()
        service.athletes = [CoachAthleteSummary(athleteID: athlete, displayName: "Yoni", linkedAt: now, hasActivePlan: false)]
        let noPlan = CoachAthleteDetailModel(athleteID: athlete, service: service)
        await noPlan.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        XCTAssertFalse(noPlan.revoked)
        XCTAssertFalse(noPlan.hasPlan)

        service.athletes = [CoachAthleteSummary(athleteID: athlete, displayName: "Yoni", linkedAt: now, hasActivePlan: true)]
        service.workoutResults = [try workout(date: "2026-11-20")]
        let noRuns = CoachAthleteDetailModel(athleteID: athlete, service: service)
        await noRuns.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        XCTAssertTrue(noRuns.hasPlan)
        XCTAssertFalse(noRuns.hasRuns)
        XCTAssertEqual(noRuns.current?.days.first { $0.iso == "2026-11-20" }?.marker, .planned)

        service.runResults = [try run(9, on: "2026-11-16")]
        let withRuns = CoachAthleteDetailModel(athleteID: athlete, service: service)
        await withRuns.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        XCTAssertTrue(withRuns.hasRuns)
    }

    func testRunsStayVisibleWhenTheAthleteHasNoPlan() async throws {
        var service = MockCoachReadService()
        service.athletes = [CoachAthleteSummary(athleteID: athlete, displayName: "Yoni", linkedAt: now, hasActivePlan: false)]
        let empty = CoachAthleteDetailModel(athleteID: athlete, service: service)
        await empty.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        XCTAssertFalse(empty.hasPlan)
        XCTAssertFalse(empty.showsWeeks, "no plan and no runs: only the notice")

        service.runResults = [try run(9, on: "2026-11-16"), try run(10, on: "2026-11-10")]
        let model = CoachAthleteDetailModel(athleteID: athlete, service: service)
        await model.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        XCTAssertFalse(model.hasPlan)
        XCTAssertTrue(model.showsWeeks, "recorded runs are not hidden behind No plan yet")
        XCTAssertEqual(model.current?.days.first { $0.iso == "2026-11-16" }?.marker, .extra)
        XCTAssertEqual(model.previous?.days.first { $0.iso == "2026-11-10" }?.extraRuns.map(\.id), [10])
    }

    func testRunLinkedToAHiddenWorkoutIsExtraAndNeverMatchedByDate() throws {
        let rest = UUID(), completed = UUID()
        let workouts = try [
            workout(rest, date: "2026-11-16", type: "rest", distance: 0),
            workout(completed, date: "2026-11-16", completed: true)
        ]
        let result = CoachAthleteDays.weeks(
            workouts: workouts, runs: [try run(1, on: "2026-11-16", linkedTo: rest)], now: now, week: week
        )
        let monday = try XCTUnwrap(day("2026-11-16", in: result))
        XCTAssertEqual(monday.extraRuns.map(\.id), [1])
        XCTAssertFalse(monday.workouts[0].matchedByDate)
        XCTAssertNil(monday.workouts[0].run)
    }

    func testOverlappingLoadsBothFinishWithData() async throws {
        var service = MockCoachReadService()
        service.athletes = [CoachAthleteSummary(athleteID: athlete, displayName: "Yoni", linkedAt: now, hasActivePlan: true)]
        let model = CoachAthleteDetailModel(athleteID: athlete, service: service)
        async let first: Void = model.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        async let second: Void = model.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        _ = await (first, second)
        XCTAssertNotNil(model.current)
        XCTAssertNotNil(model.updatedAt)
    }
}
