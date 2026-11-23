import Supabase
import XCTest
@testable import IOS_RunSmart_app

// C7.2 "New since last visit": the "{n} new" marker and the "New to review" group on Coach Today,
// seen state (local at once, server through the outbox), the outbox rules, flag-off and analytics.

/// Stub for `coach_roster_summary`, `coach_mark_athlete_seen` and `athlete_log_goal_change`.
final class CoachSeenStub: CoachSeenRepository, @unchecked Sendable {
    var news: [UUID: CoachAthleteNews] = [:]
    var newsError: Error?
    var markError: Error?
    var goalError: Error?
    var goalResult = true
    private(set) var newsCalls = 0
    private(set) var marks: [(athleteID: UUID, seenAt: Date)] = []
    private(set) var goalClientIDs: [UUID] = []

    func rosterNews() async throws -> [UUID: CoachAthleteNews] {
        newsCalls += 1
        if let newsError { throw newsError }
        return news
    }

    func markSeen(athleteID: UUID, seenAt: Date) async throws {
        if let markError { throw markError }
        marks.append((athleteID, seenAt))
    }

    func logGoalChange(clientID: UUID) async throws -> Bool {
        goalClientIDs.append(clientID)
        if let goalError { throw goalError }
        return goalResult
    }
}

private final class SeenReadStub: CoachReadServing, @unchecked Sendable {
    var athletes: [CoachAthleteSummary] = []
    var workoutResults: [CoachWorkoutSummary] = []
    var runResults: [CoachRunSummary] = []

    func listAthletes() async throws -> [CoachAthleteSummary] { athletes }
    func plan(for athleteID: UUID) async throws -> [CoachPlanSummary] { [] }
    func workouts(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachWorkoutSummary] {
        workoutResults
    }
    func runs(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachRunSummary] {
        runResults
    }
    func latestRun(for athleteID: UUID, through: Date) async throws -> CoachRunSummary? { nil }
}

private nonisolated final class SeenEventSpy: AnalyticsTracking {
    private(set) var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}
}

@MainActor
final class CoachSeenStateTests: XCTestCase {
    private let yoni = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    private let noa = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!
    private let avi = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000003")!
    private let coach = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000001")!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "CoachSeenStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Fixtures

    private func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { iso("2026-11-18T12:00:00Z") }
    private var week: CoachAthleteWeek { CoachAthleteWeek(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt) }

    private func summary(_ id: UUID, _ name: String, plan: Bool = true) -> CoachAthleteSummary {
        CoachAthleteSummary(athleteID: id, displayName: name, linkedAt: iso("2026-01-01T00:00:00Z"), hasActivePlan: plan)
    }

    private func workout(_ id: UUID, _ athlete: UUID, _ date: String) throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(id)","athlete_id":"\(athlete)","plan_id":"\(UUID())","scheduled_date":"\(date)",
        "type":"easy","planned_distance":5,"planned_duration_minutes":30,"completed":false}
        """.utf8))
    }

    private func run(_ id: Int, _ athlete: UUID, _ workout: UUID, _ stamp: String) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":"\(workout)","completed_at":"\(stamp)",
        "distance_km":5,"duration_seconds":1700}
        """.utf8))
    }

    /// Everyone is on track: yesterday done, today still to do (before 20:00).
    private func onTrack(_ athletes: [UUID]) throws -> (workouts: [CoachWorkoutSummary], runs: [CoachRunSummary]) {
        var workouts: [CoachWorkoutSummary] = []
        var runs: [CoachRunSummary] = []
        for (index, athlete) in athletes.enumerated() {
            let past = UUID()
            workouts.append(try workout(past, athlete, "2026-11-17"))
            workouts.append(try workout(UUID(), athlete, "2026-11-18"))
            runs.append(try run(index + 1, athlete, past, "2026-11-17T07:00:00Z"))
        }
        return (workouts, runs)
    }

    private func snapshot(news: [UUID: CoachAthleteNews], athletes: [CoachAthleteSummary]? = nil) throws -> CoachTodaySnapshot {
        let list = athletes ?? [summary(yoni, "Yoni"), summary(noa, "Noa"), summary(avi, "Avi")]
        let data = try onTrack(list.map(\.athleteID))
        return CoachTodaySnapshot.make(
            athletes: list, workouts: data.workouts, runs: data.runs, news: news, now: now, week: week,
            locale: Locale(identifier: "en_US")
        )
    }

    private func row(_ snapshot: CoachTodaySnapshot, _ id: UUID) -> CoachTodayRow? { snapshot.rows.first { $0.id == id } }

    // MARK: AC2: the marker and the group

    func testNewRunsPutAnOnTrackAthleteInNewToReviewWithDotAndText() throws {
        let result = try snapshot(news: [yoni: CoachAthleteNews(newRuns: 2, oldestNewAt: now)])
        let yoniRow = try XCTUnwrap(row(result, yoni))
        XCTAssertEqual(yoniRow.group, .newToReview)
        XCTAssertEqual(yoniRow.reason, .newRun)
        XCTAssertEqual(yoniRow.newCount, 2)
        XCTAssertEqual(yoniRow.newLabel, "2 new")
        XCTAssertTrue(yoniRow.spokenSentence.hasSuffix(" 2 new."), yoniRow.spokenSentence)
        XCTAssertEqual(result.groups, [.newToReview, .onTrack])
        XCTAssertEqual(CoachTodayGroup.newToReview.title(count: 1), "New to review (1)")
        XCTAssertFalse(CoachTodayGroup.newToReview.startsCollapsed)
        XCTAssertFalse(CoachTodayGroup.newToReview.needsYou, "new is not urgent: the header count stays the same")
    }

    func testNothingNewShowsNoGroupAndNoMarker() throws {
        let result = try snapshot(news: [yoni: CoachAthleteNews(seenAt: now)])
        XCTAssertFalse(result.groups.contains(.newToReview), "no empty header")
        for row in result.rows {
            XCTAssertEqual(row.newCount, 0)
            XCTAssertNil(row.newLabel, "the dot is drawn only with its text, so no text means no dot")
            XCTAssertFalse(row.spokenSentence.contains(" new."))
        }
    }

    func testChipFollowsTheSpecOrder() {
        XCTAssertEqual(CoachTodayReason.newReason(for: CoachAthleteNews(newRuns: 1, newReplies: 1)), .reply)
        XCTAssertEqual(CoachTodayReason.newReason(for: CoachAthleteNews(newRuns: 1, newEvents: 1, latestEventKind: .goalChange)), .newRun)
        XCTAssertEqual(CoachTodayReason.newReason(for: CoachAthleteNews(newEvents: 1, latestEventKind: .goalChange)), .changedGoal)
        XCTAssertEqual(CoachTodayReason.newReason(for: CoachAthleteNews(newEvents: 2, latestEventKind: .athleteMove)), .changedWorkout)
        XCTAssertEqual(CoachTodayReason.newReason(for: CoachAthleteNews(newEvents: 1, latestEventKind: .athleteSkip)), .changedWorkout)
        XCTAssertNil(CoachTodayReason.newReason(for: CoachAthleteNews(newFlags: 1)), "flags get their own chip in C7.4")
        XCTAssertNil(CoachTodayReason.newReason(for: nil))
        XCTAssertEqual(CoachTodayReason.changedGoal.chip, "Changed goal")
        XCTAssertEqual(CoachTodayReason.changedWorkout.chip, "Changed your workout")
        XCTAssertEqual(CoachTodayReason.newRun.chip, "New run")
        XCTAssertEqual(CoachTodayReason.reply.chip, "Reply")
    }

    func testGoalChangeShowsChangedGoal() throws {
        let result = try snapshot(news: [noa: CoachAthleteNews(newEvents: 1, latestEventKind: .goalChange, oldestNewAt: now)])
        let noaRow = try XCTUnwrap(row(result, noa))
        XCTAssertEqual(noaRow.reason, .changedGoal)
        XCTAssertEqual(noaRow.group, .newToReview)
        XCTAssertEqual(noaRow.newLabel, "1 new")
    }

    func testUrgentAthleteKeepsItsGroupAndStillShowsTheMarker() throws {
        // Yoni missed yesterday, and is behind for the week: urgent. The marker still shows; the chip and
        // the second-line reason stay the urgent ones.
        let missed = UUID()
        let workouts = try [workout(missed, yoni, "2026-11-17"), workout(UUID(), yoni, "2026-11-18")]
        let result = CoachTodaySnapshot.make(
            athletes: [summary(yoni, "Yoni")], workouts: workouts, runs: [],
            news: [yoni: CoachAthleteNews(newEvents: 1, latestEventKind: .goalChange)], now: now, week: week,
            locale: Locale(identifier: "en_US")
        )
        let yoniRow = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(yoniRow.group, .missedYesterday)
        XCTAssertEqual(yoniRow.reason, .missedYesterday)
        XCTAssertEqual(yoniRow.secondaryReason, .behind)
        XCTAssertEqual(yoniRow.newLabel, "1 new")
        XCTAssertTrue(yoniRow.spokenSentence.hasSuffix(" 1 new."))
        XCTAssertFalse(result.groups.contains(.newToReview), "urgent rows are not repeated in New to review")
    }

    func testNoPlanAthleteWithAGoalChangeIsNewToReview() throws {
        let result = try snapshot(
            news: [avi: CoachAthleteNews(newEvents: 1, latestEventKind: .goalChange)],
            athletes: [summary(avi, "Avi", plan: false)]
        )
        let aviRow = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(aviRow.group, .newToReview)
        XCTAssertEqual(aviRow.spokenSentence, "Avi. Changed goal. Waiting for a plan. 1 new.")
    }

    func testNewToReviewOrdersOldestItemFirst() throws {
        let result = try snapshot(news: [
            yoni: CoachAthleteNews(newRuns: 1, oldestNewAt: now.addingTimeInterval(-600)),
            noa: CoachAthleteNews(newRuns: 1, oldestNewAt: now.addingTimeInterval(-3600)),
            avi: CoachAthleteNews(newRuns: 1, oldestNewAt: now.addingTimeInterval(-60))
        ])
        XCTAssertEqual(result.rows(in: .newToReview).map(\.name), ["Noa", "Yoni", "Avi"])
    }

    func testLayoutSignatureChangesWithTheCount() throws {
        let one = try snapshot(news: [yoni: CoachAthleteNews(newRuns: 1)])
        let two = try snapshot(news: [yoni: CoachAthleteNews(newRuns: 2)])
        XCTAssertNotEqual(one.layoutSignature, two.layoutSignature, "a quiet refresh holds a new count behind the pill")
    }

    // MARK: Model: seen state

    private func model(
        _ seen: CoachSeenStub, tracker: SeenEventSpy? = nil, athletes: [CoachAthleteSummary]? = nil
    ) throws -> (CoachAthleteListModel, CoachV2Outbox) {
        let read = SeenReadStub()
        read.athletes = athletes ?? [summary(yoni, "Yoni"), summary(noa, "Noa")]
        let data = try onTrack(read.athletes.map(\.athleteID))
        read.workoutResults = data.workouts
        read.runResults = data.runs
        let outbox = CoachV2Outbox(defaults: defaults, repository: seen, tracker: tracker ?? SeenEventSpy(), now: { self.now })
        let list = CoachAthleteListModel(service: read, rosterStatus: { [:] }, tracker: tracker ?? SeenEventSpy(), seen: seen, outbox: outbox,
                                         flagStore: .offline())
        return (list, outbox)
    }

    func testFlagOffMakesNoV2CallAndQueuesNothing() async throws {
        let seen = CoachSeenStub()
        seen.news = [yoni: CoachAthleteNews(newRuns: 2)]
        let spy = SeenEventSpy()
        let (list, outbox) = try model(seen, tracker: spy)
        await list.refresh(owner: coach, now: now)
        list.markSeen(yoni, now: now)
        await list.applyCoachV2(.paused)
        await list.refresh(owner: coach, now: now)
        list.markSeen(yoni, now: now)
        XCTAssertEqual(seen.newsCalls, 0)
        XCTAssertTrue(outbox.items.isEmpty)
        XCTAssertTrue(seen.marks.isEmpty)
        XCTAssertNil(list.today)
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testV2RefreshReadsTheCountsAndShowsTheMarker() async throws {
        let seen = CoachSeenStub()
        seen.news = [yoni: CoachAthleteNews(newRuns: 2, oldestNewAt: now)]
        let (list, _) = try model(seen)
        await list.applyCoachV2(.on)
        await list.refresh(owner: coach, now: now)
        XCTAssertGreaterThanOrEqual(seen.newsCalls, 1)
        XCTAssertEqual(list.today.flatMap { row($0, yoni) }?.newLabel, "2 new")
        XCTAssertEqual(list.today.flatMap { row($0, yoni) }?.group, .newToReview)
    }

    func testCountsFailureShowsNoMarkersAndNoError() async throws {
        let seen = CoachSeenStub()
        seen.newsError = URLError(.notConnectedToInternet)
        let (list, _) = try model(seen)
        await list.applyCoachV2(.on)
        await list.refresh(owner: coach, now: now)
        XCTAssertFalse(list.failure)
        XCTAssertNotNil(list.today)
        XCTAssertFalse(list.today?.groups.contains(.newToReview) ?? true)
    }

    func testOpeningDetailClearsTheMarkerAndSendsSeenWithTheOpenTime() async throws {
        let seen = CoachSeenStub()
        seen.news = [yoni: CoachAthleteNews(newRuns: 2, oldestNewAt: now)]
        let spy = SeenEventSpy()
        let (list, outbox) = try model(seen, tracker: spy)
        await list.applyCoachV2(.on)
        await list.refresh(owner: coach, now: now)
        let openedAt = now.addingTimeInterval(60)
        list.markSeen(yoni, now: openedAt)
        // At once on this phone, before the server answers.
        XCTAssertNil(list.today.flatMap { row($0, yoni) }?.newLabel)
        XCTAssertEqual(list.today.flatMap { row($0, yoni) }?.group, .onTrack)
        await outbox.flush(userID: coach)
        XCTAssertEqual(seen.marks.map(\.athleteID), [yoni])
        XCTAssertEqual(seen.marks.first?.seenAt, openedAt)
        XCTAssertTrue(outbox.items.isEmpty)
        let event = try XCTUnwrap(spy.events.first { $0.name == "coach_athlete_seen" })
        XCTAssertEqual(event.properties["new_count"] as? Int, 2)
        XCTAssertEqual(Set(event.properties.keys), ["new_count"], "counts only")
    }

    func testOfflineOpenStaysClearedUntilTheServerCatchesUp() async throws {
        let seen = CoachSeenStub()
        seen.news = [yoni: CoachAthleteNews(newRuns: 2)]
        seen.markError = URLError(.notConnectedToInternet)
        let (list, outbox) = try model(seen)
        await list.applyCoachV2(.on)
        await list.refresh(owner: coach, now: now)
        let openedAt = now.addingTimeInterval(60)
        list.markSeen(yoni, now: openedAt)
        await outbox.flush(userID: coach)
        XCTAssertEqual(outbox.items.count, 1, "kept for the next foreground")
        // The server still reports the old counts: the marker must not come back.
        await list.refresh(owner: coach, now: now)
        XCTAssertNil(list.today.flatMap { row($0, yoni) }?.newLabel)
        // Back online: the server seen_at catches up, and a run after the open shows as new again.
        seen.markError = nil
        seen.news = [yoni: CoachAthleteNews(seenAt: openedAt, newRuns: 1, oldestNewAt: openedAt.addingTimeInterval(30))]
        await list.refresh(owner: coach, now: now)
        XCTAssertTrue(outbox.items.isEmpty)
        XCTAssertEqual(list.today.flatMap { row($0, yoni) }?.newLabel, "1 new")
    }

    func testSecondCoachPhoneClearsAfterARefresh() async throws {
        // Seen state is the server's. Another phone's open arrives as seen_at with zero counts.
        let seen = CoachSeenStub()
        seen.news = [yoni: CoachAthleteNews(newRuns: 2)]
        let (list, _) = try model(seen)
        await list.applyCoachV2(.on)
        await list.refresh(owner: coach, now: now)
        XCTAssertEqual(list.today.flatMap { row($0, yoni) }?.newLabel, "2 new")
        seen.news = [yoni: CoachAthleteNews(seenAt: now)]
        await list.refresh(owner: coach, now: now)
        XCTAssertNil(list.today.flatMap { row($0, yoni) }?.newLabel)
    }

    func testQuietRefreshHoldsANewMarkerBehindThePill() async throws {
        let seen = CoachSeenStub()
        let (list, _) = try model(seen)
        await list.applyCoachV2(.on)
        await list.refresh(owner: coach, now: now)
        seen.news = [noa: CoachAthleteNews(newRuns: 1)]
        await list.refresh(owner: coach, now: now, style: .quiet)
        XCTAssertTrue(list.hasPendingUpdate, "no re-sort while visible")
        XCTAssertNil(list.today.flatMap { row($0, noa) }?.newLabel)
        list.applyPendingUpdate()
        XCTAssertEqual(list.today.flatMap { row($0, noa) }?.newLabel, "1 new")
    }

    // MARK: Outbox

    private func outbox(_ seen: CoachSeenStub, spy: SeenEventSpy = SeenEventSpy(), at date: @escaping () -> Date) -> CoachV2Outbox {
        CoachV2Outbox(defaults: defaults, repository: seen, tracker: spy, now: date)
    }

    func testOutboxKeepsTheLatestSeenPerAthleteAndOtherAccountsItems() async {
        let seen = CoachSeenStub()
        let box = outbox(seen) { self.now }
        let other = UUID()
        box.enqueue(.markSeen(athleteID: yoni, seenAt: now), userID: coach)
        box.enqueue(.markSeen(athleteID: yoni, seenAt: now.addingTimeInterval(10)), userID: coach)
        box.enqueue(.markSeen(athleteID: yoni, seenAt: now), userID: other)
        XCTAssertEqual(box.items.count, 2)
        await box.flush(userID: coach)
        XCTAssertEqual(seen.marks.map(\.seenAt), [now.addingTimeInterval(10)])
        XCTAssertEqual(box.items.map(\.userID), [other], "another account's item waits for that account")
    }

    func testOutboxSurvivesARelaunch() {
        let seen = CoachSeenStub()
        outbox(seen) { self.now }.enqueue(.goalChange, userID: coach)
        XCTAssertEqual(outbox(seen) { self.now }.items.count, 1)
    }

    func testOutboxDropsLinkInactiveAndKeepsV2Unavailable() async {
        let seen = CoachSeenStub()
        let box = outbox(seen) { self.now }
        seen.markError = PostgrestError(code: "P0001", message: "link_inactive")
        box.enqueue(.markSeen(athleteID: yoni, seenAt: now), userID: coach)
        await box.flush(userID: coach)
        XCTAssertTrue(box.items.isEmpty, "link ended: dropped")

        seen.markError = PostgrestError(code: "P0001", message: "v2_unavailable")
        box.enqueue(.markSeen(athleteID: noa, seenAt: now), userID: coach)
        await box.flush(userID: coach)
        XCTAssertEqual(box.items.count, 1, "kill switch: kept and retried later")
        seen.markError = nil
        await box.flush(userID: coach)
        XCTAssertTrue(box.items.isEmpty)
        XCTAssertEqual(seen.marks.map(\.athleteID), [noa])
    }

    func testGoalChangeRetriesWithTheSameClientID() async {
        let seen = CoachSeenStub()
        let spy = SeenEventSpy()
        let box = outbox(seen, spy: spy) { self.now }
        seen.goalError = URLError(.notConnectedToInternet)
        await box.logGoalChange(userID: coach)
        seen.goalError = nil
        await box.flush(userID: coach)
        XCTAssertEqual(seen.goalClientIDs.count, 2)
        XCTAssertEqual(Set(seen.goalClientIDs).count, 1, "two flushes, one client id, so one server row")
        XCTAssertTrue(box.items.isEmpty)
        XCTAssertEqual(spy.events.map(\.name), ["athlete_goal_change_logged"])
        XCTAssertTrue(spy.events[0].properties.isEmpty)
    }

    func testGoalChangeWithoutALinkIsDroppedSilently() async {
        let seen = CoachSeenStub()
        seen.goalResult = false
        let spy = SeenEventSpy()
        let box = outbox(seen, spy: spy) { self.now }
        await box.logGoalChange(userID: coach)
        XCTAssertTrue(box.items.isEmpty)
        XCTAssertTrue(spy.events.isEmpty, "no active link: no event (AC4)")
    }

    func testOldItemsAreDropped() async {
        let seen = CoachSeenStub()
        var clock = now
        let box = outbox(seen) { clock }
        box.enqueue(.goalChange, userID: coach)
        clock = now.addingTimeInterval(CoachV2Outbox.maxAge + 60)
        await box.flush(userID: coach)
        XCTAssertTrue(box.items.isEmpty)
        XCTAssertTrue(seen.goalClientIDs.isEmpty)
    }

    func testTimestampParsing() {
        XCTAssertEqual(CoachSeenTimestamp.parse("2026-11-18T12:00:00Z"), now)
        XCTAssertEqual(CoachSeenTimestamp.parse("2026-11-18T12:00:00.000+00:00"), now)
        XCTAssertEqual(CoachSeenTimestamp.parse("2026-11-18 12:00:00+00"), now)
        XCTAssertEqual(CoachSeenTimestamp.parse(CoachSeenTimestamp.iso(now)), now)
    }
}
