import XCTest
@testable import IOS_RunSmart_app

/// C7.11: the coach removes an athlete, the athlete sees one neutral line once, and both
/// link ends send their v2 analytics event with no properties.
@MainActor
final class CoachLinkEndTests: XCTestCase {
    private nonisolated final class SpyAnalytics: AnalyticsTracking, @unchecked Sendable {
        var events: [(name: String, properties: [String: Any])] = []
        func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func unregister(_ key: String) {}
        func reset() {}
        var names: [String] { events.map(\.name) }
    }

    private nonisolated final class StubLinkEnd: CoachLinkEndServing, @unchecked Sendable {
        var removeResult: Result<CoachRemoveOutcome, Error> = .success(.removed)
        var notice: CoachLinkNotice?
        var markError: Error?
        private(set) var removed: [UUID] = []
        private(set) var noticeReads = 0
        private(set) var marked: [UUID] = []

        func removeAthlete(_ athleteID: UUID) async throws -> CoachRemoveOutcome {
            removed.append(athleteID)
            return try removeResult.get()
        }

        func linkNotice() async throws -> CoachLinkNotice? {
            noticeReads += 1
            return notice
        }

        func markLinkNoticeSeen(linkID: UUID) async throws {
            marked.append(linkID)
            if let markError { throw markError }
        }
    }

    private final class StubLinks: CoachLinkRepository, @unchecked Sendable {
        var link: CoachLink?
        func currentLink() async throws -> CoachLink? { link }
        func lookupInvite(code: String) async throws -> CoachLookup? { nil }
        func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
            throw CoachLinkServiceError.invalidCode
        }
        func leaveCoach(linkID: UUID) async throws { link = nil }
    }

    private let athleteID = UUID()
    private let dana = CoachLinkNotice(linkID: UUID(), coachName: "Dana")

    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
    }

    // MARK: Copy

    func testAthleteNoticeIsTheSpecLine() {
        XCTAssertEqual(plain(CoachRemovalCopy.notice(coach: "Dana")),
                       "You're no longer coached by Dana. Your plan stays and RunSmart keeps adapting it.")
        XCTAssertEqual(CoachRemovalCopy.notice(coach: "דנה"),
                       "You're no longer coached by \u{2068}דנה\u{2069}. Your plan stays and RunSmart keeps adapting it.")
    }

    func testRemoveSheetListsTheEffects() {
        XCTAssertEqual(plain(CoachRemovalCopy.menuItem(athlete: "Bea")), "Remove Bea")
        XCTAssertEqual(plain(CoachRemovalCopy.title(athlete: "Bea")), "Remove Bea?")
        let sheet = plain(CoachRemovalCopy.sheet(athlete: "Bea"))
        for line in [
            "Bea will no longer be coached by you.",
            "• You won't see Bea's plan, runs or maps.",
            "• You won't see Bea's effort, notes or flags.",
            "• You can't review Bea's runs, send feedback or change their workouts.",
            "• Bea's plan, which RunSmart keeps adapting.",
            "• Feedback you already gave. Bea can still read it.",
            "Bea sees one line in the app. No notification is sent.",
            "Bea can join you again with your code."
        ] {
            XCTAssertTrue(sheet.contains(line), "missing: \(line)")
        }
        XCTAssertEqual(plain(CoachRemovalCopy.failure(athlete: "Bea")),
                       "Couldn't remove Bea right now. Bea is still linked. Try again.")
    }

    func testCopyHasNoEmDashAndNoBareNames() {
        let all = [CoachRemovalCopy.notice(coach: "יוני"), CoachRemovalCopy.menuItem(athlete: "יוני"),
                   CoachRemovalCopy.title(athlete: "יוני"), CoachRemovalCopy.sheet(athlete: "יוני"),
                   CoachRemovalCopy.failure(athlete: "יוני")]
        for text in all {
            XCTAssertFalse(text.contains("\u{2014}"), text)
            XCTAssertFalse(text.replacingOccurrences(of: "\u{2068}יוני\u{2069}", with: "").contains("יוני"),
                           "every name is isolated: \(text)")
        }
    }

    // MARK: Coach removes

    func testConfirmRemovesTracksAndReturnsTrue() async {
        let service = StubLinkEnd()
        let spy = SpyAnalytics()
        let model = RemoveAthleteModel(service: service, analytics: { spy })

        let done = await model.confirm(athleteID: athleteID, athleteName: "Bea")

        XCTAssertTrue(done)
        XCTAssertEqual(service.removed, [athleteID])
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(spy.names, ["coach_removed_athlete"])
        XCTAssertTrue(spy.events[0].properties.isEmpty)
    }

    func testAlreadyEndedCountsAsDoneWithoutASecondEvent() async {
        let service = StubLinkEnd()
        service.removeResult = .success(.alreadyEnded)
        let spy = SpyAnalytics()
        let model = RemoveAthleteModel(service: service, analytics: { spy })

        let done = await model.confirm(athleteID: athleteID, athleteName: "Bea")

        XCTAssertTrue(done)
        XCTAssertTrue(spy.names.isEmpty)
    }

    func testFailedRemoveKeepsTheSheetWithTheError() async {
        let service = StubLinkEnd()
        service.removeResult = .failure(URLError(.timedOut))
        let spy = SpyAnalytics()
        let model = RemoveAthleteModel(service: service, analytics: { spy })

        let done = await model.confirm(athleteID: athleteID, athleteName: "Bea")

        XCTAssertFalse(done)
        XCTAssertEqual(plain(model.errorMessage ?? ""), "Couldn't remove Bea right now. Bea is still linked. Try again.")
        XCTAssertTrue(spy.names.isEmpty)
        model.cancel()
        XCTAssertNil(model.errorMessage)
    }

    func testOfflineDoesNotCallTheServer() async {
        let service = StubLinkEnd()
        let model = RemoveAthleteModel(isOnline: false, service: service, analytics: { SpyAnalytics() })

        let done = await model.confirm(athleteID: athleteID, athleteName: "Bea")

        XCTAssertFalse(done)
        XCTAssertTrue(service.removed.isEmpty)
        XCTAssertEqual(model.errorMessage, "Connect to the internet")
    }

    func testCancelCallsNothing() {
        let service = StubLinkEnd()
        let model = RemoveAthleteModel(service: service, analytics: { SpyAnalytics() })
        model.cancel()
        XCTAssertTrue(service.removed.isEmpty)
    }

    // MARK: Athlete notice

    func testFlagOffNeverReadsTheNotice() async {
        let service = StubLinkEnd()
        service.notice = dana
        let model = CoachLinkNoticeModel(service: service)

        await model.evaluate(v2Enabled: false, userID: UUID(), noLink: true)

        XCTAssertNil(model.notice)
        XCTAssertEqual(service.noticeReads, 0)
    }

    func testLinkedOrUnknownLinkNeverReadsTheNotice() async {
        let service = StubLinkEnd()
        service.notice = dana
        let model = CoachLinkNoticeModel(service: service)

        await model.evaluate(v2Enabled: true, userID: UUID(), noLink: false)
        await model.evaluate(v2Enabled: true, userID: nil, noLink: true)

        XCTAssertNil(model.notice)
        XCTAssertEqual(service.noticeReads, 0)
    }

    func testRemovedAthleteSeesTheLineOnce() async {
        let service = StubLinkEnd()
        service.notice = dana
        let model = CoachLinkNoticeModel(service: service)
        let user = UUID()

        await model.evaluate(v2Enabled: true, userID: user, noLink: true)
        XCTAssertEqual(model.notice, dana)

        await model.shown()
        await model.shown()
        XCTAssertEqual(service.marked, [dana.linkID], "marked once")

        model.dismiss()
        XCTAssertNil(model.notice)
        // A stale server answer (the mark raced the read) never shows the same line twice.
        await model.evaluate(v2Enabled: true, userID: user, noLink: true)
        XCTAssertNil(model.notice)
    }

    func testFailedMarkShowsTheLineAgainNextTime() async {
        let service = StubLinkEnd()
        service.notice = dana
        service.markError = URLError(.notConnectedToInternet)
        let model = CoachLinkNoticeModel(service: service)
        let user = UUID()

        await model.evaluate(v2Enabled: true, userID: user, noLink: true)
        await model.shown()
        model.dismiss()

        service.markError = nil
        await model.evaluate(v2Enabled: true, userID: user, noLink: true)
        XCTAssertEqual(model.notice, dana)
        await model.shown()
        XCTAssertEqual(service.marked, [dana.linkID, dana.linkID])
    }

    func testFlagTurningOffHidesTheLine() async {
        let service = StubLinkEnd()
        service.notice = dana
        let model = CoachLinkNoticeModel(service: service)
        let user = UUID()

        await model.evaluate(v2Enabled: true, userID: user, noLink: true)
        await model.evaluate(v2Enabled: false, userID: user, noLink: true)

        XCTAssertNil(model.notice)
    }

    func testAnotherUserStartsClean() async {
        let service = StubLinkEnd()
        service.notice = dana
        let model = CoachLinkNoticeModel(service: service)

        await model.evaluate(v2Enabled: true, userID: UUID(), noLink: true)
        await model.shown()
        await model.evaluate(v2Enabled: true, userID: UUID(), noLink: true)

        XCTAssertEqual(model.notice, dana, "the marked set belongs to the first user")
    }

    // MARK: Athlete leaves

    private func linkedStore() -> (CoachLinkStore, UUID) {
        let link = CoachLink(id: UUID(), coachID: UUID(), coachName: "Dana", consentedAt: Date())
        let repository = StubLinks()
        repository.link = link
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(link, userID: userID)
        return (store, userID)
    }

    func testLeaveSendsAthleteLeftCoachWhileV2IsOn() async {
        let (store, userID) = linkedStore()
        let spy = SpyAnalytics()
        let model = LeaveCoachModel(coachV2Enabled: { true }, analytics: { spy })

        let toast = await model.confirm(coachName: "Dana", userID: userID, store: store)

        XCTAssertNotNil(toast)
        XCTAssertEqual(spy.names, ["athlete_left_coach"])
        XCTAssertTrue(spy.events[0].properties.isEmpty)
    }

    func testLeaveWithV2OffSendsNoV2Event() async {
        let (store, userID) = linkedStore()
        let spy = SpyAnalytics()
        let model = LeaveCoachModel(coachV2Enabled: { false }, analytics: { spy })

        let toast = await model.confirm(coachName: "Dana", userID: userID, store: store)

        XCTAssertNotNil(toast)
        XCTAssertTrue(spy.names.isEmpty)
    }

    func testEventNames() {
        XCTAssertEqual(CoachV2Analytics.Event.coachRemovedAthlete.name, "coach_removed_athlete")
        XCTAssertEqual(CoachV2Analytics.Event.athleteLeftCoach.name, "athlete_left_coach")
        XCTAssertTrue(CoachV2Analytics.Event.coachRemovedAthlete.properties.isEmpty)
        XCTAssertTrue(CoachV2Analytics.Event.athleteLeftCoach.properties.isEmpty)
    }
}
