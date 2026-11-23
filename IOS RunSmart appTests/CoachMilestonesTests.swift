import XCTest
@testable import IOS_RunSmart_app

// C7.16 beginner milestones and one-tap praise: the rules (first run, first full week, longest run,
// Quiet 3 days), their edge cases, the Today tags and group, and the reaction (idempotent, flag-off,
// analytics, fallback to the week).

private final class MilestoneReadStub: CoachReadServing, @unchecked Sendable {
    var athletes: [CoachAthleteSummary] = []
    var recentWorkouts: [CoachWorkoutSummary] = []
    var oldWorkouts: [CoachWorkoutSummary] = []
    var runResults: [CoachRunSummary] = []
    var historyError: Error?
    private(set) var historyCalls = 0

    func listAthletes() async throws -> [CoachAthleteSummary] { athletes }
    func plan(for athleteID: UUID) async throws -> [CoachPlanSummary] { [] }

    func workouts(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachWorkoutSummary] {
        // The wide history read starts in 2000; the Today window starts within the last two weeks.
        if from.timeIntervalSince1970 < 1_000_000_000 {
            historyCalls += 1
            if let historyError { throw historyError }
            return oldWorkouts
        }
        return recentWorkouts
    }

    func runs(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachRunSummary] { runResults }
    func latestRun(for athleteID: UUID, through: Date) async throws -> CoachRunSummary? { nil }
}

private final class ReactionReaderStub: CoachMilestoneReactionReading, @unchecked Sendable {
    var targets: [UUID: Set<String>] = [:]
    var error: Error?
    func feedbackTargets(athleteIDs: [UUID]) async throws -> [UUID: Set<String>] {
        if let error { throw error }
        return targets
    }
}

private nonisolated final class MilestoneEventSpy: AnalyticsTracking {
    private(set) var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}
}

@MainActor
final class CoachMilestonesTests: XCTestCase {
    private let noa = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    private let avi = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!
    private let coach = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000001")!
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func defaults() -> UserDefaults {
        let name = "CoachMilestonesTests-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    // MARK: Fixtures. Wed 18 Nov 2026, 12:00 UTC, weeks start on Monday.

    private func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { iso("2026-11-18T12:00:00Z") }
    private func week(_ date: Date? = nil, zone: TimeZone = .gmt) -> CoachAthleteWeek {
        CoachAthleteWeek(now: date ?? now, locale: Locale(identifier: "en_US"), timeZone: zone)
    }

    private func athlete(_ id: UUID? = nil, linked: String = "2026-01-01T00:00:00Z", plan: Bool = true) -> CoachAthleteSummary {
        CoachAthleteSummary(athleteID: id ?? noa, displayName: "Noa", linkedAt: iso(linked), hasActivePlan: plan)
    }

    /// A planned workout. `done` gives a completion time and an actual distance.
    private func workout(
        _ date: String, id: UUID = UUID(), athlete: UUID? = nil, type: String = "easy", doneAt: String? = nil,
        km: Double? = nil
    ) throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(id)","athlete_id":"\(athlete ?? noa)","plan_id":"00000000-0000-4000-8000-0000000000aa",
        "scheduled_date":"\(date)","type":"\(type)","planned_distance":5,"planned_duration_minutes":30,
        "completed":\(doneAt != nil),"completed_at":\(doneAt.map { "\"\($0)\"" } ?? "null"),
        "actual_distance_km":\(km.map { String($0) } ?? "null")}
        """.utf8))
    }

    private func run(_ id: Int, workout: UUID, athlete: UUID? = nil, at stamp: String = "2026-11-17T07:00:00Z") throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete ?? noa)","workout_id":"\(workout)","completed_at":"\(stamp)",
        "distance_km":5,"duration_seconds":1700}
        """.utf8))
    }

    private func kinds(
        _ workouts: [CoachWorkoutSummary], athletes: [CoachAthleteSummary]? = nil, runs: [CoachRunSummary] = [],
        at date: Date? = nil, zone: TimeZone = .gmt, for id: UUID? = nil
    ) -> [CoachMilestoneKind] {
        let moment = date ?? now
        let result = CoachMilestoneRules.milestones(
            athletes: athletes ?? [athlete()], workouts: workouts, runs: runs, now: moment, week: week(moment, zone: zone)
        )
        return (result[id ?? noa] ?? []).map(\.kind)
    }

    // MARK: First run

    func testFirstCompletedRunIsAMilestoneWhileRecent() throws {
        let id = UUID()
        let workouts = [try workout("2026-11-17", id: id, doneAt: "2026-11-17T07:00:00Z", km: 3), try workout("2026-11-19")]
        let result = CoachMilestoneRules.milestones(
            athletes: [athlete()], workouts: workouts, runs: [try run(901, workout: id)], now: now, week: week()
        )
        let first = try XCTUnwrap(result[noa]?.first)
        XCTAssertEqual(first.kind, .firstRun)
        XCTAssertEqual(first.target, .run(901), "the note goes on the run that did the workout")
        XCTAssertEqual(first.fallbackTarget, .week("2026-11-16"))
        XCTAssertEqual(first.kind.tag, "First run")
    }

    func testFirstRunFallsBackToTheWeekWhenTheRunIsDeleted() throws {
        // The workout is done, but its run is gone from the runs read.
        let id = UUID()
        let workouts = [try workout("2026-11-17", id: id, doneAt: "2026-11-17T07:00:00Z", km: 3)]
        let result = CoachMilestoneRules.milestones(athletes: [athlete()], workouts: workouts, runs: [], now: now, week: week())
        XCTAssertEqual(result[noa]?.first?.kind, .firstRun, "a deleted run does not remove the milestone")
        XCTAssertEqual(result[noa]?.first?.target, .week("2026-11-16"))
    }

    func testFirstRunExpiresAfterSevenDays() throws {
        let old = [try workout("2026-11-10", doneAt: "2026-11-10T07:00:00Z", km: 3)]
        XCTAssertEqual(kinds(old), [], "8 days ago is out of the window")
        let inside = [try workout("2026-11-12", doneAt: "2026-11-12T07:00:00Z", km: 3)]
        XCTAssertEqual(kinds(inside), [.firstRun], "7 days including today is in")
    }

    func testOnlyTheEarliestCompletedWorkoutIsTheFirstRun() throws {
        let workouts = [
            try workout("2026-11-02", doneAt: "2026-11-02T07:00:00Z", km: 3),
            try workout("2026-11-17", doneAt: "2026-11-17T07:00:00Z", km: 4)
        ]
        XCTAssertEqual(kinds(workouts), [], "the first run was weeks ago; the new one is not a first")
    }

    func testNoWorkoutsOrNoPlanGiveNothingAndDoNotCrash() throws {
        XCTAssertEqual(kinds([], athletes: [athlete(plan: false)]), [])
        XCTAssertEqual(kinds([], athletes: []), [])
        XCTAssertEqual(kinds([], athletes: [athlete(linked: "2026-11-18T09:00:00Z")]), [], "just joined, nothing yet")
    }

    func testRestRowsNeverCount() throws {
        // A completed rest row is not a run.
        let workouts = [try workout("2026-11-17", type: "rest", doneAt: "2026-11-17T07:00:00Z", km: 0)]
        XCTAssertEqual(kinds(workouts), [])
    }

    func testOtherAthletesWorkoutsAreNotMixedIn() throws {
        let workouts = [
            try workout("2026-11-17", athlete: avi, doneAt: "2026-11-17T07:00:00Z", km: 3),
            try workout("2026-11-17", athlete: noa)
        ]
        let result = CoachMilestoneRules.milestones(
            athletes: [athlete(), athlete(avi)], workouts: workouts, runs: [], now: now, week: week()
        )
        XCTAssertEqual(result[noa]?.map(\.kind), [.quiet3Days], "Noa missed hers; Avi's run is not hers")
        XCTAssertEqual(result[avi]?.map(\.kind), [.firstRun])
    }

    // MARK: Longest run

    private func history(_ kms: [Double], lastDay: String = "2026-11-17") throws -> [CoachWorkoutSummary] {
        // Runs on consecutive days, the last one on `lastDay`.
        let last = CoachMilestoneRules.day(lastDay, calendar: week().calendar)!
        return try kms.enumerated().map { index, km in
            let date = week().calendar.date(byAdding: .day, value: -(kms.count - 1 - index) * 2, to: last)!
            let day = CoachReadDay.iso(date, calendar: week().calendar)
            return try workout(day, doneAt: "\(day)T07:00:00Z", km: km)
        }
    }

    func testLongestRunNeedsThreeEarlierWorkouts() throws {
        XCTAssertFalse(kinds(try history([3, 4, 5])).contains(.longestRun), "only 2 earlier workouts: not enough to call it a record")
        XCTAssertTrue(kinds(try history([3, 4, 5, 6])).contains(.longestRun))
    }

    func testLongestRunMustBeStrictlyLonger() throws {
        XCTAssertFalse(kinds(try history([3, 4, 6, 6])).contains(.longestRun), "a tie is not a record")
        XCTAssertFalse(kinds(try history([3, 8, 4, 5])).contains(.longestRun), "shorter than the best so far")
    }

    func testLongestRunSkipsWorkoutsWithoutADistance() throws {
        var workouts = try history([3, 4, 5, 6])
        workouts.append(try workout("2026-11-18", doneAt: "2026-11-18T07:00:00Z", km: nil))
        XCTAssertTrue(kinds(workouts).contains(.longestRun), "a later workout with no distance changes nothing")
    }

    func testLongestRunIsTheLatestRecordAndExpires() throws {
        XCTAssertFalse(kinds(try history([3, 4, 5, 6], lastDay: "2026-11-05")).contains(.longestRun))
    }

    func testSeveralTagsShowTogetherInTagOrder() throws {
        // First run on 12 Nov and a record on 17 Nov, both inside 7 days.
        let workouts = [
            try workout("2026-11-12", doneAt: "2026-11-12T07:00:00Z", km: 2),
            try workout("2026-11-14", doneAt: "2026-11-14T07:00:00Z", km: 3),
            try workout("2026-11-15", doneAt: "2026-11-15T07:00:00Z", km: 4),
            try workout("2026-11-17", doneAt: "2026-11-17T07:00:00Z", km: 6)
        ]
        XCTAssertEqual(kinds(workouts), [.firstRun, .firstFullWeek, .longestRun], "in tag order; 12, 14 and 15 Nov also finish a week")
    }

    // MARK: First full week

    func testFirstFullWeekNeedsEveryNonRestWorkoutDone() throws {
        let week1 = [
            try workout("2026-11-09", doneAt: "2026-11-09T07:00:00Z", km: 3),
            try workout("2026-11-11", doneAt: "2026-11-11T07:00:00Z", km: 4),
            try workout("2026-11-13", doneAt: "2026-11-13T07:00:00Z", km: 5),
            try workout("2026-11-14", type: "rest"),
            try workout("2026-11-15", type: "rest")
        ]
        let result = CoachMilestoneRules.milestones(
            athletes: [athlete(linked: "2026-11-01T00:00:00Z")], workouts: week1, runs: [], now: now, week: week()
        )
        let milestone = try XCTUnwrap(result[noa]?.first { $0.kind == .firstFullWeek })
        XCTAssertEqual(milestone.target, .week("2026-11-09"))
        XCTAssertEqual(milestone.subject, "2026-11-09")

        // One workout still missing: no full week.
        var missing = week1
        missing[2] = try workout("2026-11-13")
        XCTAssertFalse(kinds(missing, athletes: [athlete(linked: "2026-11-01T00:00:00Z")]).contains(.firstFullWeek))
    }

    func testAOneWorkoutWeekIsNotAFullWeek() throws {
        let workouts = [try workout("2026-11-17", doneAt: "2026-11-17T07:00:00Z", km: 3)]
        XCTAssertFalse(kinds(workouts).contains(.firstFullWeek))
    }

    func testOnlyTheFirstFullWeekCounts() throws {
        // Week of 2 Nov was full and long ago; the week of 9 Nov is full too and recent: not a first.
        let workouts = [
            try workout("2026-11-02", doneAt: "2026-11-02T07:00:00Z", km: 3),
            try workout("2026-11-04", doneAt: "2026-11-04T07:00:00Z", km: 3),
            try workout("2026-11-09", doneAt: "2026-11-09T07:00:00Z", km: 3),
            try workout("2026-11-11", doneAt: "2026-11-11T07:00:00Z", km: 3)
        ]
        XCTAssertFalse(kinds(workouts, athletes: [athlete(linked: "2026-11-01T00:00:00Z")]).contains(.firstFullWeek))
    }

    func testWorkoutsBeforeTheAthleteJoinedDoNotBlockTheFirstFullWeek() throws {
        // Joined on Wed 11 Nov. Mon 9 Nov was never part of this coach's plan, so the week of 9 Nov
        // counts only Wed and Fri, both done.
        let workouts = [
            try workout("2026-11-09"),
            try workout("2026-11-11", doneAt: "2026-11-11T07:00:00Z", km: 3),
            try workout("2026-11-13", doneAt: "2026-11-13T07:00:00Z", km: 4)
        ]
        XCTAssertTrue(kinds(workouts, athletes: [athlete(linked: "2026-11-11T08:00:00Z")]).contains(.firstFullWeek))
    }

    func testWeekStartFollowsTheCoachsFirstWeekday() throws {
        // Sunday-start week (Israel): Sun 8 Nov to Sat 14 Nov.
        let il = CoachAthleteWeek(now: now, locale: Locale(identifier: "he_IL"), timeZone: .gmt)
        let workouts = [
            try workout("2026-11-08", doneAt: "2026-11-08T07:00:00Z", km: 3),
            try workout("2026-11-12", doneAt: "2026-11-12T07:00:00Z", km: 3)
        ]
        let result = CoachMilestoneRules.milestones(
            athletes: [athlete(linked: "2026-11-01T00:00:00Z")], workouts: workouts, runs: [], now: now, week: il
        )
        XCTAssertEqual(result[noa]?.first { $0.kind == .firstFullWeek }?.target, .week("2026-11-08"))
    }

    // MARK: Quiet 3 days

    func testQuietThreeDaysNeedsWorkoutsDueAndNoneDone() throws {
        // Sat 14, Sun 15 and Mon 16 were planned; today is Wed 18 at 12:00, so the window is 15 to 17.
        let missed = [
            try workout("2026-11-15"), try workout("2026-11-16"), try workout("2026-11-17")
        ]
        XCTAssertEqual(kinds(missed), [.quiet3Days])

        var oneDone = missed
        oneDone[1] = try workout("2026-11-16", doneAt: "2026-11-16T07:00:00Z", km: 3)
        XCTAssertFalse(kinds(oneDone).contains(.quiet3Days))
    }

    func testRestDaysAloneNeverMakeAnAthleteQuiet() throws {
        let workouts = [
            try workout("2026-11-15", type: "rest"), try workout("2026-11-16", type: "rest"),
            try workout("2026-11-17", type: "rest"), try workout("2026-11-18")
        ]
        XCTAssertEqual(kinds(workouts), [], "nothing was due, and today is still open")
    }

    func testQuietIsOffWhenThePlanHasNothingInTheWindow() throws {
        XCTAssertEqual(kinds([], athletes: [athlete(plan: false)]), [])
    }

    func testQuietNeedsThreeDaysWithTheCoach() throws {
        let workouts = [try workout("2026-11-16"), try workout("2026-11-17")]
        XCTAssertEqual(kinds(workouts, athletes: [athlete(linked: "2026-11-16T10:00:00Z")]), [], "joined 2 days ago: window starts before the link")
        XCTAssertEqual(kinds(workouts, athletes: [athlete(linked: "2026-11-15T10:00:00Z")]), [.quiet3Days])
    }

    func testQuietIgnoresAWorkoutDoneEarlyFromTheFuture() throws {
        // Thursday's workout was done on Tuesday: the athlete was active in the window.
        let workouts = [
            try workout("2026-11-16"), try workout("2026-11-17"),
            try workout("2026-11-19", doneAt: "2026-11-17T18:00:00Z", km: 4)
        ]
        XCTAssertFalse(kinds(workouts).contains(.quiet3Days))
    }

    func testQuietWindowMovesAtTwentyHundredInTheCoachsTimeZone() throws {
        // Asia/Jerusalem is UTC+2 in November. 17:59 UTC is 19:59 local (window 15 to 17); 18:00 UTC is 20:00
        // local (the window shifts to 16 to 18, so a missed Wednesday workout now counts).
        let jerusalem = TimeZone(identifier: "Asia/Jerusalem")!
        let onlyToday = [try workout("2026-11-18")]
        XCTAssertEqual(kinds(onlyToday, at: iso("2026-11-18T17:59:00Z"), zone: jerusalem), [], "19:59: today is still open")
        XCTAssertEqual(kinds(onlyToday, at: iso("2026-11-18T18:00:00Z"), zone: jerusalem), [.quiet3Days], "20:00: today counts as missed")
        let onlyOld = [try workout("2026-11-15")]
        XCTAssertEqual(kinds(onlyOld, at: iso("2026-11-18T17:59:00Z"), zone: jerusalem), [.quiet3Days])
        XCTAssertEqual(kinds(onlyOld, at: iso("2026-11-18T18:00:00Z"), zone: jerusalem), [], "the 15th left the window at 20:00")
    }

    func testQuietCannotBePraisedAndHasNoTarget() throws {
        let result = CoachMilestoneRules.milestones(
            athletes: [athlete()], workouts: [try workout("2026-11-16")], runs: [], now: now, week: week()
        )
        let quiet = try XCTUnwrap(result[noa]?.first)
        XCTAssertEqual(quiet.kind, .quiet3Days)
        XCTAssertFalse(quiet.kind.canPraise, "coach-only: never a message to the athlete")
        XCTAssertNil(quiet.target)
    }

    // MARK: Time zones

    func testTheSevenDayWindowStartsAtLocalMidnight() throws {
        // Done at 22:30 UTC on 11 Nov = 00:30 on 12 Nov in Jerusalem. The window there starts 12 Nov 00:00 local.
        let jerusalem = TimeZone(identifier: "Asia/Jerusalem")!
        let workouts = [try workout("2026-11-12", doneAt: "2026-11-11T22:30:00Z", km: 3)]
        XCTAssertEqual(kinds(workouts, at: iso("2026-11-18T12:00:00Z"), zone: jerusalem), [.firstRun])
        XCTAssertEqual(kinds(workouts, at: iso("2026-11-18T12:00:00Z"), zone: .gmt), [], "11 Nov is 8 days back in UTC")
    }

    // MARK: Today rows

    private func snapshot(_ milestones: [UUID: [CoachMilestone]], workouts: [CoachWorkoutSummary] = []) -> CoachTodaySnapshot {
        CoachTodaySnapshot.make(
            athletes: [athlete(), athlete(avi)], workouts: workouts, runs: [], milestones: milestones,
            now: now, week: week(), locale: Locale(identifier: "en_US")
        )
    }

    private func praise(_ id: UUID, _ kind: CoachMilestoneKind = .firstRun) -> CoachMilestone {
        CoachMilestone(athleteID: id, kind: kind, subject: "s", target: .run(7), fallbackTarget: .week("2026-11-16"))
    }

    func testRowsCarryTheirTagsAndNoMilestonesMeansNoStrip() {
        let result = snapshot([noa: [praise(noa)]])
        XCTAssertEqual(result.rows.first { $0.id == noa }?.milestones.map(\.kind), [.firstRun])
        XCTAssertEqual(result.rows.first { $0.id == avi }?.milestones, [])
        XCTAssertTrue(snapshot([:]).rows.allSatisfy { $0.milestones.isEmpty })
    }

    func testAPraiseTagMovesACalmRowOutOfTheCollapsedGroup() {
        let plain = snapshot([:])
        XCTAssertEqual(plain.rows.first { $0.id == noa }?.group, .restToday, "no workouts today: collapsed Rest today")
        let tagged = snapshot([noa: [praise(noa)]])
        XCTAssertEqual(tagged.rows.first { $0.id == noa }?.group, .newToReview)
        XCTAssertEqual(tagged.rows.first { $0.id == avi }?.group, .restToday)
    }

    func testQuietDoesNotMoveARowButUrgentRowsKeepTheirGroup() throws {
        let quiet = snapshot([noa: [praise(noa, .quiet3Days)]])
        XCTAssertEqual(quiet.rows.first { $0.id == noa }?.group, .restToday, "Quiet 3 days is not praise")
        // Noa missed yesterday: urgent, and a first-run tag does not pull her out of that group.
        let missed = snapshot([noa: [praise(noa)]], workouts: [try workout("2026-11-17")])
        XCTAssertEqual(missed.rows.first { $0.id == noa }?.group, .missedYesterday)
        XCTAssertEqual(missed.rows.first { $0.id == noa }?.milestones.count, 1)
    }

    func testMilestonesChangeTheLayoutSignature() {
        XCTAssertNotEqual(snapshot([:]).layoutSignature, snapshot([noa: [praise(noa)]]).layoutSignature)
    }

    func testReactionsAreOneTapPhrases() {
        XCTAssertEqual(CoachReaction.allCases.map(\.text), ["👏", "🔥", "Great job"])
        XCTAssertTrue(CoachReaction.allCases.allSatisfy { CoachFeedbackText.canSend($0.text) })
    }

    func testFeedbackIDIsStableAndPerCoachAndMilestone() {
        let first = CoachMilestoneReactions.feedbackID(coachID: coach, milestoneID: "a|first_run|x")
        XCTAssertEqual(first, CoachMilestoneReactions.feedbackID(coachID: coach, milestoneID: "a|first_run|x"))
        XCTAssertNotEqual(first, CoachMilestoneReactions.feedbackID(coachID: coach, milestoneID: "a|first_run|y"))
        XCTAssertNotEqual(first, CoachMilestoneReactions.feedbackID(coachID: UUID(), milestoneID: "a|first_run|x"))
    }

    // MARK: The model: loading, reacting

    private struct Harness {
        let model: CoachAthleteListModel
        let feedback: MockCoachFeedbackService
        let spy: MilestoneEventSpy
        let reader: ReactionReaderStub
        let read: MilestoneReadStub
        let store: CoachMilestoneReactionStore
    }

    private func harness(
        workouts: [CoachWorkoutSummary], runs: [CoachRunSummary] = [], v2: Bool = true,
        old: [CoachWorkoutSummary] = []
    ) async -> Harness {
        let read = MilestoneReadStub()
        read.athletes = [athlete()]
        read.recentWorkouts = workouts
        read.oldWorkouts = old
        read.runResults = runs
        let feedback = MockCoachFeedbackService()
        feedback.signedInCoach = coach
        let spy = MilestoneEventSpy()
        let reader = ReactionReaderStub()
        let store = CoachMilestoneReactionStore(defaults: defaults())
        let outbox = CoachFeedbackOutbox(defaults: defaults(), sessionCoachID: { [coach] in coach })
        let seen = CoachSeenStub()
        let model = CoachAthleteListModel(
            service: read, rosterStatus: { [:] }, tracker: spy, seen: seen,
            outbox: CoachV2Outbox(defaults: defaults(), repository: seen, tracker: spy), flagStore: .offline(),
            feedbackService: feedback, feedbackOutbox: outbox, reactionStore: store, reactionReader: reader
        )
        if v2 { await model.applyCoachV2(.on) }
        await model.refresh(owner: coach, now: now)
        return Harness(model: model, feedback: feedback, spy: spy, reader: reader, read: read, store: store)
    }

    private var firstRunWorkouts: (workouts: [CoachWorkoutSummary], runs: [CoachRunSummary]) {
        get throws {
            let id = UUID()
            return ([try workout("2026-11-17", id: id, doneAt: "2026-11-17T07:00:00Z", km: 3)], [try run(901, workout: id)])
        }
    }

    func testRefreshBuildsMilestonesAndFiresShownOncePerSession() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        let row = try XCTUnwrap(h.model.today?.rows.first)
        XCTAssertEqual(row.milestones.map(\.kind), [.firstRun])
        h.model.trackMilestonesShown()
        h.model.trackMilestonesShown()
        let shown = h.spy.events.filter { $0.name == "milestone_shown" }
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.properties["kind"] as? String, "first_run")
        XCTAssertEqual(shown.first?.properties.count, 1, "only the kind: no athlete, no names")
    }

    func testFlagOffAndPausedMakeNoMilestoneCallAndShowNothing() async throws {
        let data = try firstRunWorkouts
        for state in [CoachV2State.off, .paused] {
            let read = MilestoneReadStub()
            read.athletes = [athlete()]
            read.recentWorkouts = data.workouts
            let spy = MilestoneEventSpy()
            let seen = CoachSeenStub()
            let model = CoachAthleteListModel(
                service: read, rosterStatus: { [:] }, tracker: spy, seen: seen,
                outbox: CoachV2Outbox(defaults: defaults(), repository: seen, tracker: spy), flagStore: .offline(),
                feedbackService: MockCoachFeedbackService(),
                feedbackOutbox: CoachFeedbackOutbox(defaults: defaults(), sessionCoachID: { [coach] in coach }),
                reactionStore: CoachMilestoneReactionStore(defaults: defaults()), reactionReader: ReactionReaderStub()
            )
            await model.applyCoachV2(state)
            await model.refresh(owner: coach, now: now)
            XCTAssertNil(model.today, "\(state): no Today, so no tags, no strip, no headers")
            XCTAssertEqual(read.historyCalls, 0, "\(state): no wide history read")
            model.trackMilestonesShown()
            XCTAssertTrue(spy.events.isEmpty)
        }
    }

    func testReactingSavesOneNoteOnTheRunAndAShownTagBecomesReacted() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        let milestone = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        XCTAssertFalse(h.model.isReacted(milestone))

        h.model.react(to: milestone, with: .clap)
        XCTAssertTrue(h.model.isReacted(milestone), "Reacted shows at the tap, before the send ends")
        h.model.react(to: milestone, with: .fire)   // a double tap
        h.model.react(to: milestone, with: .greatJob)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(h.feedback.addCalls, 1, "a second tap never sends a second reaction")
        let stored = try XCTUnwrap(h.feedback.stored.first)
        XCTAssertEqual(h.feedback.stored.count, 1)
        XCTAssertEqual(stored.text, "👏")
        XCTAssertEqual(stored.target, .run(901))
        XCTAssertEqual(stored.athleteID, noa)
        XCTAssertEqual(stored.id, CoachMilestoneReactions.feedbackID(coachID: coach, milestoneID: milestone.id))
        XCTAssertEqual(h.spy.events.filter { $0.name == "praise_sent" }.count, 1)
        let sent = try XCTUnwrap(h.spy.events.first { $0.name == "praise_sent" })
        XCTAssertEqual(sent.properties["kind"] as? String, "first_run")
        XCTAssertEqual(sent.properties.count, 1, "not the reaction, not the athlete")
    }

    func testReactedStateSurvivesARefreshAndARelaunch() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        let milestone = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        h.model.react(to: milestone, with: .fire)
        try await Task.sleep(for: .milliseconds(200))
        await h.model.refresh(owner: coach, now: now)
        XCTAssertTrue(h.model.isReacted(milestone))
        XCTAssertTrue(h.store.reacted(coachID: coach).contains(milestone.id), "kept on the phone for a new launch")
    }

    func testANoteAlreadyWrittenOnTheRunCountsAsReacted() async throws {
        let data = try firstRunWorkouts
        let read = MilestoneReadStub()
        _ = read
        let h = await harness(workouts: data.workouts, runs: data.runs)
        h.reader.targets = [noa: [CoachFeedbackTarget.run(901).key]]
        await h.model.refresh(owner: coach, now: now)
        let milestone = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        XCTAssertTrue(h.model.isReacted(milestone), "written from the composer or another phone")
        h.model.react(to: milestone, with: .clap)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(h.feedback.addCalls, 0)
    }

    func testAFailedReactionsReadKeepsThePhonesOwnRecord() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        let milestone = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        h.model.react(to: milestone, with: .clap)
        try await Task.sleep(for: .milliseconds(200))
        h.reader.error = URLError(.notConnectedToInternet)
        await h.model.refresh(owner: coach, now: now)
        XCTAssertTrue(h.model.isReacted(milestone))
        XCTAssertNotNil(h.model.today, "a failed read never turns Today into an error")
    }

    func testReactingOfflineQueuesOnceAndTheNextRefreshSendsIt() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        let milestone = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        h.feedback.failure = .notSent
        h.model.react(to: milestone, with: .greatJob)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(h.model.isReacted(milestone), "queued: still Reacted")
        XCTAssertEqual(h.feedback.stored.count, 0)

        h.feedback.failure = nil
        await h.model.refresh(owner: coach, now: now)
        XCTAssertEqual(h.feedback.stored.count, 1)
        XCTAssertEqual(h.feedback.stored.first?.text, "Great job")
        h.model.react(to: milestone, with: .clap)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(h.feedback.stored.count, 1, "still one reaction")
    }

    func testARefusedReactionBringsTheButtonsBack() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        let milestone = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        h.feedback.failure = .rejected
        h.model.react(to: milestone, with: .clap)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(h.model.isReacted(milestone))
        XCTAssertTrue(h.model.reactionFailed(milestone))
        XCTAssertFalse(h.store.reacted(coachID: coach).contains(milestone.id))
    }

    func testQuietAndFlagOffCannotBeReactedTo() async throws {
        let h = await harness(workouts: [try workout("2026-11-16"), try workout("2026-11-17")])
        let quiet = try XCTUnwrap(h.model.today?.rows.first?.milestones.first)
        XCTAssertEqual(quiet.kind, .quiet3Days)
        h.model.react(to: quiet, with: .clap)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(h.feedback.addCalls, 0, "Quiet 3 days never sends a message")
        XCTAssertFalse(h.model.isReacted(quiet))
        XCTAssertTrue(h.spy.events.filter { $0.name == "praise_sent" }.isEmpty)

        await h.model.applyCoachV2(.off)
        h.model.react(to: praise(noa), with: .clap)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(h.feedback.addCalls, 0, "flag-off: no write")
    }

    func testHistoryIsReadOnceThenCachedAndAFailureKeepsTheRecentWindow() async throws {
        let data = try firstRunWorkouts
        let h = await harness(workouts: data.workouts, runs: data.runs)
        XCTAssertEqual(h.read.historyCalls, 1)
        await h.model.refresh(owner: coach, now: now.addingTimeInterval(60))
        XCTAssertEqual(h.read.historyCalls, 1, "the old part is cached for 30 minutes")

        let failing = await harness(workouts: data.workouts, runs: data.runs, old: [])
        failing.read.historyError = URLError(.timedOut)
        await failing.model.refresh(owner: coach, now: now.addingTimeInterval(3_600))
        XCTAssertNotNil(failing.model.today, "history failing never fails Today")
    }
}
