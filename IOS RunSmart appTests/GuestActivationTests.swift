import XCTest
@testable import IOS_RunSmart_app

final class GuestActivationTests: XCTestCase {
    private nonisolated final class AnalyticsSpy: AnalyticsTracking {
        private(set) var events: [(name: String, properties: [String: Any])] = []

        func track(_ event: String, properties: [String: Any]) {
            events.append((event, properties))
        }

        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func reset() {}
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "GuestActivationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGuestJourneyPersistsLocallyAndCanBeCleared() throws {
        var profile = OnboardingProfile.empty
        profile.goal = "First 5K"
        profile.experience = "Getting started"
        profile.weeklyRunDays = 3
        profile.preferredDays = ["Mon", "Wed", "Sat"]

        let first = GuestJourneyStore(defaults: defaults)
        first.start()
        first.update(profile: profile, step: .preview)
        first.markPreviewSeen()

        let restored = GuestJourneyStore(defaults: defaults)
        XCTAssertTrue(restored.state.isActive)
        XCTAssertEqual(restored.state.profile, profile)
        XCTAssertEqual(restored.state.step, .preview)
        XCTAssertTrue(restored.state.hasSeenPreview)

        restored.clear()
        XCTAssertFalse(GuestJourneyStore(defaults: defaults).state.isActive)
    }

    func testPreviewUsesGoalExperienceAndScheduleDeterministically() throws {
        var profile = OnboardingProfile.empty
        profile.goal = "First 5K"
        profile.experience = "Getting started"
        profile.weeklyRunDays = 3
        profile.preferredDays = ["Mon", "Wed", "Sat"]

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z"))

        let first = GuestPlanPreviewBuilder.make(profile: profile, now: now, calendar: calendar)
        let repeated = GuestPlanPreviewBuilder.make(profile: profile, now: now, calendar: calendar)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.workouts.count, 3)
        XCTAssertEqual(first.goal, "First 5K")
        XCTAssertEqual(first.experience, "Getting started")
        XCTAssertEqual(first.firstWorkout, first.workouts.first)
        XCTAssertEqual(first.workouts.map(\.weekday), ["Sat", "Mon", "Wed"])

        var advanced = profile
        advanced.goal = "Marathon"
        advanced.experience = "Race focused"
        let advancedPreview = GuestPlanPreviewBuilder.make(profile: advanced, now: now, calendar: calendar)
        XCTAssertGreaterThan(advancedPreview.firstWorkout.distanceKm, first.firstWorkout.distanceKm)
        XCTAssertNotEqual(advancedPreview.workouts.map(\.kind), first.workouts.map(\.kind))
    }

    func testUpgradeProfilePreservesGuestAnswersAndResumesAtCoaching() {
        var profile = OnboardingProfile.empty
        profile.goal = "Half Marathon"
        profile.experience = "Consistent runner"
        profile.weeklyRunDays = 4
        profile.preferredDays = ["Tue", "Thu", "Sat", "Sun"]

        let state = GuestJourneyState(
            isActive: true,
            profile: profile,
            step: .preview,
            hasSeenPreview: true,
            didTrackAuthenticatedUpgrade: false
        )

        XCTAssertEqual(state.upgradeProfile.goal, "Half Marathon")
        XCTAssertEqual(state.upgradeProfile.experience, "Consistent runner")
        XCTAssertEqual(state.upgradeProfile.weeklyRunDays, 4)
        XCTAssertEqual(state.upgradeProfile.preferredDays, ["Tue", "Thu", "Sat", "Sun"])
        XCTAssertEqual(state.authenticatedOnboardingStartStep, 3)
    }

    func testGuestRelaunchGetsItsOwnFirstFrameRoute() {
        XCTAssertEqual(ActivationFirstFrameScreen.guestValue.rawValue, "guest_value")
        XCTAssertEqual(ActivationFirstFrameScreen.resolved(
            isLaunchOverlayVisible: false,
            isLoading: false,
            isAuthenticated: false,
            hasCompletedOnboarding: false,
            isGuestJourneyActive: true
        ), .guestValue)
    }

    func testGuestActivationEventsKeepStableFunnelNamesAndProperties() {
        let saved = Analytics.shared
        let spy = AnalyticsSpy()
        defer { Analytics.shared = saved }
        Analytics.shared = spy

        Analytics.trackGuestModeStarted()
        Analytics.trackGuestProfileCompleted(goal: "First 5K", experience: "Getting started", daysPerWeek: 3)
        Analytics.trackGuestPlanPreviewViewed(
            goal: "First 5K",
            experience: "Getting started",
            daysPerWeek: 3,
            firstWorkoutType: "easy"
        )
        Analytics.trackGuestSignInPrompted(source: "week_one_preview")
        Analytics.trackGuestAuthenticatedUpgrade()

        XCTAssertEqual(spy.events.map(\.name), [
            "guest_mode_started",
            "guest_profile_completed",
            "guest_plan_preview_viewed",
            "guest_sign_in_prompted",
            "guest_authenticated_upgrade"
        ])
        XCTAssertEqual(spy.events[0].properties["source"] as? String, "sign_in_wall")
        XCTAssertEqual(spy.events[1].properties["days_per_week"] as? Int, 3)
        XCTAssertEqual(spy.events[2].properties["first_workout_type"] as? String, "easy")
        XCTAssertEqual(spy.events[3].properties["source"] as? String, "week_one_preview")
    }
}
