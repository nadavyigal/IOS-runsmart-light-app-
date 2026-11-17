import XCTest
@testable import IOS_RunSmart_app

/// Story 1.3: join by code stops for a guest, Not now writes nothing, and each
/// failure uses the consent-screen copy. "Coach" is the human coach.
@MainActor
final class CoachLinkTests: XCTestCase {
    private final class StubRepository: CoachLinkRepository, @unchecked Sendable {
        var link: CoachLink?
        var lookup: Result<CoachLookup?, Error> = .success(nil)
        var join: Result<JoinCoachOutcome, Error> = .failure(CoachLinkServiceError.invalidCode)
        /// Lookups consumed in order. When empty, `lookup` is used.
        var lookupQueue: [Result<CoachLookup?, Error>] = []
        private(set) var lookupCalls = 0
        private(set) var joinCalls = 0
        private(set) var leaveCalls = 0
        var leaveError: Error?
        private(set) var joinedCode: String?
        private(set) var joinedInviteID: UUID?
        private(set) var joinedCoachID: UUID?
        private(set) var currentLinkCalls = 0
        private var holdFirstLink = false
        private var releaseLink: CheckedContinuation<Void, Never>?
        private var linkEntered: CheckedContinuation<Void, Never>?

        func armHoldOnFirstCurrentLink() {
            holdFirstLink = true
        }

        func currentLink() async throws -> CoachLink? {
            currentLinkCalls += 1
            if holdFirstLink {
                holdFirstLink = false
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    releaseLink = continuation
                    linkEntered?.resume()
                    linkEntered = nil
                }
            }
            return link
        }

        func waitUntilCurrentLinkBlocked() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if releaseLink != nil {
                    continuation.resume()
                    return
                }
                linkEntered = continuation
            }
        }

        func releaseCurrentLink() {
            releaseLink?.resume()
            releaseLink = nil
        }

        func lookupInvite(code: String) async throws -> CoachLookup? {
            lookupCalls += 1
            let result: CoachLookup?
            if !lookupQueue.isEmpty {
                result = try lookupQueue.removeFirst().get()
            } else {
                result = try lookup.get()
            }
            guard let found = result else { return nil }
            return CoachLookup(
                inviteID: found.inviteID,
                coachID: found.coachID,
                displayName: found.displayName,
                code: code
            )
        }

        func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
            joinCalls += 1
            joinedCode = code
            joinedInviteID = inviteID
            joinedCoachID = coachID
            return try join.get()
        }

        func leaveCoach(linkID: UUID) async throws {
            leaveCalls += 1
            if let leaveError {
                throw leaveError
            }
            link = nil
        }
    }

    private let athleteID = UUID()
    private let danaInvite = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let ronInvite = UUID(uuidString: "22222222-0000-4000-8000-000000000002")!
    private let danaCoach = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let ronCoach = UUID(uuidString: "CCCCCCCC-0000-4000-8000-00000000000C")!

    private var dana: CoachLookup {
        CoachLookup(inviteID: danaInvite, coachID: danaCoach, displayName: "Dana", code: "ABC234")
    }

    private var ron: CoachLookup {
        CoachLookup(inviteID: ronInvite, coachID: ronCoach, displayName: "Ron", code: "ABC234")
    }

    private func persistedLink(for coach: CoachLookup) -> CoachLink {
        CoachLink(id: danaInvite, coachID: coach.coachID, coachName: coach.displayName,
                  consentedAt: Date(timeIntervalSince1970: 1_795_000_000))
    }

    func testConsentCopyMatchesTheStory() {
        XCTAssertEqual(CoachConsentCopy.title(coach: "Dana"), "Share with Dana?")
        XCTAssertEqual(
            CoachConsentCopy.body(coach: "Dana"),
            """
            Dana can see:
            • Your training plan
            • Your runs: distance, time, pace and average heart rate
            • Route maps of new runs you record in RunSmart. The start and end of each route are trimmed for privacy.

            Dana can also change your upcoming workouts.

            Not shared: your chats with RunSmart, and health data such as sleep or HRV.

            If you leave, Dana will no longer see your runs. You keep any feedback Dana has already given you. You can leave anytime in Settings.
            """
        )
    }

    func testUnsignedContinueDoesNotLookUpOrJoin() async {
        let repository = StubRepository()
        let model = JoinCoachViewModel(code: "abc234", repository: repository)

        await model.continueTapped(athleteID: nil)

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(repository.lookupCalls, 0)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
    }

    func testValidCodeShowsConsentAndNotNowCreatesNothing() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)

        await model.continueTapped(athleteID: athleteID)

        XCTAssertEqual(model.phase, .consent(dana, athleteID: athleteID))
        XCTAssertEqual(repository.joinCalls, 0)

        model.notNow()

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
    }

    func testShareJoinsAndNotNowDoesNot() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        repository.join = .success(.joined(persistedLink(for: dana)))
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)
        await model.continueTapped(athleteID: athleteID)

        await model.share(athleteID: athleteID)

        XCTAssertEqual(model.joinedCoach, persistedLink(for: dana))
        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(repository.joinedCode, "ABC234")
    }

    func testShareUsesTheCodeFromConsentWhenTheFieldChanges() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        repository.join = .success(.joined(persistedLink(for: dana)))
        let model = JoinCoachViewModel(code: "DANA01", repository: repository)
        await model.continueTapped(athleteID: athleteID)

        model.code = "RON999"
        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.joinedCode, "DANA01")
        XCTAssertEqual(repository.joinedInviteID, danaInvite)
        XCTAssertEqual(repository.joinedCoachID, danaCoach)
        XCTAssertEqual(model.joinedCoach?.coachID, danaCoach)
        XCTAssertEqual(model.joinedCoach?.coachName, "Dana")
    }

    func testJoinIntentSurvivesSignInAndOnboardingAndIsConsumedOnce() {
        let store = CoachLinkStore(repository: StubRepository())
        store.resumeJoinAfterSignIn = true

        XCTAssertFalse(store.consumeJoinIntent(isAuthenticated: false, onboardingComplete: false))
        XCTAssertFalse(store.consumeJoinIntent(isAuthenticated: true, onboardingComplete: false))
        XCTAssertTrue(store.consumeJoinIntent(isAuthenticated: true, onboardingComplete: true))
        XCTAssertFalse(store.consumeJoinIntent(isAuthenticated: true, onboardingComplete: true))
    }

    func testAChangeOfAthleteRequiresFreshConsent() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)
        await model.continueTapped(athleteID: athleteID)

        await model.share(athleteID: UUID())

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testInvalidCodeCopy() async {
        let repository = StubRepository()
        repository.lookup = .success(nil)
        let model = JoinCoachViewModel(code: "NOPE00", repository: repository)

        await model.continueTapped(athleteID: athleteID)

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(model.errorMessage, "That code doesn't work. Check it with your coach.")
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testInactiveCodeUsesTheSameCopy() {
        let error = NSError(domain: "Postgrest", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "invalid_code"
        ])
        XCTAssertEqual(
            JoinCoachViewModel.message(for: error),
            "That code doesn't work. Check it with your coach."
        )
    }

    func testSelfJoinUsesTheInvalidCodeCopy() {
        XCTAssertEqual(
            JoinCoachViewModel.message(for: CoachLinkServiceError.invalidCode),
            "That code doesn't work. Check it with your coach."
        )
        let error = NSError(domain: "Postgrest", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "cannot_join_self"
        ])
        XCTAssertEqual(
            JoinCoachViewModel.message(for: error),
            "That code doesn't work. Check it with your coach."
        )
    }

    func testAlreadyLinkedCopy() async {
        let repository = StubRepository()
        repository.link = persistedLink(for: dana)
        let model = JoinCoachViewModel(code: "OTHER1", repository: repository)

        await model.continueTapped(athleteID: athleteID)

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(
            model.errorMessage,
            "You're with Dana. Leave Dana first to join another coach."
        )
        XCTAssertEqual(repository.lookupCalls, 0)
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testAlreadyLinkedFromJoinUsesTheCurrentCoachName() async {
        let repository = StubRepository()
        repository.lookup = .success(CoachLookup(
            inviteID: ronInvite,
            coachID: ronCoach,
            displayName: "Ron",
            code: "RON999"
        ))
        repository.join = .success(.alreadyLinked(coachName: "Dana"))
        let model = JoinCoachViewModel(code: "RON999", repository: repository)
        await model.continueTapped(athleteID: athleteID)

        await model.share(athleteID: athleteID)

        XCTAssertEqual(
            model.errorMessage,
            "You're with Dana. Leave Dana first to join another coach."
        )
        XCTAssertNil(model.joinedCoach)
    }

    func testOfflineCopy() async {
        let repository = StubRepository()
        repository.lookup = .failure(URLError(.notConnectedToInternet))
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)

        await model.continueTapped(athleteID: athleteID)

        XCTAssertEqual(model.errorMessage, "You need to be online to join.")
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
    }

    func testSettingsRowIsHiddenWhileLinked() async {
        let repository = StubRepository()
        let store = CoachLinkStore(repository: repository)
        XCTAssertFalse(store.showsJoinCoach)

        let userID = UUID()
        store.beginSession(userID: userID)
        await store.refresh(userID: userID)
        XCTAssertTrue(store.showsJoinCoach, "no link means the Settings row is shown")

        repository.link = persistedLink(for: dana)
        await store.refresh(userID: userID)
        XCTAssertFalse(store.showsJoinCoach)
    }

    func testShareRejectsWhenTheCodeNowNamesADifferentCoach() async {
        let repository = StubRepository()
        let danaForCode = CoachLookup(
            inviteID: danaInvite, coachID: danaCoach, displayName: "Dana", code: "ABC234"
        )
        let ronForSameCode = CoachLookup(
            inviteID: ronInvite, coachID: ronCoach, displayName: "Ron", code: "ABC234"
        )
        repository.lookupQueue = [.success(danaForCode), .success(ronForSameCode), .success(ronForSameCode)]
        repository.join = .success(.joined(persistedLink(for: ronForSameCode)))
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)

        await model.continueTapped(athleteID: athleteID)
        XCTAssertEqual(model.phase, .consent(danaForCode, athleteID: athleteID))

        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
        XCTAssertEqual(model.phase, .consent(ronForSameCode, athleteID: athleteID))
        XCTAssertEqual(model.errorMessage, "This code now belongs to Ron")

        await model.share(athleteID: athleteID)

        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(repository.joinedInviteID, ronInvite)
        XCTAssertEqual(repository.joinedCoachID, ronCoach)
        XCTAssertEqual(model.joinedCoach?.coachName, "Ron")
    }

    func testJoinKeepsServerLinkAndDiscardsOlderRefresh() async {
        let repository = StubRepository()
        repository.armHoldOnFirstCurrentLink()
        let store = CoachLinkStore(repository: repository)
        let athlete = UUID()
        store.beginSession(userID: athlete)
        let refresh = Task { await store.refresh(userID: athlete) }
        await repository.waitUntilCurrentLinkBlocked()

        let link = persistedLink(for: dana)
        store.noteJoined(link, userID: athlete)
        repository.releaseCurrentLink()
        await refresh.value

        XCTAssertEqual(store.currentLink, link)
        XCTAssertFalse(store.showsJoinCoach)
        store.beginSession(userID: UUID())
        store.noteJoined(link, userID: athlete)
        XCTAssertNil(store.currentLink)
    }

    func testRefreshDiscardsResultAfterUserSwitch() async {
        let repository = StubRepository()
        repository.link = persistedLink(for: dana)
        repository.armHoldOnFirstCurrentLink()
        let store = CoachLinkStore(repository: repository)
        let userA = UUID()
        let userB = UUID()
        store.beginSession(userID: userA)

        let first = Task { await store.refresh(userID: userA) }
        await repository.waitUntilCurrentLinkBlocked()

        repository.link = nil
        store.beginSession(userID: userB)
        let second = Task { await store.refresh(userID: userB) }
        await second.value
        repository.releaseCurrentLink()
        await first.value

        XCTAssertNil(store.currentLink)
        XCTAssertTrue(store.didAttemptLoad)
        XCTAssertTrue(store.showsJoinCoach)
    }

    func testLeaveSheetCopyMatchesAndHidesTheLockLine() {
        XCTAssertFalse(LeaveCoachCopy.coachWorkoutLocksEnabled)
        let sheet = LeaveCoachCopy.sheet(coach: "Dana")
        XCTAssertEqual(
            sheet,
            """
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
            """
        )
        XCTAssertFalse(sheet.contains("no longer protected"))
        for bullet in CoachConsentCopy.sharedBullets() {
            XCTAssertTrue(CoachConsentCopy.body(coach: "Dana").contains(bullet))
        }
        XCTAssertEqual(LeaveCoachCopy.monogram(for: "Dana Cohen"), "DC")
        XCTAssertEqual(
            LeaveCoachCopy.toast(coach: "Dana"),
            "You left Dana. Dana no longer sees your runs."
        )
    }

    func testCancelLeaveChangesNothing() async {
        let repository = StubRepository()
        repository.link = persistedLink(for: dana)
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(persistedLink(for: dana), userID: userID)
        let model = LeaveCoachModel()

        model.cancel()

        XCTAssertEqual(repository.leaveCalls, 0)
        XCTAssertEqual(store.currentLink, persistedLink(for: dana))
        XCTAssertFalse(store.showsJoinCoach)
        XCTAssertNil(model.errorMessage)
    }

    func testLeaveFailureKeepsTheAthleteLinked() async {
        let repository = StubRepository()
        repository.link = persistedLink(for: dana)
        repository.leaveError = CoachLinkServiceError.offline
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(persistedLink(for: dana), userID: userID)
        let model = LeaveCoachModel()

        let toast = await model.confirm(coachName: "Dana", userID: userID, store: store)

        XCTAssertNil(toast)
        XCTAssertEqual(model.errorMessage, LeaveCoachCopy.failure)
        XCTAssertEqual(store.currentLink?.coachName, "Dana")
        XCTAssertFalse(store.showsJoinCoach)
        XCTAssertEqual(repository.leaveCalls, 1)
    }

    func testLeaveRejectsAStaleLinkAndIgnoresAnOlderRefresh() async throws {
        let repository = StubRepository()
        let link = persistedLink(for: dana)
        repository.link = link
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(link, userID: userID)
        let model = LeaveCoachModel()
        let stale = await model.confirm(coachName: "Dana", userID: userID, store: store,
                                       expectedLinkID: UUID())
        XCTAssertNil(stale)
        XCTAssertEqual(repository.leaveCalls, 0)

        repository.armHoldOnFirstCurrentLink()
        let refresh = Task { await store.refresh(userID: userID) }
        await repository.waitUntilCurrentLinkBlocked()
        try await store.leave(userID: userID, expectedLinkID: link.id)
        repository.link = link
        repository.releaseCurrentLink()
        await refresh.value

        XCTAssertNil(store.currentLink)
        XCTAssertTrue(store.showsJoinCoach)
        let router = AppRouter(coachModeEnabled: false)
        router.open(.myCoach)
        XCTAssertNil(router.activeSheet)
    }

    func testLeaveReconcilesLostResponseWhenServerHasRevokedLink() async {
        let repository = StubRepository()
        repository.leaveError = CoachLinkServiceError.offline
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(persistedLink(for: dana), userID: userID)

        let toast = await LeaveCoachModel().confirm(coachName: "Dana", userID: userID, store: store)

        XCTAssertNotNil(toast)
        XCTAssertNil(store.currentLink)
    }

    func testLeaveSuccessShowsJoinCoachAgain() async {
        let repository = StubRepository()
        repository.link = persistedLink(for: dana)
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(persistedLink(for: dana), userID: userID)
        let model = LeaveCoachModel()

        let toast = await model.confirm(coachName: "Dana", userID: userID, store: store)

        XCTAssertEqual(toast, "You left Dana. Dana no longer sees your runs.")
        XCTAssertNil(store.currentLink)
        XCTAssertTrue(store.showsJoinCoach)
        XCTAssertEqual(store.leaveNotice, toast)
        store.beginSession(userID: UUID())
        XCTAssertNil(store.leaveNotice)
    }

    func testOfflineLeaveDoesNotCallTheServer() async {
        let repository = StubRepository()
        let store = CoachLinkStore(repository: repository)
        let userID = UUID()
        store.beginSession(userID: userID)
        store.noteJoined(persistedLink(for: dana), userID: userID)
        let model = LeaveCoachModel(isOnline: false)

        XCTAssertEqual(model.leaveDisabledReason, "Connect to the internet")
        let toast = await model.confirm(coachName: "Dana", userID: userID, store: store)

        XCTAssertNil(toast)
        XCTAssertEqual(repository.leaveCalls, 0)
        XCTAssertEqual(store.currentLink?.coachName, "Dana")
    }
}


/// Story 1.4: an invite link opens the join screen. The host is `ExternalURLs.inviteBase`.
@MainActor
final class InviteDeepLinkTests: XCTestCase {
    private final class Stub: CoachLinkRepository, @unchecked Sendable {
        var link: CoachLink?
        var lookup: Result<CoachLookup?, Error> = .success(nil)
        private(set) var joinCalls = 0

        func currentLink() async throws -> CoachLink? { link }

        func lookupInvite(code: String) async throws -> CoachLookup? {
            guard let found = try lookup.get() else { return nil }
            return CoachLookup(
                inviteID: found.inviteID,
                coachID: found.coachID,
                displayName: found.displayName,
                code: code
            )
        }

        func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
            joinCalls += 1
            return .joined(CoachLink(id: inviteID, coachID: coachID, coachName: foundName, consentedAt: Date(timeIntervalSince1970: 0)))
        }

        func leaveCoach(linkID: UUID) async throws {
            throw CoachLinkServiceError.notLinked
        }

        private var foundName: String { "Dana" }
    }

    private let athleteID = UUID()
    private let danaInvite = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let danaCoach = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!

    private var dana: CoachLookup {
        CoachLookup(inviteID: danaInvite, coachID: danaCoach, displayName: "Dana", code: "K7M2QX")
    }

    private func inviteURL(_ code: String) -> URL {
        ExternalURLs.inviteBase.appendingPathComponent("join").appendingPathComponent(code)
    }

    // MARK: URL parsing

    func testValidInviteURLExtractsTheCode() {
        let url = inviteURL("K7M2QX")
        XCTAssertEqual(InviteLink.route(for: url), .code("K7M2QX"))
        XCTAssertTrue(url.absoluteString.hasPrefix(ExternalURLs.inviteBase.absoluteString + "/join/"))
    }

    func testLowercaseCodeIsAccepted() {
        XCTAssertEqual(InviteLink.route(for: inviteURL("k7m2qx")), .code("K7M2QX"))
    }

    func testWrongHostIsIgnored() {
        let apex = URL(string: "https://runsmart-ai.com/join/K7M2QX")!
        let other = URL(string: "https://example.com/join/K7M2QX")!
        XCTAssertEqual(InviteLink.route(for: apex), .ignored)
        XCTAssertEqual(InviteLink.route(for: other), .ignored)
    }

    func testWrongPathIsIgnored() {
        let support = ExternalURLs.inviteBase.appendingPathComponent("support")
        XCTAssertEqual(InviteLink.route(for: support), .ignored)
    }

    func testJunkIsIgnored() {
        XCTAssertEqual(InviteLink.route(for: URL(string: "https://example.com/hello")!), .ignored)
        XCTAssertEqual(InviteLink.route(for: URL(string: "runsmart://join/K7M2QX")!), .ignored)
        XCTAssertNil(InviteLink.code(inPasted: "not a code and not a link"))
    }

    func testBadFormatOnTheInvitePathIsUnresolved() {
        XCTAssertEqual(InviteLink.route(for: inviteURL("IIIIII")), .unresolved)
        XCTAssertEqual(InviteLink.route(for: inviteURL("NO")), .unresolved)
    }

    // MARK: Paste

    func testPasteControlExtractsABareCode() {
        let model = JoinCoachViewModel(repository: Stub())
        model.applyPastedText("  k7m2qx\n")
        XCTAssertEqual(model.code, "K7M2QX")
    }

    func testPasteControlExtractsAFullLink() {
        let model = JoinCoachViewModel(code: "OLD", repository: Stub())
        model.applyPastedText(inviteURL("abc234").absoluteString)
        XCTAssertEqual(model.code, "ABC234")
    }

    func testPasteControlLeavesTheFieldWhenTheClipboardIsJunk() {
        let model = JoinCoachViewModel(code: "ABC234", repository: Stub())
        model.applyPastedText("hello there")
        XCTAssertEqual(model.code, "ABC234")
    }

    // MARK: Flow

    func testGuestKeepsTheCodeThroughSignIn() {
        let store = CoachLinkStore(repository: Stub())
        let consumed = store.receiveInviteLink(inviteURL("k7m2qx"), coachModeEnabled: true, canOpenJoinNow: false)

        XCTAssertTrue(consumed)
        XCTAssertEqual(store.draftCode, "K7M2QX")
        XCTAssertEqual(store.pendingInvite, .code("K7M2QX"))
        XCTAssertFalse(store.consumeJoinIntent(isAuthenticated: false, onboardingComplete: false))
        XCTAssertEqual(store.draftCode, "K7M2QX")
        XCTAssertFalse(store.consumeJoinIntent(isAuthenticated: true, onboardingComplete: false))
        XCTAssertEqual(store.draftCode, "K7M2QX")
        XCTAssertTrue(store.consumeJoinIntent(isAuthenticated: true, onboardingComplete: true))
        XCTAssertEqual(store.draftCode, "K7M2QX")
        XCTAssertEqual(store.pendingInvite, .code("K7M2QX"))
    }

    func testFlagOffDoesNotOpenTheJoinScreen() {
        let store = CoachLinkStore(repository: Stub())
        let consumed = store.receiveInviteLink(inviteURL("K7M2QX"), coachModeEnabled: false, canOpenJoinNow: true)

        XCTAssertTrue(consumed, "an invite link must not fall through to sign-in")
        XCTAssertNil(store.pendingInvite)
        XCTAssertEqual(store.draftCode, "")
        XCTAssertFalse(store.resumeJoinAfterSignIn)
    }

    func testBadLinkLandsOnJoinWithTheHint() {
        let store = CoachLinkStore(repository: Stub())
        XCTAssertTrue(store.receiveInviteLink(inviteURL("IIIIII"), coachModeEnabled: true, canOpenJoinNow: true))
        XCTAssertEqual(store.pendingInvite, .unresolved)
        XCTAssertEqual(store.draftCode, "")

        let model = JoinCoachViewModel(code: "LEFT", repository: Stub())
        model.consumePendingInvite(.unresolved)
        XCTAssertEqual(model.code, "")
        XCTAssertTrue(model.showsEntryHint)
        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(CoachConsentCopy.unresolvedLinkHint, "Enter your coach's code")
    }

    func testInvalidCodeFromLinkLandsEmptyWithHint() async {
        let repository = Stub()
        repository.lookup = .success(nil)
        let model = JoinCoachViewModel(repository: repository)
        model.consumePendingInvite(.code("K7M2QX"))
        XCTAssertEqual(model.phase, .resolvingLink)

        await model.resolveFromLink(athleteID: athleteID)

        XCTAssertEqual(model.code, "")
        XCTAssertTrue(model.showsEntryHint)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testOfflineLinkLandsEmptyWithHint() async {
        let repository = Stub()
        repository.lookup = .failure(URLError(.notConnectedToInternet))
        let model = JoinCoachViewModel(repository: repository)
        model.consumePendingInvite(.code("K7M2QX"))

        await model.resolveFromLink(athleteID: athleteID)

        XCTAssertEqual(model.code, "")
        XCTAssertTrue(model.showsEntryHint)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.phase, .enterCode)
    }

    func testValidLinkResolvesToConsent() async {
        let repository = Stub()
        repository.lookup = .success(dana)
        let model = JoinCoachViewModel(repository: repository)
        model.consumePendingInvite(.code("K7M2QX"))

        await model.resolveFromLink(athleteID: athleteID)

        XCTAssertEqual(model.phase, .consent(dana, athleteID: athleteID))
        XCTAssertFalse(model.showsEntryHint)
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testAlreadyLinkedLinkShowsTheStoryMessage() async {
        let repository = Stub()
        repository.link = CoachLink(
            id: danaInvite, coachID: danaCoach, coachName: "Dana",
            consentedAt: Date(timeIntervalSince1970: 1)
        )
        repository.lookup = .success(dana)
        let model = JoinCoachViewModel(repository: repository)
        model.consumePendingInvite(.code("K7M2QX"))

        await model.resolveFromLink(athleteID: athleteID)

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(model.code, "K7M2QX")
        XCTAssertEqual(
            model.errorMessage,
            "You're with Dana. Leave Dana first to join another coach."
        )
        XCTAssertFalse(model.showsEntryHint)
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testManualCodeStillReachesConsentAfterABadLink() async {
        let repository = Stub()
        repository.lookup = .success(dana)
        let model = JoinCoachViewModel(repository: repository)
        model.consumePendingInvite(.unresolved)
        XCTAssertTrue(model.showsEntryHint)

        model.code = "K7M2QX"
        await model.continueTapped(athleteID: athleteID)

        XCTAssertEqual(model.phase, .consent(dana, athleteID: athleteID))
        XCTAssertFalse(model.showsEntryHint)
    }
}
