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
