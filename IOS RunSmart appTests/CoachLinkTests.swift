import XCTest
@testable import IOS_RunSmart_app

/// Story 1.3: join by code stops for a guest, Not now writes nothing, and each
/// failure uses the consent-screen copy. "Coach" is the human coach.
@MainActor
final class CoachLinkTests: XCTestCase {
    private final class StubRepository: CoachLinkRepository, @unchecked Sendable {
        var link: CoachLink?
        var lookup: Result<CoachLookup?, Error> = .success(nil)
        var join: Result<JoinCoachOutcome, Error> = .success(
            .joined(CoachLookup(
                inviteID: UUID(uuidString: "11111111-0000-4000-8000-000000000001")!,
                coachID: UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!,
                displayName: "Dana",
                code: "ABC234"
            ))
        )
        /// Lookups consumed in order. When empty, `lookup` is used.
        var lookupQueue: [Result<CoachLookup?, Error>] = []
        private(set) var lookupCalls = 0
        private(set) var joinCalls = 0
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

        func joinCoach(code: String, inviteID: UUID, coachID: UUID) async throws -> JoinCoachOutcome {
            joinCalls += 1
            joinedCode = code
            joinedInviteID = inviteID
            joinedCoachID = coachID
            return try join.get()
        }
    }

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

        await model.continueTapped(isSignedIn: false)

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(repository.lookupCalls, 0)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
    }

    func testValidCodeShowsConsentAndNotNowCreatesNothing() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)

        await model.continueTapped(isSignedIn: true)

        XCTAssertEqual(model.phase, .consent(dana))
        XCTAssertEqual(repository.joinCalls, 0)

        model.notNow()

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
    }

    func testShareJoinsAndNotNowDoesNot() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        repository.join = .success(.joined(dana))
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)
        await model.continueTapped(isSignedIn: true)

        await model.share()

        XCTAssertEqual(model.joinedCoach, dana)
        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(repository.joinedCode, "ABC234")
    }

    func testShareUsesTheCodeFromConsentWhenTheFieldChanges() async {
        let repository = StubRepository()
        repository.lookup = .success(dana)
        repository.join = .success(.joined(dana))
        let model = JoinCoachViewModel(code: "DANA01", repository: repository)
        await model.continueTapped(isSignedIn: true)

        model.code = "RON999"
        await model.share()

        XCTAssertEqual(repository.joinedCode, "DANA01")
        XCTAssertEqual(repository.joinedInviteID, danaInvite)
        XCTAssertEqual(repository.joinedCoachID, danaCoach)
        XCTAssertEqual(model.joinedCoach?.coachID, danaCoach)
        XCTAssertEqual(model.joinedCoach?.displayName, "Dana")
    }

    func testInvalidCodeCopy() async {
        let repository = StubRepository()
        repository.lookup = .success(nil)
        let model = JoinCoachViewModel(code: "NOPE00", repository: repository)

        await model.continueTapped(isSignedIn: true)

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
        repository.link = CoachLink(id: UUID(), coachID: dana.coachID, coachName: "Dana")
        let model = JoinCoachViewModel(code: "OTHER1", repository: repository)

        await model.continueTapped(isSignedIn: true)

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
        await model.continueTapped(isSignedIn: true)

        await model.share()

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

        await model.continueTapped(isSignedIn: true)

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

        repository.link = CoachLink(id: UUID(), coachID: dana.coachID, coachName: "Dana")
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
        repository.join = .success(.joined(ronForSameCode))
        let model = JoinCoachViewModel(code: "ABC234", repository: repository)

        await model.continueTapped(isSignedIn: true)
        XCTAssertEqual(model.phase, .consent(danaForCode))

        await model.share()

        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)
        XCTAssertEqual(model.phase, .consent(ronForSameCode))
        XCTAssertEqual(model.errorMessage, "This code now belongs to Ron")

        await model.share()

        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(repository.joinedInviteID, ronInvite)
        XCTAssertEqual(repository.joinedCoachID, ronCoach)
        XCTAssertEqual(model.joinedCoach?.displayName, "Ron")
    }

    func testRefreshDiscardsResultAfterUserSwitch() async {
        let repository = StubRepository()
        repository.link = CoachLink(id: UUID(), coachID: danaCoach, coachName: "Dana")
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
}
