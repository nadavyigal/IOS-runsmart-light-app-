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
            .joined(CoachLookup(coachID: UUID(), displayName: "Dana"))
        )
        private(set) var lookupCalls = 0
        private(set) var joinCalls = 0
        private(set) var joinedCode: String?
        private(set) var currentLinkCalls = 0

        func currentLink() async throws -> CoachLink? {
            currentLinkCalls += 1
            return link
        }

        func lookupInvite(code: String) async throws -> CoachLookup? {
            lookupCalls += 1
            return try lookup.get()
        }

        func joinCoach(code: String) async throws -> JoinCoachOutcome {
            joinCalls += 1
            joinedCode = code
            return try join.get()
        }
    }

    private let dana = CoachLookup(
        coachID: UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!,
        displayName: "Dana"
    )

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

    func testGuestContinueDoesNotCreateALinkAndKeepsTheCode() async {
        let repository = StubRepository()
        let model = JoinCoachViewModel(code: "abc234", repository: repository)

        await model.continueTapped(isSignedIn: false)

        XCTAssertEqual(model.phase, .needsSignIn)
        XCTAssertEqual(model.code, "abc234")
        XCTAssertEqual(repository.lookupCalls, 0)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(model.joinedCoach)

        model.returnedFromSignIn()

        XCTAssertEqual(model.phase, .enterCode)
        XCTAssertEqual(model.code, "abc234")
        XCTAssertEqual(repository.joinCalls, 0)
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
        XCTAssertEqual(model.joinedCoach, dana)
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
        repository.lookup = .success(CoachLookup(coachID: UUID(), displayName: "Ron"))
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

        await store.refresh()
        XCTAssertTrue(store.showsJoinCoach, "no link means the Settings row is shown")

        repository.link = CoachLink(id: UUID(), coachID: dana.coachID, coachName: "Dana")
        await store.refresh()
        XCTAssertFalse(store.showsJoinCoach)
    }
}
