import XCTest
@testable import IOS_RunSmart_app

/// Story 3.3: the coach is visible on Today and the Plan while linked, and nothing
/// coach-related renders without an active link. "Coach" is the human coach.
@MainActor
final class CoachPresenceTests: XCTestCase {
    private let coachID = UUID()
    private let athlete = UUID()
    private let linkedAt = ISO8601DateFormatter().date(from: "2026-11-10T08:00:00Z")!

    private nonisolated final class StubMyCoach: MyCoachFetching, @unchecked Sendable {
        var result: Result<MyCoach?, Error>
        private(set) var calls = 0
        init(_ result: Result<MyCoach?, Error>) { self.result = result }
        func myCoach() async throws -> MyCoach? {
            calls += 1
            return try result.get()
        }
    }

    private nonisolated final class StubLinks: CoachLinkRepository, @unchecked Sendable {
        var link: CoachLink?
        init(link: CoachLink?) { self.link = link }
        func currentLink() async throws -> CoachLink? { link }
        func lookupInvite(code: String) async throws -> CoachLookup? { nil }
        func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
            throw CoachLinkServiceError.invalidCode
        }
        func leaveCoach(linkID: UUID) async throws { link = nil }
    }

    private var link: CoachLink {
        CoachLink(id: UUID(), coachID: coachID, coachName: "Dana", consentedAt: linkedAt)
    }

    private func presence(mode: CoachPlanMode?, for id: UUID? = nil) -> (CoachPresence, StubMyCoach) {
        let stub = StubMyCoach(.success(MyCoach(coachID: id ?? coachID, displayName: "Dana", planMode: mode)))
        return (CoachPresence(fetcher: stub), stub)
    }

    private func note(run: RecordedRun? = nil, week: String? = nil, minutesAfterLink: Double,
                      read: Date? = nil, coach: UUID? = nil, kind: AthleteFeedbackNote.Kind = .note, text: String = "Lovely steady pace.") -> AthleteFeedbackNote {
        AthleteFeedbackNote(
            id: UUID(), coachID: coach ?? coachID, coachName: "Dana",
            runID: run == nil ? nil : 101,
            runSourceProvider: run?.runSourceKey.sourceProvider, runSourceActivityID: run?.runSourceKey.sourceActivityID,
            weekStart: week, text: text, createdAt: linkedAt.addingTimeInterval(minutesAfterLink * 60), readAt: read, kind: kind
        )
    }

    /// Saturday 14 Nov 2026, 07:00 UTC.
    private func saturdayRun() -> RecordedRun {
        let start = ISO8601DateFormatter().date(from: "2026-11-14T07:00:00Z")!
        return RecordedRun(
            id: UUID(), providerActivityID: nil, source: .runSmart,
            startedAt: start, endedAt: start.addingTimeInterval(1800),
            distanceMeters: 5000, movingTimeSeconds: 1800, averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil, routePoints: [], syncedAt: nil
        )
    }

    /// Wednesday 18 Nov 2026: inside the week that starts 16 Nov.
    private let today = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func layer(_ coach: CoachLink?, _ notes: [AthleteFeedbackNote],
                       state: AthleteFeedbackStore.LoadState = .loaded, runs: [RecordedRun] = []) -> TodayCoachLayer? {
        TodayCoachLayer.make(coach: coach, notes: notes, loadState: state, runs: runs,
                             calendar: utc, locale: Locale(identifier: "en_US"), now: today)
    }

    private func waitForPresenceDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: Strip

    func testStripShowsWithAnActiveLink() {
        let (gate, _) = presence(mode: .group)
        gate.apply(link)
        XCTAssertTrue(gate.isActive)
        let today = layer(gate.coach, [])
        XCTAssertEqual(today?.coachName, "Dana")
        XCTAssertEqual(CoachPresenceCopy.coachedBy("Dana"), "Coached by Dana")
        XCTAssertEqual(PlanCoachHeader.make(coach: gate.coach, planMode: .group, goal: "Half marathon")?.coachName, "Dana")
    }

    func testNothingRendersWhenUnlinked() {
        let (gate, stub) = presence(mode: .group)
        gate.apply(nil)
        XCTAssertFalse(gate.isActive)
        XCTAssertNil(layer(gate.coach, [note(week: "2026-11-16", minutesAfterLink: 5)]))
        XCTAssertNil(PlanCoachHeader.make(coach: gate.coach, planMode: .group, goal: "Half marathon"))
        XCTAssertEqual(stub.calls, 0, "No link, no get_my_coach call")
    }

    func testRevokedLinkHidesEverything() async {
        let repository = StubLinks(link: link)
        let store = CoachLinkStore(repository: repository)
        store.beginSession(userID: athlete)
        await store.refresh(userID: athlete)
        let (gate, _) = presence(mode: .individual)
        gate.bind(to: store)
        XCTAssertTrue(gate.isActive)

        // The server revoked the link; the next refresh finds none.
        repository.link = nil
        await store.refresh(userID: athlete)
        await waitForPresenceDelivery()
        XCTAssertFalse(gate.isActive)
        XCTAssertNil(gate.planMode)
        XCTAssertNil(layer(gate.coach, [note(week: "2026-11-16", minutesAfterLink: 5)]))
    }

    func testLeaveClearsPresenceAfterLinkStoreCommits() async throws {
        let originalLink = link
        let store = CoachLinkStore(repository: StubLinks(link: originalLink))
        store.beginSession(userID: athlete)
        await store.refresh(userID: athlete)
        let (gate, _) = presence(mode: .individual)
        gate.bind(to: store)
        await gate.waitForPlanMode()
        XCTAssertEqual(gate.coach, originalLink)

        let cleared = expectation(description: "Coach presence cleared after leaving")
        let observation = gate.$coach.dropFirst().sink { coach in
            guard coach == nil else { return }
            XCTAssertNil(store.currentLink, "Presence must read the committed link")
            cleared.fulfill()
        }
        defer { observation.cancel() }

        try await store.leave(userID: athlete, expectedLinkID: originalLink.id)
        await fulfillment(of: [cleared], timeout: 2)
        XCTAssertNil(gate.coach)
        XCTAssertNil(gate.planMode)
    }

    func testQueuedLinkDoesNotRestorePresenceAfterASessionChange() async {
        let originalLink = link
        let store = CoachLinkStore(repository: StubLinks(link: originalLink))
        store.beginSession(userID: athlete)
        let (gate, _) = presence(mode: .individual)
        gate.bind(to: store)

        let observation = gate.$coach.dropFirst().sink { coach in
            if coach != nil {
                XCTAssertEqual(coach, store.currentLink, "Presence cannot resurrect a cleared link")
            }
        }
        defer { observation.cancel() }

        await store.refresh(userID: athlete)
        store.beginSession(userID: UUID())
        await waitForPresenceDelivery()

        XCTAssertNil(gate.coach)
        XCTAssertNil(gate.planMode)
    }

    // MARK: Plan titles

    func testGroupAndIndividualTitles() async {
        let (group, _) = presence(mode: .group)
        group.apply(link)
        await group.waitForPlanMode()
        XCTAssertEqual(group.planMode, .group)
        let groupHeader = PlanCoachHeader.make(coach: group.coach, planMode: group.planMode, goal: " Half marathon ")
        XCTAssertEqual(groupHeader?.titleText, "Dana's plan: Half marathon")
        XCTAssertNil(groupHeader?.sublineText)

        let (individual, _) = presence(mode: .individual)
        individual.apply(link)
        await individual.waitForPlanMode()
        let individualHeader = PlanCoachHeader.make(coach: individual.coach, planMode: individual.planMode, goal: "10K")
        XCTAssertEqual(individualHeader?.titleText, "Dana's plan for you")
        XCTAssertEqual(individualHeader?.sublineText, "RunSmart builds it, Dana supervises it")
    }

    func testGroupWithoutAGoalAndUnknownModeFallBack() {
        XCTAssertEqual(PlanCoachHeader.make(coach: link, planMode: .group, goal: nil)?.titleText, "Dana's plan")
        let unknown = PlanCoachHeader.make(coach: link, planMode: nil, goal: "10K")
        XCTAssertNotNil(unknown, "The strip still shows")
        XCTAssertNil(unknown?.titleText, "Unknown Plan Mode keeps the solo title")
        // Story 4.4 case exists and is not produced yet.
        XCTAssertEqual(PlanCoachHeader(coachName: "Dana", title: .customGoal(goal: "10K")).titleText,
                       "Dana's plan for you: 10K")
    }

    func testPlanModeFromAnotherCoachIsIgnored() async {
        let (gate, _) = presence(mode: .group, for: UUID())
        gate.apply(link)
        await gate.waitForPlanMode()
        XCTAssertTrue(gate.isActive)
        XCTAssertNil(gate.planMode)
    }

    func testFailedPlanModeReadKeepsTheStrip() async {
        let stub = StubMyCoach(.failure(URLError(.notConnectedToInternet)))
        let gate = CoachPresence(fetcher: stub)
        gate.apply(link)
        await gate.waitForPlanMode()
        XCTAssertTrue(gate.isActive)
        XCTAssertNil(gate.planMode)
    }

    func testFailedPlanModeReadRetriesOnTheNextRefreshOfTheSameLink() async {
        let repository = StubLinks(link: link)
        let store = CoachLinkStore(repository: repository)
        store.beginSession(userID: athlete)
        await store.refresh(userID: athlete)
        let stub = StubMyCoach(.failure(URLError(.notConnectedToInternet)))
        let gate = CoachPresence(fetcher: stub)
        gate.bind(to: store)
        await gate.waitForPlanMode()
        XCTAssertNil(gate.planMode)

        // Back online: the foreground refresh returns the same link.
        stub.result = .success(MyCoach(coachID: coachID, displayName: "Dana", planMode: .individual))
        await store.refresh(userID: athlete)
        await waitForPresenceDelivery()
        await gate.waitForPlanMode()
        XCTAssertEqual(gate.planMode, .individual)
        XCTAssertEqual(stub.calls, 2)

        // Resolved: a further refresh of the same link doesn't ask again.
        await store.refresh(userID: athlete)
        await waitForPresenceDelivery()
        await gate.waitForPlanMode()
        XCTAssertEqual(stub.calls, 2)
    }

    // MARK: Cards

    func testCardsNewestFirstCappedAtTwoWithMoreRow() {
        let run = saturdayRun()
        let oldest = note(week: "2026-11-09", minutesAfterLink: 1)
        let middle = note(run: run, minutesAfterLink: 2)
        let newest = note(week: "2026-11-16", minutesAfterLink: 3)
        let read = note(week: "2026-11-02", minutesAfterLink: 4, read: linkedAt)
        let beforeLink = note(week: "2026-11-02", minutesAfterLink: -60)
        let otherCoach = note(week: "2026-11-02", minutesAfterLink: 5, coach: UUID())

        let today = layer(link, [oldest, middle, newest, read, beforeLink, otherCoach], runs: [run])
        XCTAssertEqual(today?.cards.map(\.id), [newest.id, middle.id])
        XCTAssertEqual(today?.cards.map(\.title), ["Dana's note for this week", "Dana on your Saturday run"])
        XCTAssertEqual(today?.moreCount, 1)
        XCTAssertEqual(CoachPresenceCopy.more(2, coach: "Dana"), "2 more from Dana")
    }

    func testAnOlderWeekNoteNamesItsWeekInsteadOfThisWeek() {
        let older = note(week: "2026-11-09", minutesAfterLink: 1)
        let current = note(week: "2026-11-16", minutesAfterLink: 2)
        let today = layer(link, [older, current])
        XCTAssertEqual(today?.cards.map(\.title),
                       ["Dana's note for this week", "Dana's note for the week of Nov 9"])
    }

    func testRunNotOnThisPhoneStillTitlesTheCard() {
        let today = layer(link, [note(run: saturdayRun(), minutesAfterLink: 1)], runs: [])
        XCTAssertEqual(today?.cards.first?.title, "Dana on your run")
        XCTAssertEqual(today?.moreCount, 0)
    }

    func testQuietCoachShowsTheStripOnly() {
        let today = layer(link, [note(week: "2026-11-16", minutesAfterLink: 1, read: linkedAt)])
        XCTAssertNotNil(today)
        XCTAssertEqual(today?.cards, [])
        XCTAssertEqual(today?.moreCount, 0)
        XCTAssertEqual(today?.status, .ready)
    }

    func testLoadingShowsASkeletonOnlyWithNothingCached() {
        XCTAssertEqual(layer(link, [], state: .loading)?.status, .loading)
        let cached = note(week: "2026-11-16", minutesAfterLink: 1)
        let refreshing = layer(link, [cached], state: .loading)
        XCTAssertEqual(refreshing?.status, .ready)
        XCTAssertEqual(refreshing?.cards.count, 1)
    }

    func testErrorRow() {
        let failed = layer(link, [], state: .failed)
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertEqual(failed?.cards, [])
        XCTAssertEqual(CoachPresenceCopy.refreshFailed("Dana"), "Couldn't refresh Dana's updates")
    }

    // MARK: Read

    func testReadOpensTheRunOrWeekAndMarksRead() async {
        let run = saturdayRun()
        let runNote = note(run: run, minutesAfterLink: 2)
        let weekNote = note(week: "2026-11-16", minutesAfterLink: 1)
        XCTAssertEqual(CoachNoteDestination.of(runNote, calendar: utc), .run)
        XCTAssertEqual(CoachNoteDestination.of(weekNote, calendar: utc),
                       .week(weekNote.weekStartDate(calendar: utc)))

        let service = MockAthleteFeedbackService(rows: [runNote, weekNote])
        let suite = "CoachPresenceTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = AthleteFeedbackStore(service: service, cache: AthleteFeedbackCache(defaults: UserDefaults(suiteName: suite)!),
                                         currentUserID: { [athlete] in athlete })
        store.beginSession(userID: athlete)
        await store.load()
        XCTAssertEqual(layer(link, store.notes, runs: [run])?.cards.first?.id, runNote.id)

        await store.markRead([runNote])
        XCTAssertEqual(service.markReadCalls, [runNote.id])
        let after = layer(link, store.notes, runs: [run])
        XCTAssertEqual(after?.cards.map(\.id), [weekNote.id], "The read card leaves Today")
    }

    func testWelcomeIsSignedAndPinnedWithinCapUntilRead() async {
        let coach = link
        let welcome = note(minutesAfterLink: 1, kind: .welcome, text: "שלום יוני")
        let newer = note(week: "2026-11-16", minutesAfterLink: 2)
        let newest = note(week: "2026-11-16", minutesAfterLink: 3)
        let service = MockAthleteFeedbackService(rows: [welcome, newer, newest])
        let suite = "CoachWelcomeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AthleteFeedbackStore(service: service, cache: AthleteFeedbackCache(defaults: defaults),
                                         currentUserID: { [athlete] in athlete })
        store.beginSession(userID: athlete)
        await store.load()

        let before = layer(coach, store.notes)
        XCTAssertEqual(before?.cards.map(\.id), [welcome.id, newest.id])
        XCTAssertEqual(before?.cards.first?.title, "Welcome from Dana")
        XCTAssertEqual(before?.cards.first?.note.text, "שלום יוני")
        XCTAssertEqual(before?.moreCount, 1)
        XCTAssertEqual(CoachNoteDestination.of(welcome), .welcome)
        XCTAssertTrue(store.notes(for: saturdayRun()).isEmpty)

        await store.markRead([welcome])
        XCTAssertEqual(service.markReadCalls, [welcome.id])
        XCTAssertEqual(layer(coach, store.notes)?.cards.map(\.id), [newest.id, newer.id])
        XCTAssertEqual(layer(coach, [])?.cards, [])
    }

    // MARK: Leaving

    func testAfterLeavingNothingCoachRelatedRenders() async throws {
        let repository = StubLinks(link: link)
        let store = CoachLinkStore(repository: repository)
        store.beginSession(userID: athlete)
        await store.refresh(userID: athlete)
        let (gate, _) = presence(mode: .group)
        gate.bind(to: store)
        await gate.waitForPlanMode()
        XCTAssertEqual(PlanCoachHeader.make(coach: gate.coach, planMode: gate.planMode, goal: "10K")?.titleText,
                       "Dana's plan: 10K")

        try await store.leave(userID: athlete)
        await waitForPresenceDelivery()
        XCTAssertFalse(gate.isActive)
        XCTAssertNil(gate.planMode)
        let unread = note(week: "2026-11-16", minutesAfterLink: 1)
        XCTAssertNil(layer(gate.coach, [unread]), "No strip and no card")
        XCTAssertNil(PlanCoachHeader.make(coach: gate.coach, planMode: gate.planMode, goal: "10K"), "Solo title")
        XCTAssertFalse(CoachLayerHooks.showsPlanUpdateCard(gate))
        XCTAssertFalse(CoachLayerHooks.showsPraiseCard(gate))
        XCTAssertNil(CoachLayerHooks.editedByLabel(gate, workout: RunSmartPreviewData.workouts[0]))
    }
}
