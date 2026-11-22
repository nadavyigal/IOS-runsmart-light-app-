import XCTest
@testable import IOS_RunSmart_app

// C7.1 Coach Today: day states, groups, chip priority, the 20:00 cutoff, week start, time zones and DST,
// the runs-RPC failure, the pending-update pill and the analytics events.

private final class StubRead: CoachReadServing, @unchecked Sendable {
    var athletes: [CoachAthleteSummary] = []
    var workoutResults: [CoachWorkoutSummary] = []
    var runResults: [CoachRunSummary] = []
    var runsError: Error?
    var listError: Error?
    private(set) var workoutWindows: [(from: Date, to: Date)] = []
    private(set) var runWindows: [(from: Date, to: Date)] = []

    func listAthletes() async throws -> [CoachAthleteSummary] {
        if let listError { throw listError }
        return athletes
    }

    func plan(for athleteID: UUID) async throws -> [CoachPlanSummary] { [] }

    func workouts(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachWorkoutSummary] {
        workoutWindows.append((from, to))
        return workoutResults
    }

    func runs(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachRunSummary] {
        runWindows.append((from, to))
        if let runsError { throw runsError }
        return runResults
    }

    func latestRun(for athleteID: UUID, through: Date) async throws -> CoachRunSummary? { nil }
}

private nonisolated final class EventSpy: AnalyticsTracking {
    private(set) var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}
}

@MainActor
final class CoachTodayTests: XCTestCase {
    private let athleteID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    private let en = Locale(identifier: "en_US")   // week starts Monday
    private let il = Locale(identifier: "he_IL")   // week starts Sunday (region IL)

    // MARK: Fixtures (same shape as CoachAthleteDetailTests)

    private func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func summary(_ id: UUID? = nil, name: String = "Yoni", plan: Bool = true) -> CoachAthleteSummary {
        CoachAthleteSummary(athleteID: id ?? athleteID, displayName: name, linkedAt: iso("2026-01-01T00:00:00Z"), hasActivePlan: plan)
    }

    private func workout(
        _ date: String, athlete: UUID? = nil, type: String = "easy", distance: Double = 10,
        minutes: Int? = 50, completed: Bool = false
    ) throws -> CoachWorkoutSummary {
        try workout(UUID(), date, athlete: athlete, type: type, distance: distance, minutes: minutes, completed: completed)
    }

    private func workout(
        _ id: UUID, _ date: String, athlete: UUID? = nil, type: String = "easy", distance: Double = 10,
        minutes: Int? = 50, completed: Bool = false
    ) throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(id)","athlete_id":"\(athlete ?? athleteID)","plan_id":"\(UUID())","scheduled_date":"\(date)",
        "type":"\(type)","planned_distance":\(distance),"planned_duration_minutes":\(minutes.map(String.init) ?? "null"),
        "completed":\(completed)}
        """.utf8))
    }

    private func run(
        _ id: Int, at stamp: String, linkedTo workout: UUID? = nil, athlete: UUID? = nil, distance: Double = 10
    ) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete ?? athleteID)","workout_id":\(workout.map { "\"\($0)\"" } ?? "null"),
        "completed_at":"\(stamp)","distance_km":\(distance),"duration_seconds":\(Int(distance * 340))}
        """.utf8))
    }

    private func snapshot(
        _ athletes: [CoachAthleteSummary]? = nil, workouts: [CoachWorkoutSummary], runs: [CoachRunSummary] = [],
        runsLoaded: Bool = true, now: String = "2026-11-18T12:00:00Z", locale: Locale? = nil,
        timeZone: TimeZone = .gmt
    ) -> CoachTodaySnapshot {
        let date = iso(now)
        let week = CoachAthleteWeek(now: date, locale: locale ?? en, timeZone: timeZone)
        return CoachTodaySnapshot.make(
            athletes: athletes ?? [summary()], workouts: workouts, runs: runs, runsLoaded: runsLoaded,
            now: date, week: week, locale: Locale(identifier: "en_US")
        )
    }

    private func states(_ snapshot: CoachTodaySnapshot, _ id: UUID? = nil) -> [CoachTodayDayState] {
        (snapshot.rows.first { $0.id == (id ?? athleteID) }?.days ?? []).map(\.state)
    }

    // MARK: AC2 glyphs: every state, and the 80% line

    func testEveryDayStateOverSevenDays() throws {
        let done = UUID(), partial = UUID(), missed = UUID(), planned = UUID(), done2 = UUID()
        // Wed 18 Nov, before 20:00. The 7 days are 12 Nov to 18 Nov.
        let workouts = try [
            workout(done, "2026-11-12"), workout(partial, "2026-11-13"), workout(missed, "2026-11-14"),
            workout(done2, "2026-11-17"), workout(planned, "2026-11-18"),
            workout("2026-11-15", type: "rest", distance: 0)
        ]
        let runs = try [
            run(1, at: "2026-11-12T07:00:00Z", linkedTo: done),
            run(2, at: "2026-11-13T07:00:00Z", linkedTo: partial, distance: 7.99),
            run(3, at: "2026-11-16T07:00:00Z"),
            run(4, at: "2026-11-17T07:00:00Z", linkedTo: done2)
        ]
        let result = snapshot(workouts: workouts, runs: runs)
        XCTAssertEqual(states(result), [.done, .partial, .missed, .rest, .extra, .done, .planned])
        XCTAssertEqual(result.rows[0].days.map(\.iso).first, "2026-11-12", "oldest at the leading edge")
        XCTAssertEqual(result.rows[0].days.map(\.iso).last, "2026-11-18", "today at the trailing edge")
    }

    func testEightyPercentLine() throws {
        let exact = UUID(), under = UUID()
        let workouts = try [workout(exact, "2026-11-16"), workout(under, "2026-11-17")]
        let runs = try [
            run(1, at: "2026-11-16T07:00:00Z", linkedTo: exact, distance: 8),
            run(2, at: "2026-11-17T07:00:00Z", linkedTo: under, distance: 7.9)
        ]
        let result = snapshot(workouts: workouts, runs: runs)
        XCTAssertEqual(states(result)[4], .done, "80% of the plan counts as done")
        XCTAssertEqual(states(result)[5], .partial, "below 80% is partial")
    }

    func testDurationPlansUseTheEightyPercentRuleToo() throws {
        let id = UUID()
        let timed = try workout(id, "2026-11-17", distance: 0, minutes: 40)
        let shortRun = try run(1, at: "2026-11-17T07:00:00Z", linkedTo: id, distance: 3)   // 3 km = 1020 s, 17 of 40 min
        XCTAssertEqual(states(snapshot(workouts: [timed], runs: [shortRun]))[5], .partial)
        let line = snapshot(workouts: [timed], runs: [shortRun]).rows[0]
        XCTAssertEqual(line.days[5].spoken, "Tuesday 17 November: Easy 40 minutes, partial 3 kilometres.")
    }

    // MARK: AC3 the 20:00 cutoff

    func testTodaysWorkoutIsNotMissedUntilTwentyHundred() throws {
        let today = try workout("2026-11-18")
        let before = snapshot(workouts: [today], now: "2026-11-18T19:59:00Z").rows[0]
        XCTAssertEqual(before.days.last?.state, .planned)
        XCTAssertTrue(before.todayLine.hasSuffix("Not done yet"), before.todayLine)
        XCTAssertNil(before.reason)
        XCTAssertEqual(before.group, .onTrack)

        let after = snapshot(workouts: [today], now: "2026-11-18T20:00:00Z").rows[0]
        XCTAssertEqual(after.days.last?.state, .missed)
        XCTAssertTrue(after.todayLine.contains("· Missed"), after.todayLine)
        XCTAssertEqual(after.reason, .missedToday)
        XCTAssertEqual(after.group, .missedToday)
    }

    func testYesterdaysMissShowsAsMissedYesterdayBeforeTheCutoff() throws {
        let yesterday = try workout("2026-11-17")
        let row = snapshot(workouts: [yesterday], now: "2026-11-18T12:00:00Z").rows[0]
        XCTAssertEqual(row.reason, .missedYesterday)
        XCTAssertEqual(row.group, .missedYesterday)
        XCTAssertEqual(row.focusDayISO, "2026-11-17")
        XCTAssertEqual(row.reason?.chip, "Missed yesterday")
    }

    func testAfterTheCutoffTheYesterdayGroupDissolves() throws {
        // One old miss, nothing today: after 20:00 the athlete is behind, not "missed yesterday".
        let yesterday = try workout("2026-11-17")
        let row = snapshot(workouts: [yesterday], now: "2026-11-18T20:30:00Z").rows[0]
        XCTAssertNotEqual(row.reason, .missedYesterday)
        XCTAssertEqual(row.group, .behind)
    }

    func testCutoffReadsTheCalendarsTimeZone() throws {
        // 19:30 in New York is 00:30 UTC the next day. The cutoff follows the calendar, not UTC.
        let today = try workout("2026-11-18")
        let ny = TimeZone(identifier: "America/New_York")!
        let early = snapshot(workouts: [today], now: "2026-11-19T00:30:00Z", timeZone: ny).rows[0]
        XCTAssertEqual(early.days.last?.state, .planned, "19:30 local is before the cutoff")
        let late = snapshot(workouts: [today], now: "2026-11-19T01:30:00Z", timeZone: ny).rows[0]
        XCTAssertEqual(late.days.last?.state, .missed, "20:30 local is after the cutoff")
    }

    // MARK: AC4 runs failed: unknown, never missed

    func testRunsFailureNeverMarksAnythingMissed() throws {
        let workouts = try [workout("2026-11-14"), workout("2026-11-17"), workout("2026-11-18")]
        let result = snapshot(workouts: workouts, runsLoaded: false, now: "2026-11-18T21:00:00Z")
        XCTAssertEqual(states(result), Array(repeating: .unknown, count: 7))
        XCTAssertFalse(result.rows[0].days.contains { $0.state == .missed })
        XCTAssertNil(result.rows[0].reason)
        XCTAssertEqual(result.rows[0].group, .athletes)
        XCTAssertEqual(result.needCount, 0)
        XCTAssertNil(result.summaryLine, "nobody is called caught up on guesswork")
        XCTAssertNil(result.caughtUpDetail)
        XCTAssertNil(result.rows[0].weekProgress)
        XCTAssertEqual(result.rows[0].days[0].spoken, "Thursday 12 November: unknown, runs didn't load.")
        XCTAssertTrue(result.rows[0].spokenSentence.contains("Last 7 days: unknown, runs didn't load."))
    }

    // MARK: Week start (G14)

    func testWeekStartFollowsTheRegionRule() throws {
        // Sunday 22 Nov, noon. US week: Mon 16 to Sun 22. IL week: Sun 22 to Sat 28.
        let monday = try workout(UUID(), "2026-11-16")
        let sunday = try workout(UUID(), "2026-11-22")
        let runs = [try run(1, at: "2026-11-16T07:00:00Z", linkedTo: monday.id)]
        let us = snapshot(workouts: [monday, sunday], runs: runs, now: "2026-11-22T12:00:00Z", locale: en).rows[0]
        XCTAssertEqual(us.weekProgress, "1 of 2 this week")
        let israel = snapshot(workouts: [monday, sunday], runs: runs, now: "2026-11-22T12:00:00Z", locale: il).rows[0]
        XCTAssertEqual(israel.weekProgress, "0 of 1 this week")
    }

    // MARK: Time zone and DST boundaries

    func testRunLateInTheEveningBelongsToTheLocalDay() throws {
        // 23:30 EST on 18 Nov is already 19 Nov in UTC. The athlete's day is still the 18th.
        let ny = TimeZone(identifier: "America/New_York")!
        let id = UUID()
        let result = snapshot(
            workouts: [try workout(id, "2026-11-18")],
            runs: [try run(1, at: "2026-11-18T23:30:00-05:00", linkedTo: id)],
            now: "2026-11-19T12:00:00-05:00", timeZone: ny
        )
        XCTAssertEqual(result.rows[0].days.first { $0.iso == "2026-11-18" }?.state, .done)
        XCTAssertEqual(result.rows[0].days.first { $0.iso == "2026-11-19" }?.state, .rest)
    }

    func testFallBackDaySevenDaysStayDistinctAndOrdered() throws {
        // New York leaves daylight time on Sun 1 Nov 2026: that day has 25 hours.
        let ny = TimeZone(identifier: "America/New_York")!
        let id = UUID()
        let result = snapshot(
            workouts: [try workout(id, "2026-11-01")],
            runs: [try run(1, at: "2026-11-01T23:30:00-05:00", linkedTo: id)],
            now: "2026-11-02T12:00:00-05:00", timeZone: ny
        )
        let isos = result.rows[0].days.map(\.iso)
        XCTAssertEqual(isos, ["2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"])
        XCTAssertEqual(result.rows[0].days[5].state, .done)
    }

    func testSpringForwardDayKeepsItsRun() throws {
        // New York enters daylight time on Sun 8 Mar 2026 (23 hours). A 01:30 EST run is on the 8th.
        let ny = TimeZone(identifier: "America/New_York")!
        let id = UUID()
        let result = snapshot(
            workouts: [try workout(id, "2026-03-08")],
            runs: [try run(1, at: "2026-03-08T01:30:00-05:00", linkedTo: id)],
            now: "2026-03-09T12:00:00-04:00", timeZone: ny
        )
        XCTAssertEqual(result.rows[0].days.map(\.iso).last, "2026-03-09")
        XCTAssertEqual(result.rows[0].days.first { $0.iso == "2026-03-08" }?.state, .done)
    }

    func testCutoffOnADstChangeDay() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let today = try workout("2026-11-01")
        // 19:59 EST and 20:00 EST on the 25-hour day.
        let before = snapshot(workouts: [today], now: "2026-11-01T19:59:00-05:00", timeZone: ny).rows[0]
        XCTAssertEqual(before.days.last?.state, .planned)
        let after = snapshot(workouts: [today], now: "2026-11-01T20:00:00-05:00", timeZone: ny).rows[0]
        XCTAssertEqual(after.days.last?.state, .missed)
    }

    func testJerusalemDstEndsOnTheLastSundayOfOctober() throws {
        let tz = TimeZone(identifier: "Asia/Jerusalem")!
        let result = snapshot(workouts: [], now: "2026-10-26T12:00:00+02:00", locale: il, timeZone: tz)
        let isos = result.rows[0].days.map(\.iso)
        XCTAssertEqual(isos.first, "2026-10-20")
        XCTAssertEqual(isos.last, "2026-10-26")
        XCTAssertEqual(Set(isos).count, 7)
    }

    // MARK: AC5 chip priority and the one-chip rule

    func testOneChipShowsTheMostUrgentReason() throws {
        // Missed today (after the cutoff) and behind (two misses this week).
        let workouts = try [workout("2026-11-16"), workout("2026-11-17"), workout("2026-11-18")]
        let row = snapshot(workouts: workouts, now: "2026-11-18T21:00:00Z").rows[0]
        XCTAssertEqual(row.reason, .missedToday)
        XCTAssertEqual(row.secondaryReason, .behind)
        XCTAssertEqual(row.group, .missedToday)
        XCTAssertTrue(row.todayLine.hasSuffix("Behind this week"), "the second reason is text in the second line")
        XCTAssertEqual(row.spokenSentence.components(separatedBy: "Behind this week").count, 1, "VoiceOver names one reason")
    }

    func testReasonPriorityOrder() {
        let order = CoachTodayReason.allCases.sorted { $0.priority < $1.priority }
        // C7.2 adds the four "new" reasons after the urgent ones (UX spec A.3 item 5).
        XCTAssertEqual(order, [.missedToday, .missedYesterday, .behind, .reply, .newRun, .changedGoal, .changedWorkout])
        XCTAssertEqual(CoachTodayReason.allCases.map(\.chip),
                       ["Missed today", "Missed yesterday", "Behind", "Reply", "New run", "Changed goal", "Changed your workout"])
    }

    func testBehindRuleTwoMissesOrBelowEightyPercent() throws {
        // Two misses earlier in the week: behind, even though nothing was missed yesterday.
        let twoMisses = try [workout("2026-11-16"), workout("2026-11-17"), workout("2026-11-18")]
        let a = snapshot(workouts: twoMisses, now: "2026-11-18T12:00:00Z").rows[0]
        XCTAssertEqual(a.reason, .missedYesterday, "yesterday's miss is more urgent than behind")
        XCTAssertEqual(a.secondaryReason, .behind)

        // Sunday: week to date is Mon to Sat. 5 due, 4 done, 1 missed on Tuesday = exactly 80%: not behind.
        func week(missingOne: Bool) throws -> CoachTodayRow {
            let ids = (0..<5).map { _ in UUID() }
            let days = ["2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20"]
            let workouts = try zip(ids, days).map { try workout($0, $1) }
            let runs = try zip(ids, days).enumerated().compactMap { index, pair -> CoachRunSummary? in
                missingOne && index == 1 ? nil : try run(index, at: "\(pair.1)T07:00:00Z", linkedTo: pair.0)
            }
            return snapshot(workouts: workouts, runs: runs, now: "2026-11-22T12:00:00Z").rows[0]
        }
        XCTAssertNil(try week(missingOne: true).reason, "4 of 5 is exactly 80%")
        XCTAssertEqual(try week(missingOne: true).group, .restToday)
        // 4 due, 3 done, 1 missed = 75%: behind.
        let ids = (0..<4).map { _ in UUID() }
        let days = ["2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19"]
        let workouts = try zip(ids, days).map { try workout($0, $1) }
        let runs = try zip(ids, days).enumerated().compactMap { index, pair -> CoachRunSummary? in
            index == 1 ? nil : try run(index, at: "\(pair.1)T07:00:00Z", linkedTo: pair.0)
        }
        XCTAssertEqual(snapshot(workouts: workouts, runs: runs, now: "2026-11-22T12:00:00Z").rows[0].reason, .behind)
    }

    func testPartialRunsCountAsPartialCreditInTheEightyPercentCheck() throws {
        let ids = (0..<2).map { _ in UUID() }
        let workouts = try [workout(ids[0], "2026-11-16"), workout(ids[1], "2026-11-17")]
        let runs = try [
            run(1, at: "2026-11-16T07:00:00Z", linkedTo: ids[0], distance: 10),
            run(2, at: "2026-11-17T07:00:00Z", linkedTo: ids[1], distance: 5)   // 50%: (1 + 0.5) / 2 = 75%
        ]
        let row = snapshot(workouts: workouts, runs: runs, now: "2026-11-18T12:00:00Z").rows[0]
        XCTAssertEqual(row.reason, .behind)
        XCTAssertEqual(row.days[4].state, .done)
        XCTAssertEqual(row.days[5].state, .partial)
    }

    // MARK: Groups, order, summary

    func testGroupsAndOrder() throws {
        let missing = UUID(), behind = UUID(), steady = UUID(), resting = UUID(), nothing = UUID(), second = UUID()
        let athletes = [
            summary(steady, name: "Steady"), summary(missing, name: "Zed"), summary(behind, name: "Behind"),
            summary(resting, name: "Rester"), summary(nothing, name: "Nada", plan: false), summary(second, name: "Avi")
        ]
        func plan(_ athlete: UUID, _ days: [String]) throws -> [CoachWorkoutSummary] {
            try days.map { try workout(UUID(), $0, athlete: athlete) }
        }
        var workouts: [CoachWorkoutSummary] = []
        workouts += try plan(missing, ["2026-11-17"])                  // missed yesterday
        workouts += try plan(second, ["2026-11-17", "2026-11-16"])    // missed yesterday, two misses
        workouts += try plan(behind, ["2026-11-16", "2026-11-17"])     // 2 misses, but yesterday...
        workouts += try plan(steady, ["2026-11-18"])                   // planned today
        let result = snapshot(athletes, workouts: workouts, now: "2026-11-18T12:00:00Z")
        let groups = result.groups
        XCTAssertEqual(groups, [.missedYesterday, .onTrack, .restToday, .noPlan])
        // Two misses ahead of one; then the oldest miss; then name.
        XCTAssertEqual(result.rows(in: .missedYesterday).map(\.name), ["Avi", "Behind", "Zed"])
        XCTAssertEqual(result.rows(in: .noPlan).first?.todayLine, "Waiting for a plan")
        XCTAssertEqual(result.needCount, 3)
        XCTAssertEqual(result.summaryLine, "3 athletes need you")
        XCTAssertEqual(CoachTodayGroup.missedYesterday.title(count: 3), "Missed yesterday (3)")
    }

    func testOrderIgnoresTheServersRowOrderOnTies() throws {
        let a = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!
        let one = snapshot([summary(a, name: "Same"), summary(b, name: "Same")], workouts: [])
        let two = snapshot([summary(b, name: "Same"), summary(a, name: "Same")], workouts: [])
        XCTAssertEqual(one.rows.map(\.id), two.rows.map(\.id))
    }

    func testSummaryLinesAndEmptyStates() throws {
        XCTAssertEqual(snapshot([], workouts: []).summaryLine, "No athletes yet")
        XCTAssertEqual(snapshot([summary(plan: false)], workouts: []).summaryLine, "Nobody has a plan yet")
        let one = try snapshot(workouts: [workout("2026-11-17")], now: "2026-11-18T12:00:00Z")
        XCTAssertEqual(one.summaryLine, "1 athlete needs you")
        let tidy = try snapshot(
            [summary(name: "A"), summary(UUID(), name: "B")],
            workouts: [workout("2026-11-18", athlete: athleteID)], now: "2026-11-18T12:00:00Z"
        )
        XCTAssertEqual(tidy.summaryLine, "You're caught up for today")
        XCTAssertEqual(tidy.caughtUpDetail, "1 on track · 1 rest day")
    }

    func testNoPlanRowsAndNoEmptyHeadersForLaterStories() throws {
        let result = snapshot([summary(plan: false)], workouts: [])
        XCTAssertEqual(result.groups, [.noPlan])
        XCTAssertNil(result.rows[0].weekProgress)
        XCTAssertEqual(result.rows[0].spokenSentence, "Yoni. Waiting for a plan.")
        // C7.4 pain and C7.16 milestones: no group exists yet. C7.2 added "New to review", which has no
        // header without news (CoachSeenStateTests).
        XCTAssertEqual(CoachTodayGroup.allCases.count, 8)
        XCTAssertFalse(CoachTodayGroup.allCases.contains { $0.title(count: 1).contains("Pain") })
    }

    func testThirtyAthletesFillTheGroupsAndCollapseAtEight() {
        let result = CoachTodaySnapshot.previewFixture(athletes: 30)
        XCTAssertEqual(result.athleteCount, 30)
        XCTAssertEqual(coachTodayGroupLimit, 8)
        XCTAssertTrue(result.groups.contains { result.rows(in: $0).count > coachTodayGroupLimit },
                      "the fixture has a group big enough to collapse")
        XCTAssertEqual(Set(result.rows.map(\.id)).count, 30)
    }

    // MARK: AC8 VoiceOver sentences

    func testRowSentenceMatchesTheSpecShape() throws {
        // Yoni: 4 done, 1 partial, 0 missed, 1 rest, today a tempo run not done yet.
        let ids = (0..<6).map { _ in UUID() }
        let days = ["2026-11-12", "2026-11-13", "2026-11-14", "2026-11-16", "2026-11-17", "2026-11-18"]
        let types = ["easy", "easy", "easy", "easy", "easy", "tempo"]
        let workouts = try (0..<6).map { try workout(ids[$0], days[$0], type: types[$0], distance: $0 == 5 ? 6 : 10) }
        let runs = try [
            run(1, at: "2026-11-12T07:00:00Z", linkedTo: ids[0]), run(2, at: "2026-11-13T07:00:00Z", linkedTo: ids[1]),
            run(3, at: "2026-11-14T07:00:00Z", linkedTo: ids[2]), run(4, at: "2026-11-16T07:00:00Z", linkedTo: ids[3]),
            run(5, at: "2026-11-17T07:00:00Z", linkedTo: ids[4], distance: 7.9)
        ]
        let row = snapshot(workouts: workouts, runs: runs).rows[0]
        XCTAssertEqual(
            row.spokenSentence,
            "Yoni. Today: Tempo 6 km, not done yet. Last 7 days: 4 done, 1 partial, 0 missed, 1 rest."
        )
        XCTAssertEqual(row.daysSummaryText, "4 done · 1 partial · 1 rest · 1 to do")
    }

    func testDaySentenceForTheAdjustableStrip() throws {
        let id = UUID()
        let result = snapshot(
            workouts: [try workout(id, "2026-11-15", type: "long", distance: 10)],
            runs: [try run(1, at: "2026-11-15T07:00:00Z", linkedTo: id, distance: 10.4)]
        )
        XCTAssertEqual(
            result.rows[0].days.first { $0.iso == "2026-11-15" }?.spoken,
            "Sunday 15 November: Long run 10 kilometres, done 10.4 kilometres."
        )
        XCTAssertEqual(result.rows[0].days.first { $0.iso == "2026-11-13" }?.spoken, "Friday 13 November: rest day.")
    }

    func testStatusStringsFromTheSpec() throws {
        let id = UUID()
        let planned = try workout(id, "2026-11-18", type: "tempo", distance: 6)
        let done = snapshot(
            workouts: [planned], runs: [try run(1, at: "2026-11-18T07:00:00Z", linkedTo: id, distance: 6.2)]
        ).rows[0]
        XCTAssertTrue(done.todayLine.contains("Done "), done.todayLine)
        XCTAssertTrue(done.todayLine.contains("6.2 km"), done.todayLine)
        let partial = snapshot(
            workouts: [planned], runs: [try run(1, at: "2026-11-18T07:00:00Z", linkedTo: id, distance: 4)]
        ).rows[0]
        XCTAssertTrue(partial.todayLine.contains("Partial "), partial.todayLine)
        XCTAssertTrue(partial.todayLine.contains("4 of 6 km"), partial.todayLine)
        let extra = snapshot(workouts: [], runs: [try run(2, at: "2026-11-18T07:00:00Z", distance: 5)]).rows[0]
        XCTAssertTrue(extra.todayLine.hasPrefix("Extra run "), extra.todayLine)
        XCTAssertEqual(snapshot(workouts: []).rows[0].todayLine, "Rest")
    }

    func testGlyphsAreDistinctShapesWithLabels() {
        let glyphs = CoachTodayDayState.allCases.map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "color is never the only signal")
        XCTAssertEqual(CoachTodayDayState.allCases.map(\.label),
                       ["Done", "Partial", "Missed", "Rest", "Not done yet", "Extra run", "Unknown"])
    }

    // MARK: AC7/AC5 model: window, failure, pending pill, flag off

    private func model(_ service: StubRead, tracker: EventSpy? = nil) -> CoachAthleteListModel {
        let seen = CoachSeenStub()
        let outbox = CoachV2Outbox(
            defaults: UserDefaults(suiteName: "CoachTodayTests-\(UUID().uuidString)")!, repository: seen
        )
        return CoachAthleteListModel(service: service, rosterStatus: { [:] }, tracker: tracker, seen: seen, outbox: outbox)
    }

    private func stubWithAthlete() -> StubRead {
        let stub = StubRead()
        stub.athletes = [summary()]
        return stub
    }

    func testFlagOffKeepsThe126WindowAndMakesNoToday() async {
        let stub = stubWithAthlete()
        let list = model(stub)
        let now = Date()
        await list.refresh(owner: athleteID, now: now)
        XCTAssertNil(list.today)
        XCTAssertEqual(stub.workoutWindows.first?.from, CoachAthleteWeek(now: now).interval.start)
        await list.applyCoachV2(.paused)
        await list.refresh(owner: athleteID, now: now)
        XCTAssertNil(list.today)
        XCTAssertEqual(stub.workoutWindows.last?.from, CoachAthleteWeek(now: now).interval.start)
    }

    func testFlagOnReadsTheSevenDayWindowWithTheExistingRPCs() async {
        let stub = stubWithAthlete()
        let list = model(stub)
        await list.applyCoachV2(.on)
        let now = Date()
        await list.refresh(owner: athleteID, now: now)
        XCTAssertNotNil(list.today)
        let week = CoachAthleteWeek(now: now)
        let sixDaysBack = week.calendar.date(byAdding: .day, value: -6, to: week.calendar.startOfDay(for: now))!
        XCTAssertEqual(stub.workoutWindows.last?.from, min(week.interval.start, sixDaysBack))
        XCTAssertEqual(stub.runWindows.last?.from, min(week.interval.start, sixDaysBack))
        XCTAssertEqual(stub.runWindows.count, 1, "one runs call per refresh, no new RPC")
    }

    func testTurningV2OnAfterTheRosterLoadedReloadsWithTheNewWindow() async {
        let stub = stubWithAthlete()
        let list = model(stub)
        await list.refresh(owner: athleteID)
        XCTAssertNil(list.today)
        await list.applyCoachV2(.on)
        XCTAssertNotNil(list.today)
        await list.applyCoachV2(.off)
        XCTAssertNil(list.today, "kill switch or flag off drops Today at once")
    }

    func testRunsFailureAloneKeepsTodayAndShowsUnknown() async {
        let stub = stubWithAthlete()
        stub.workoutResults = [try! workout("2026-11-01")]
        stub.runsError = URLError(.timedOut)
        let list = model(stub)
        await list.applyCoachV2(.on)
        await list.refresh(owner: athleteID)
        XCTAssertFalse(list.failure, "a failed runs call alone is a partial state, not an error")
        XCTAssertEqual(list.today?.runsLoaded, false)
        XCTAssertEqual(list.today?.rows.first?.days.map(\.state), Array(repeating: .unknown, count: 7))
        XCTAssertTrue(list.rows.isEmpty, "the roster does not call anyone behind without runs")
    }

    func testRunsFailureStillFailsThe126Roster() async {
        let stub = stubWithAthlete()
        stub.runsError = URLError(.timedOut)
        let list = model(stub)
        await list.refresh(owner: athleteID)
        XCTAssertTrue(list.failure)
        XCTAssertNil(list.today)
    }

    func testQuietRefreshHoldsMovingRowsBehindThePill() async {
        let stub = stubWithAthlete()
        let list = model(stub)
        await list.applyCoachV2(.on)
        await list.refresh(owner: athleteID)
        let shown = list.today
        XCTAssertFalse(list.hasPendingUpdate)

        // Same data: nothing moves, no pill.
        await list.refresh(owner: athleteID, style: .quiet)
        XCTAssertFalse(list.hasPendingUpdate)

        // A new athlete arrives in the background: the screen keeps its rows, the pill appears.
        stub.athletes.append(summary(UUID(), name: "Noa"))
        await list.refresh(owner: athleteID, style: .quiet)
        XCTAssertTrue(list.hasPendingUpdate)
        XCTAssertEqual(list.today?.rows.map(\.id), shown?.rows.map(\.id), "no re-sort while visible")

        list.applyPendingUpdate()
        XCTAssertFalse(list.hasPendingUpdate)
        XCTAssertEqual(list.today?.athleteCount, 2)
    }

    func testPullToRefreshShowsNewDataAtOnce() async {
        let stub = stubWithAthlete()
        let list = model(stub)
        await list.applyCoachV2(.on)
        await list.refresh(owner: athleteID)
        stub.athletes.append(summary(UUID(), name: "Noa"))
        await list.refresh(owner: athleteID)
        XCTAssertEqual(list.today?.athleteCount, 2)
        XCTAssertFalse(list.hasPendingUpdate)
    }

    func testQuietRefreshFailureDoesNotBreakTheScreen() async {
        struct Down: Error {}
        let stub = stubWithAthlete()
        let list = model(stub)
        await list.applyCoachV2(.on)
        await list.refresh(owner: athleteID)
        stub.listError = Down()
        await list.refresh(owner: athleteID, style: .quiet)
        XCTAssertFalse(list.failure)
        XCTAssertNotNil(list.today, "the last good screen stays")
        await list.refresh(owner: athleteID)
        XCTAssertTrue(list.failure, "a pull to refresh does show the error")
        XCTAssertNotNil(list.today, "with the cached list under the banner")
    }

    func testZeroAthletesStillGetsATodaySnapshot() async {
        let stub = StubRead()
        let list = model(stub)
        await list.applyCoachV2(.on)
        await list.refresh(owner: athleteID)
        XCTAssertEqual(list.today?.summaryLine, "No athletes yet")
    }

    // MARK: Analytics (v1.3 section 3.8)

    func testTodayViewedFiresOncePerVisitWithCountsOnly() async {
        let stub = stubWithAthlete()
        stub.workoutResults = [try! workout("2026-11-01")]
        let spy = EventSpy()
        let list = model(stub, tracker: spy)
        await list.applyCoachV2(.on)
        list.trackTodayViewed()
        XCTAssertTrue(spy.events.isEmpty, "nothing to view before data loads")
        await list.refresh(owner: athleteID)
        list.trackTodayViewed()
        list.trackTodayViewed()
        XCTAssertEqual(spy.events.count, 1)
        XCTAssertEqual(spy.events[0].name, "coach_today_viewed")
        XCTAssertEqual(spy.events[0].properties["athlete_count"] as? Int, 1)
        XCTAssertEqual(spy.events[0].properties["need_count"] as? Int, list.today?.needCount)
        XCTAssertEqual(Set(spy.events[0].properties.keys), ["athlete_count", "need_count"])
        list.todayDidDisappear()
        list.trackTodayViewed()
        XCTAssertEqual(spy.events.count, 2, "a new visit is a new view")
    }

    func testRowOpenedCarriesOnlyTheReasonEnum() async throws {
        let spy = EventSpy()
        let stub = stubWithAthlete()
        let list = model(stub, tracker: spy)
        await list.applyCoachV2(.on)
        await list.refresh(owner: athleteID)
        let row = try XCTUnwrap(list.today?.rows.first)
        list.trackRowOpened(row)
        XCTAssertEqual(spy.events.last?.name, "coach_today_row_opened")
        XCTAssertEqual(spy.events.last?.properties["reason"] as? String, "none")
        XCTAssertEqual(spy.events.last?.properties.count, 1, "no id, name or workout detail")
    }

    func testEventPropertiesAreIdsEnumsAndCountsUnderSixtyFourCharacters() {
        let events: [CoachV2Analytics.Event] = [.coachTodayViewed(athleteCount: 30, needCount: 4)]
            + CoachTodayReason.allCases.map { .coachTodayRowOpened(reason: $0.rawValue) }
            + [.coachTodayRowOpened(reason: "none")]
        for event in events {
            XCTAssertFalse(event.properties.isEmpty)
            for (key, value) in event.properties {
                XCTAssertLessThanOrEqual(key.count, 64)
                switch value.raw {
                case let text as String: XCTAssertLessThanOrEqual(text.count, 64, "\(event.name).\(key)")
                case is Int, is Bool: break
                default: XCTFail("\(event.name).\(key) is not an id, enum, count or duration")
                }
            }
        }
    }

    func testFlagOffSendsNoV2Events() async {
        let spy = EventSpy()
        let stub = stubWithAthlete()
        let list = model(stub, tracker: spy)
        await list.refresh(owner: athleteID)
        list.trackTodayViewed()
        await list.applyCoachV2(.paused)
        list.trackTodayViewed()
        if let row = CoachTodaySnapshot.previewFixture(athletes: 3).rows.first { list.trackRowOpened(row) }
        XCTAssertTrue(spy.events.isEmpty)
    }
}
