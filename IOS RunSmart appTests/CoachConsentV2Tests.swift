import XCTest
@testable import IOS_RunSmart_app

/// C7.8: consent v2 (P8 at join), the one-time P9 notice on Today, the leave sheet's v2
/// lines, and the C7.8 analytics events. "Coach" is the human coach, not the AI coach.

private struct Offline: Error {}

private nonisolated final class SpyAnalytics: AnalyticsTracking, @unchecked Sendable {
    var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}

    var names: [String] { events.map(\.name) }
    func surfaces(_ name: String) -> [String] {
        events.filter { $0.name == name }.compactMap { $0.properties["surface"] as? String }
    }
}

private final class StubConsentRepository: CoachConsentRepository, @unchecked Sendable {
    var status: Result<CoachConsentStatus?, Error> = .success(nil)
    var ackResult: Result<Void, Error> = .success(())
    private(set) var statusCalls = 0
    private(set) var ackCalls = 0

    func status() async throws -> CoachConsentStatus? {
        statusCalls += 1
        return try status.get()
    }

    func acknowledge() async throws {
        ackCalls += 1
        try ackResult.get()
    }

    nonisolated deinit {}
}

private final class StubLinkRepository: CoachLinkRepository, @unchecked Sendable {
    var lookup: CoachLookup?
    var consentVersion: Result<Int, Error> = .success(1)
    var outcome: JoinCoachOutcome
    private(set) var versionCalls = 0
    private(set) var joinV1Calls = 0
    private(set) var joinV2Versions: [Int] = []

    init(outcome: JoinCoachOutcome) {
        self.outcome = outcome
    }

    func currentLink() async throws -> CoachLink? { nil }

    func lookupInvite(code: String) async throws -> CoachLookup? {
        guard let lookup else { return nil }
        return CoachLookup(inviteID: lookup.inviteID, coachID: lookup.coachID, displayName: lookup.displayName,
                           code: code, planMode: lookup.planMode, groupPlan: lookup.groupPlan)
    }

    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
        joinV1Calls += 1
        return outcome
    }

    func leaveCoach(linkID: UUID) async throws {}

    func inviteConsentVersion(code: String) async throws -> Int {
        versionCalls += 1
        return try consentVersion.get()
    }

    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID,
                   consentVersion: Int) async throws -> JoinCoachOutcome {
        joinV2Versions.append(consentVersion)
        return outcome
    }

    nonisolated deinit {}
}

@MainActor
final class CoachConsentNoticeTests: XCTestCase {
    private let userID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let linkID = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let otherLink = UUID(uuidString: "22222222-0000-4000-8000-000000000002")!

    private func status(needsAck: Bool, link: UUID? = nil, isV2: Bool = true) -> CoachConsentStatus {
        CoachConsentStatus(linkID: link ?? linkID, coachName: "Dana", linkIsV2: isV2,
                           needsV2Ack: needsAck, sharingActive: isV2 && !needsAck)
    }

    private func makeModel(_ repository: StubConsentRepository, _ spy: SpyAnalytics) -> CoachConsentNoticeModel {
        CoachConsentNoticeModel(repository: repository, analytics: { spy })
    }

    // Flag-off AC: no v2 call, no sheet, no event.
    func testFlagOffMakesNoCallAndShowsNothing() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let spy = SpyAnalytics()
        let model = makeModel(repository, spy)

        await model.evaluate(v2Enabled: false, userID: userID, linkID: linkID)

        XCTAssertNil(model.notice)
        XCTAssertEqual(repository.statusCalls, 0)
        XCTAssertEqual(repository.ackCalls, 0)
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testNoLinkOrSignedOutMakesNoCall() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let model = makeModel(repository, SpyAnalytics())

        await model.evaluate(v2Enabled: true, userID: userID, linkID: nil)
        await model.evaluate(v2Enabled: true, userID: nil, linkID: linkID)

        XCTAssertNil(model.notice)
        XCTAssertEqual(repository.statusCalls, 0)
    }

    // AC3: a v1 link on a v2 pair shows P9 once, and counts it as shown.
    func testShowsP9WhenTheServerSaysTheAthleteNeedsIt() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let spy = SpyAnalytics()
        let model = makeModel(repository, spy)

        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertEqual(model.notice, CoachConsentNotice(linkID: linkID, coachName: "Dana"))

        // Today re-appears while P9 is up: no second read, no second "shown".
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertEqual(repository.statusCalls, 1)
        XCTAssertEqual(spy.names, ["consent_v2_shown"])
        XCTAssertEqual(spy.surfaces("consent_v2_shown"), ["notice"])
    }

    // AC5 + AC7: the server says no (already acked, coach not v2, kill switch): hidden.
    func testHidesP9WhenTheServerSaysNo() async {
        for answer in [status(needsAck: false), status(needsAck: false, isV2: false)] {
            let repository = StubConsentRepository()
            repository.status = .success(answer)
            let spy = SpyAnalytics()
            let model = makeModel(repository, spy)

            await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

            XCTAssertNil(model.notice)
            XCTAssertTrue(spy.events.isEmpty)
        }
    }

    func testIgnoresAStatusForADifferentLinkOrNoLink() async {
        for answer in [status(needsAck: true, link: otherLink), nil] {
            let repository = StubConsentRepository()
            repository.status = .success(answer)
            let model = makeModel(repository, SpyAnalytics())

            await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

            XCTAssertNil(model.notice)
        }
    }

    // P8/P9 offline state: the notice waits for a connection.
    func testOfflineStatusReadShowsNothing() async {
        let repository = StubConsentRepository()
        repository.status = .failure(Offline())
        let model = makeModel(repository, SpyAnalytics())

        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

        XCTAssertNil(model.notice)
        repository.status = .success(status(needsAck: true))
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNotNil(model.notice)
    }

    func testOKAcknowledgesAndHidesP9() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let spy = SpyAnalytics()
        let model = makeModel(repository, spy)
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

        let recorded = await model.acknowledge()

        XCTAssertTrue(recorded)
        XCTAssertEqual(repository.ackCalls, 1)
        XCTAssertNil(model.notice)
        XCTAssertEqual(spy.names, ["consent_v2_shown", "consent_v2_acked"])
        XCTAssertEqual(spy.surfaces("consent_v2_acked"), ["notice"])
    }

    // AC4: the ack fails, P9 goes away for now and shows again on the next open.
    func testAckFailureShowsP9AgainOnTheNextOpen() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        repository.ackResult = .failure(Offline())
        let spy = SpyAnalytics()
        let model = makeModel(repository, spy)
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

        let recorded = await model.acknowledge()

        XCTAssertFalse(recorded)
        XCTAssertNil(model.notice)
        XCTAssertFalse(spy.names.contains("consent_v2_acked"))

        // Same foreground: Today re-appearing does not bring it back or re-read.
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNil(model.notice)
        XCTAssertEqual(repository.statusCalls, 1)

        // Next open: the server still says the athlete needs it, so it shows again.
        model.beginForeground()
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(spy.surfaces("consent_v2_shown"), ["notice", "notice"])
    }

    func testSwipeAwayShowsAgainOnTheNextOpen() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let model = makeModel(repository, SpyAnalytics())
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

        model.dismissForNow()
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNil(model.notice)

        model.beginForeground()
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(repository.ackCalls, 0)
    }

    // AC3: "Leave {Coach}" opens the leave sheet; it is not a leave and not an ack.
    func testLeaveTappedKeepsP9PendingAndCountsTheTap() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let spy = SpyAnalytics()
        let model = makeModel(repository, spy)
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)

        model.leaveTapped()

        XCTAssertNotNil(model.notice)
        XCTAssertEqual(repository.ackCalls, 0)
        XCTAssertEqual(spy.surfaces("consent_v2_leave_tapped"), ["notice"])
    }

    // The athlete left, or v2 turned off (kill switch): P9 goes away.
    func testLinkGoneOrFlagOffHidesP9() async {
        let repository = StubConsentRepository()
        repository.status = .success(status(needsAck: true))
        let model = makeModel(repository, SpyAnalytics())
        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNotNil(model.notice)

        await model.evaluate(v2Enabled: true, userID: userID, linkID: nil)
        XCTAssertNil(model.notice)

        await model.evaluate(v2Enabled: true, userID: userID, linkID: linkID)
        XCTAssertNotNil(model.notice)
        await model.evaluate(v2Enabled: false, userID: userID, linkID: linkID)
        XCTAssertNil(model.notice)
    }
}

@MainActor
final class CoachConsentJoinTests: XCTestCase {
    private let athleteID = UUID()
    private let danaCoach = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let danaInvite = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!

    private var dana: CoachLookup {
        CoachLookup(inviteID: danaInvite, coachID: danaCoach, displayName: "Dana", code: "DANA22")
    }

    private var joined: JoinCoachOutcome {
        .joined(CoachLink(id: UUID(), coachID: danaCoach, coachName: "Dana", consentedAt: Date()))
    }

    private func makeModel(_ repository: StubLinkRepository, v2: Bool, spy: SpyAnalytics) -> JoinCoachViewModel {
        JoinCoachViewModel(code: "DANA22", repository: repository, coachV2Enabled: { v2 }, analytics: { spy })
    }

    private func consentVersion(_ model: JoinCoachViewModel) -> Int? {
        guard case .consent(let coach, _) = model.phase else { return nil }
        return coach.consentVersion
    }

    // AC1 + AC2: a v2 athlete joining a v2 coach sees P8 and joins with version 2.
    func testV2CoachShowsP8AndJoinsWithTheAck() async {
        let repository = StubLinkRepository(outcome: joined)
        repository.lookup = dana
        repository.consentVersion = .success(2)
        let spy = SpyAnalytics()
        let model = makeModel(repository, v2: true, spy: spy)

        await model.continueTapped(athleteID: athleteID)
        XCTAssertEqual(consentVersion(model), 2)
        XCTAssertEqual(spy.surfaces("consent_v2_shown"), ["join"])

        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.joinV2Versions, [2])
        XCTAssertEqual(repository.joinV1Calls, 0)
        XCTAssertNotNil(model.joinedCoach)
        XCTAssertEqual(spy.surfaces("consent_v2_acked"), ["join"])
    }

    // AC7: the coach is not v2, so the A3 copy and Story 1.3's join.
    func testCoachNotV2KeepsTheA3CopyAndTheV1Join() async {
        let repository = StubLinkRepository(outcome: joined)
        repository.lookup = dana
        repository.consentVersion = .success(1)
        let spy = SpyAnalytics()
        let model = makeModel(repository, v2: true, spy: spy)

        await model.continueTapped(athleteID: athleteID)
        XCTAssertEqual(consentVersion(model), 1)
        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.versionCalls, 1)
        XCTAssertEqual(repository.joinV1Calls, 1)
        XCTAssertTrue(repository.joinV2Versions.isEmpty)
        XCTAssertTrue(spy.events.isEmpty)
    }

    // A failed version check falls back to the A3 copy (P9 follows once the link is v2).
    func testVersionCheckFailureFallsBackToA3() async {
        let repository = StubLinkRepository(outcome: joined)
        repository.lookup = dana
        repository.consentVersion = .failure(Offline())
        let model = makeModel(repository, v2: true, spy: SpyAnalytics())

        await model.continueTapped(athleteID: athleteID)
        XCTAssertEqual(consentVersion(model), 1)
        await model.share(athleteID: athleteID)
        XCTAssertEqual(repository.joinV1Calls, 1)
    }

    // Flag-off AC: no v2 RPC, the 1.2.6 join, no event.
    func testFlagOffMakesNoV2Call() async {
        let repository = StubLinkRepository(outcome: joined)
        repository.lookup = dana
        repository.consentVersion = .success(2)
        let spy = SpyAnalytics()
        let model = makeModel(repository, v2: false, spy: spy)

        await model.continueTapped(athleteID: athleteID)
        XCTAssertEqual(model.phase, .consent(dana, athleteID: athleteID))
        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.versionCalls, 0)
        XCTAssertTrue(repository.joinV2Versions.isEmpty)
        XCTAssertEqual(repository.joinV1Calls, 1)
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testAlreadyLinkedV2JoinIsNotCountedAsAnAck() async {
        let repository = StubLinkRepository(outcome: .alreadyLinked(coachName: "Ron"))
        repository.lookup = dana
        repository.consentVersion = .success(2)
        let spy = SpyAnalytics()
        let model = makeModel(repository, v2: true, spy: spy)

        await model.continueTapped(athleteID: athleteID)
        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.joinV2Versions, [2])
        XCTAssertTrue(spy.surfaces("consent_v2_acked").isEmpty)
        XCTAssertEqual(model.errorMessage, CoachConsentCopy.alreadyLinked(coach: "Ron"))
    }
}

@MainActor
final class CoachConsentCopyTests: XCTestCase {
    func testP8IsTheSpecCopyWithTheReadReceiptLine() {
        let body = CoachConsentCopy.v2Body(coach: "Dana")
        let expectedLines = [
            "Dana can see:",
            "• Your training plan",
            "• Your runs: distance, time, pace and average heart rate",
            "• Route maps of runs you record in RunSmart, with the start and end trimmed for privacy",
            "• How hard each run felt (effort 1–10)",
            "• Notes you add to your runs. You can hide any note from Dana.",
            "• Pain or \"something off\" flags you send",
            "Dana can see when you read group messages.",
            "Not shared: your chats with RunSmart, and health data such as sleep or HRV.",
            "If you leave, Dana will no longer see your runs. You keep any feedback Dana has already given you. You can leave anytime in Settings.",
        ]
        for line in expectedLines {
            XCTAssertTrue(body.contains(line), "P8 is missing: \(line)")
        }
        XCTAssertEqual(CoachConsentCopy.title(coach: "Dana"), "Share with Dana?")
    }

    /// The lock sentence follows the A13 rule: only once coach workouts are locked (C8.1a).
    func testP8LockSentenceFollowsTheLockFlag() {
        let body = CoachConsentCopy.v2Body(coach: "Dana")
        XCTAssertTrue(body.contains("Dana can also set and change your upcoming workouts."))
        XCTAssertEqual(body.contains("RunSmart won't change workouts Dana sets."),
                       LeaveCoachCopy.coachWorkoutLocksEnabled)
    }

    func testP9IsTheSpecCopy() {
        XCTAssertEqual(CoachConsentCopy.noticeTitle(coach: "Dana"), "Dana can now see how your runs felt")
        XCTAssertEqual(CoachConsentCopy.noticeBody(coach: "Dana"), """
        From now on, Dana can see:
        • How hard each run felt (effort 1–10)
        • Notes you add to runs. You can hide any note from Dana.
        • Pain or "something off" flags you send

        Dana can see when you read group messages.

        Notes you wrote before today stay on this phone.
        Effort from your last 14 days is shared too.
        """)
        XCTAssertEqual(CoachConsentCopy.noticeOK, "OK")
        XCTAssertEqual(CoachConsentCopy.noticeLeave(coach: "Dana"), "Leave Dana")
    }

    // AC8: the leave sheet adds the effort, notes and flags line and the replies line.
    func testLeaveSheetV2Lines() {
        let sheet = LeaveCoachCopy.sheet(coach: "Dana", includesV2Lines: true)
        XCTAssertTrue(sheet.contains("What stops:\n• Dana won't see your plan, runs or maps.\n• Dana won't see your effort, notes or flags."))
        XCTAssertTrue(sheet.contains("• Your replies to Dana's notes.\n\nYou can join a coach again with a code."))
    }

    // Flag-off AC: without the v2 lines the sheet is the 1.2.6 sheet, word for word.
    func testLeaveSheetWithoutV2LinesIsUnchanged() {
        XCTAssertEqual(LeaveCoachCopy.sheet(coach: "Dana"), """
        Leave Dana?
        If you leave, Dana will no longer see your runs.

        What stops:
        • Dana won't see your plan, runs or maps.
        • Dana won't review your runs or send new feedback.
        • Dana can't change your workouts.
        • Dana's name and notes are removed from your plan.

        What stays:
        • Your plan, which RunSmart keeps adapting.
        • Your run history.
        • Feedback Dana has already given you. You can still read it on the runs it was written for.

        You can join a coach again with a code.
        """)
        XCTAssertFalse(LeaveCoachCopy.sheet(coach: "Dana").contains("effort"))
    }

    func testNoEmDashesInC78Copy() {
        let copy = [
            CoachConsentCopy.v2Body(coach: "Dana"),
            CoachConsentCopy.noticeTitle(coach: "Dana"),
            CoachConsentCopy.noticeBody(coach: "Dana"),
            LeaveCoachCopy.sheet(coach: "Dana", includesV2Lines: true),
        ].joined()
        XCTAssertFalse(copy.contains("\u{2014}"))
    }

    func testEventNamesAndPropertiesCarryOnlyTheSurface() {
        let events: [(CoachV2Analytics.Event, String)] = [
            (.consentV2Shown(surface: .join), "consent_v2_shown"),
            (.consentV2Acked(surface: .notice), "consent_v2_acked"),
            (.consentV2LeaveTapped(surface: .notice), "consent_v2_leave_tapped"),
        ]
        for (event, name) in events {
            XCTAssertEqual(event.name, name)
            XCTAssertEqual(Array(event.properties.keys), ["surface"])
        }
        XCTAssertEqual(CoachV2Analytics.Event.consentV2Shown(surface: .join).properties["surface"], .kind("join"))
        XCTAssertEqual(CoachV2Analytics.Event.consentV2Shown(surface: .notice).properties["surface"], .kind("notice"))
    }
}
