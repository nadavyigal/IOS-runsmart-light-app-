import XCTest
@testable import IOS_RunSmart_app

/// Story 1.2: the Coach tab exists only for flagged coaches; the invite is
/// short, case-insensitive and shareable. "Coach" is the human coach, not the AI coach.
@MainActor
final class CoachModeTests: XCTestCase {
    private final class StubRepository: CoachModeRepository, @unchecked Sendable {
        var hasProfile: Result<Bool, Error> = .success(false)
        var invite: Result<String, Error> = .success("K7M2QX")
        private(set) var inviteCalls = 0

        func hasCoachProfile(userID: UUID) async throws -> Bool { try hasProfile.get() }

        func myInviteCode() async throws -> String {
            inviteCalls += 1
            return try invite.get()
        }
    }

    private struct Offline: Error {}

    private let userA = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let userB = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!

    // MARK: Tab visibility

    func testCoachTabIsHiddenForNonCoaches() {
        let tabs = RunSmartTab.visibleTabs(isCoach: false)
        XCTAssertFalse(tabs.contains(.coach))
        XCTAssertEqual(tabs, [.today, .plan, .run, .report, .profile],
                       "non-coaches must see exactly the existing five tabs, in the existing order")
    }

    func testCoachTabIsShownToCoachesBesideTheNormalTabs() {
        let tabs = RunSmartTab.visibleTabs(isCoach: true)
        XCTAssertTrue(tabs.contains(.coach))
        XCTAssertEqual(tabs.filter { $0 != .coach }, RunSmartTab.visibleTabs(isCoach: false),
                       "a coach is also an ordinary athlete: every normal tab stays")
    }

    func testTabBarDefaultsToTheNonCoachTabs() {
        // A tab bar built without being told the role must never show the Coach tab.
        let bar = CustomTabBar(selectedTab: .constant(.today))
        XCTAssertFalse(bar.tabs.contains(.coach))
    }

    func testStoreStartsAsNonCoach() {
        XCTAssertFalse(CoachModeStore(repository: StubRepository()).isCoach)
    }

    // MARK: Role check

    func testUserWithoutCoachProfileNeverGetsTheTab() async {
        let repository = StubRepository()
        repository.hasProfile = .success(false)
        let store = CoachModeStore(repository: repository)

        await store.refresh(userID: userA)

        XCTAssertFalse(store.isCoach)
        XCTAssertFalse(RunSmartTab.visibleTabs(isCoach: store.isCoach).contains(.coach))
    }

    func testUserWithCoachProfileGetsTheTab() async {
        let repository = StubRepository()
        repository.hasProfile = .success(true)
        let store = CoachModeStore(repository: repository)

        await store.refresh(userID: userA)

        XCTAssertTrue(store.isCoach)
        XCTAssertTrue(RunSmartTab.visibleTabs(isCoach: store.isCoach).contains(.coach))
    }

    func testSigningOutRemovesTheTab() async {
        let repository = StubRepository()
        repository.hasProfile = .success(true)
        let store = CoachModeStore(repository: repository)
        await store.refresh(userID: userA)
        XCTAssertTrue(store.isCoach)

        await store.refresh(userID: nil)

        XCTAssertFalse(store.isCoach, "signing out must remove the tab")
    }

    func testSwitchingToANonCoachAccountRemovesTheTab() async {
        let repository = StubRepository()
        repository.hasProfile = .success(true)
        let store = CoachModeStore(repository: repository)
        await store.refresh(userID: userA)
        XCTAssertTrue(store.isCoach)

        repository.hasProfile = .success(false)
        await store.refresh(userID: userB)

        XCTAssertFalse(store.isCoach)
    }

    func testFailedCheckNeverGrantsTheTabToANewUser() async {
        let repository = StubRepository()
        repository.hasProfile = .failure(Offline())
        let store = CoachModeStore(repository: repository)

        await store.refresh(userID: userA)

        XCTAssertFalse(store.isCoach)
    }

    func testFailedCheckKeepsTheTabForTheSameCoach() async {
        let repository = StubRepository()
        repository.hasProfile = .success(true)
        let store = CoachModeStore(repository: repository)
        await store.refresh(userID: userA)

        repository.hasProfile = .failure(Offline())
        await store.refresh(userID: userA)

        XCTAssertTrue(store.isCoach, "a coach on a flaky connection should not lose the tab")
    }

    func testFailedCheckAfterSwitchingUsersDoesNotCarryTheOldRole() async {
        let repository = StubRepository()
        repository.hasProfile = .success(true)
        let store = CoachModeStore(repository: repository)
        await store.refresh(userID: userA)

        repository.hasProfile = .failure(Offline())
        await store.refresh(userID: userB)

        XCTAssertFalse(store.isCoach, "user B must not inherit user A's coach tab")
    }

    // MARK: Invite

    func testInviteLinkIsBaseJoinCode() {
        let invite = CoachInvite(code: "K7M2QX")
        let base = URL(string: "https://example.test")!

        XCTAssertEqual(invite.link(baseURL: base).absoluteString, "https://example.test/join/K7M2QX")
        XCTAssertEqual(invite.link().absoluteString, ExternalURLs.inviteBase.absoluteString + "/join/K7M2QX")
    }

    func testInviteCodeIsCaseInsensitiveByUppercasing() {
        XCTAssertEqual(CoachInvite(code: " k7m2qx\n").code, "K7M2QX")
        XCTAssertEqual(CoachInvite(code: "k7m2qx"), CoachInvite(code: "K7M2QX"))
        XCTAssertTrue(CoachInvite(code: "k7m2qx").link().absoluteString.hasSuffix("/join/K7M2QX"))
    }

    func testShareMessageMatchesTheSpec() {
        let invite = CoachInvite(code: "K7M2QX")
        let base = URL(string: "https://example.test")!

        XCTAssertEqual(
            invite.shareMessage(baseURL: base),
            "Join my group in RunSmart: https://example.test/join/K7M2QX  Code: K7M2QX"
        )
    }

    func testInviteViewModelLoadsTheCode() async {
        let repository = StubRepository()
        let viewModel = CoachInviteViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded(CoachInvite(code: "K7M2QX")))
    }

    func testInviteViewModelShowsErrorThenRetrySucceeds() async {
        let repository = StubRepository()
        repository.invite = .failure(Offline())
        let viewModel = CoachInviteViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed)

        repository.invite = .success("abc234")
        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded(CoachInvite(code: "ABC234")))
        XCTAssertEqual(repository.inviteCalls, 2)
    }
}
