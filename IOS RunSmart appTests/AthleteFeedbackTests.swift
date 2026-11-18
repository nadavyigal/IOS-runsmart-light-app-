import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class AthleteFeedbackTests: XCTestCase {
    private let coach = UUID()
    private let athlete = UUID()
    private let linkedAt = ISO8601DateFormatter().date(from: "2026-11-10T08:00:00Z")!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "AthleteFeedbackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var link: CoachLink { CoachLink(id: UUID(), coachID: coach, coachName: "Dana", consentedAt: linkedAt) }

    private func run(endedAt: Date, source: RunSmartDataSource = .runSmart, providerID: String? = nil) -> RecordedRun {
        RecordedRun(
            id: UUID(), providerActivityID: providerID, source: source,
            startedAt: endedAt.addingTimeInterval(-1800), endedAt: endedAt,
            distanceMeters: 5000, movingTimeSeconds: 1800, averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil, routePoints: [], syncedAt: nil
        )
    }

    private func note(on run: RecordedRun? = nil, week: String? = nil, created: Date, read: Date? = nil,
                      coachID: UUID? = nil, edited: Date? = nil, text: String = "Strong finish.") -> AthleteFeedbackNote {
        AthleteFeedbackNote(
            id: UUID(), coachID: coachID ?? coach, coachName: "Dana",
            runID: run == nil ? nil : 101,
            runSourceProvider: run?.runSourceKey.sourceProvider, runSourceActivityID: run?.runSourceKey.sourceActivityID,
            weekStart: week, text: text, createdAt: created, editedAt: edited, readAt: read
        )
    }

    private func store(_ service: MockAthleteFeedbackService) -> AthleteFeedbackStore {
        let store = AthleteFeedbackStore(service: service, cache: AthleteFeedbackCache(defaults: defaults))
        store.beginSession(userID: athlete)
        return store
    }

    func testRunNotesAttachByTheRunsSourceKey() async {
        let mine = run(endedAt: linkedAt.addingTimeInterval(86_400))
        let other = run(endedAt: linkedAt.addingTimeInterval(90_000))
        let service = MockAthleteFeedbackService(rows: [note(on: mine, created: linkedAt.addingTimeInterval(100_000))])
        let store = store(service)
        await store.load()
        XCTAssertEqual(store.notes(for: mine).count, 1, "matched by source provider and the local run id")
        XCTAssertTrue(store.notes(for: other).isEmpty)
        XCTAssertEqual(mine.runSourceKey.sourceActivityID, mine.id.uuidString)
    }

    func testWeekNotesPinToThePlanWeekThatContainsTheirStart() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let service = MockAthleteFeedbackService(rows: [note(week: "2026-11-16", created: linkedAt)])
        let store = store(service)
        await store.load()
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        XCTAssertEqual(store.notes(weekFrom: monday, to: sunday, calendar: calendar).count, 1)
        // A plan week that starts on Sunday the 15th still contains the coach's Monday start.
        let israeliStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        XCTAssertEqual(store.notes(weekFrom: israeliStart, to: sunday.addingTimeInterval(-86_400), calendar: calendar).count, 1)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: monday)!
        XCTAssertTrue(store.notes(weekFrom: nextWeek, to: calendar.date(byAdding: .day, value: 6, to: nextWeek)!, calendar: calendar).isEmpty)
    }

    func testBadgeCountsUnreadFromTheCurrentLinkAndClearsByReading() async {
        let afterLink = linkedAt.addingTimeInterval(3600)
        let unread = note(week: "2026-11-16", created: afterLink)
        let alreadyRead = note(week: "2026-11-09", created: afterLink, read: afterLink)
        let beforeLink = note(week: "2026-11-02", created: linkedAt.addingTimeInterval(-3600))
        let otherCoach = note(week: "2026-11-16", created: afterLink, coachID: UUID())
        let service = MockAthleteFeedbackService(rows: [unread, alreadyRead, beforeLink, otherCoach])
        let store = store(service)
        await store.load()
        XCTAssertEqual(store.unreadCount(link: link), 1)
        XCTAssertEqual(store.unreadCount(link: nil), 0, "no badge when not linked")

        await store.markRead([unread])
        XCTAssertEqual(store.unreadCount(link: link), 0)
        XCTAssertEqual(service.markReadCalls, [unread.id], "opening records read_at on the server")
    }

    func testFailedMarkReadKeepsTheBadgeForTheNextOpen() async {
        let unread = note(week: "2026-11-16", created: linkedAt.addingTimeInterval(3600))
        let service = MockAthleteFeedbackService(rows: [unread])
        let store = store(service)
        await store.load()
        service.failure = URLError(.notConnectedToInternet)
        await store.markRead([unread])
        XCTAssertEqual(store.unreadCount(link: link), 1, "never cleared by anything but a recorded read")
    }

    func testPendingLineAt0And71And73Hours() {
        let ended = linkedAt.addingTimeInterval(86_400)
        let saved = run(endedAt: ended)
        XCTAssertEqual(CoachReviewLine.forRun(saved, link: link, hasFeedback: false, now: ended), .willReview(coach: "Dana"))
        XCTAssertEqual(CoachReviewLine.forRun(saved, link: link, hasFeedback: false, now: ended.addingTimeInterval(71 * 3600)),
                       .willReview(coach: "Dana"))
        XCTAssertEqual(CoachReviewLine.forRun(saved, link: link, hasFeedback: false, now: ended.addingTimeInterval(73 * 3600)),
                       .shared(coach: "Dana"))
        XCTAssertEqual(CoachReviewLine.willReview(coach: "Dana").text, "Dana will review this run")
        XCTAssertEqual(CoachReviewLine.shared(coach: "Dana").text, "Shared with Dana")
    }

    func testFeedbackReplacesThePendingLine() async {
        let ended = linkedAt.addingTimeInterval(86_400)
        let saved = run(endedAt: ended)
        let service = MockAthleteFeedbackService()
        let store = store(service)
        await store.load()
        XCTAssertEqual(store.reviewLine(for: saved, link: link, now: ended.addingTimeInterval(80 * 3600)), .shared(coach: "Dana"))
        service.set([note(on: saved, created: ended.addingTimeInterval(81 * 3600))])
        await store.load()
        XCTAssertNil(store.reviewLine(for: saved, link: link, now: ended.addingTimeInterval(82 * 3600)))
    }

    func testNoPendingLineForImportedPreLinkOrUnlinkedRuns() {
        let after = linkedAt.addingTimeInterval(86_400)
        XCTAssertNil(CoachReviewLine.forRun(run(endedAt: after, source: .healthKit), link: link, hasFeedback: false, now: after))
        XCTAssertNil(CoachReviewLine.forRun(run(endedAt: after, source: .garmin), link: link, hasFeedback: false, now: after))
        XCTAssertNil(CoachReviewLine.forRun(run(endedAt: after, providerID: "strava-1"), link: link, hasFeedback: false, now: after))
        XCTAssertNil(CoachReviewLine.forRun(run(endedAt: linkedAt.addingTimeInterval(-60)), link: link, hasFeedback: false, now: after))
        XCTAssertNil(CoachReviewLine.forRun(run(endedAt: after), link: nil, hasFeedback: false, now: after), "none after leaving")
    }

    func testAfterLeavingNotesStayReadableWithNoBadge() async {
        let ended = linkedAt.addingTimeInterval(86_400)
        let saved = run(endedAt: ended)
        let unread = note(on: saved, created: ended.addingTimeInterval(3600))
        let store = store(MockAthleteFeedbackService(rows: [unread]))
        await store.load()
        // Left the coach: no link.
        XCTAssertEqual(store.notes(for: saved).first?.coachName, "Dana", "still on its run with the original name")
        XCTAssertEqual(store.unreadCount(link: nil), 0, "unread at the moment of leaving shows no badge")
        XCTAssertTrue(store.currentNotes(link: nil).isEmpty, "no Feedback row")
        XCTAssertNil(store.reviewLine(for: run(endedAt: ended), link: nil, now: ended))
        // Rejoining later doesn't bring the old unread note back as a badge.
        let rejoined = CoachLink(id: UUID(), coachID: coach, coachName: "Dana", consentedAt: ended.addingTimeInterval(7200))
        XCTAssertEqual(store.unreadCount(link: rejoined), 0)
    }

    func testCachedNotesShowOfflineAndBelongToTheirAthlete() async {
        let cached = note(week: "2026-11-16", created: linkedAt)
        let first = store(MockAthleteFeedbackService(rows: [cached]))
        await first.load()

        let offlineService = MockAthleteFeedbackService()
        offlineService.failure = URLError(.notConnectedToInternet)
        let offline = store(offlineService)
        XCTAssertEqual(offline.notes.map(\.id), [cached.id], "shown before the network answers")
        await offline.load()
        XCTAssertEqual(offline.loadState, .failed)
        XCTAssertEqual(offline.notes.map(\.id), [cached.id], "kept when the load fails")

        offline.beginSession(userID: UUID())
        XCTAssertTrue(offline.notes.isEmpty, "another athlete on this phone sees nothing")
    }

    func testHeaderSpokenTextAndCopy() {
        let date = ISO8601DateFormatter().date(from: "2026-11-12T09:00:00Z")!
        let plain = note(week: "2026-11-09", created: date)
        let edited = note(week: "2026-11-09", created: date, edited: date)
        let gb = Locale(identifier: "en_GB")
        let utc = TimeZone(identifier: "UTC")!
        let header = AthleteFeedbackFormat.header(plain, locale: gb, timeZone: utc)
            .replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        XCTAssertEqual(header, "Dana · 12 Nov")
        XCTAssertEqual(AthleteFeedbackFormat.spoken(plain, locale: gb, timeZone: utc), "Feedback from Dana, 12 November")
        XCTAssertEqual(AthleteFeedbackFormat.spoken(edited, locale: gb, timeZone: utc), "Feedback from Dana, 12 November, edited")
        XCTAssertEqual(AthleteFeedbackCopy.loadFailed("Dana"), "Couldn't load Dana's note.")
    }

    func testDecodesTheServerRow() throws {
        let json = """
        {"id":"\(UUID())","coach_id":"\(coach)","coach_name":"Dana","run_id":101,
         "run_source_provider":"runsmart_ios","run_source_activity_id":"\(UUID())","week_start":null,
         "text":"כל הכבוד","created_at":"2026-11-18T07:00:00.123+00:00","edited_at":null,"read_at":null}
        """
        let decoded = try JSONDecoder().decode(AthleteFeedbackNote.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.coachName, "Dana")
        XCTAssertTrue(decoded.isRunNote)
        XCTAssertNil(decoded.readAt)
        XCTAssertEqual(decoded.text, "כל הכבוד")
    }
}
