import XCTest
@testable import IOS_RunSmart_app

/// Story 1.8: a Group Plan coach is confirmed, then the athlete's phone generates
/// the plan, and only then is the link created.
@MainActor
final class GroupPlanJoinTests: XCTestCase {
    private final class StubRepository: CoachLinkRepository, @unchecked Sendable {
        var lookup: Result<CoachLookup?, Error> = .success(nil)
        var join: Result<JoinCoachOutcome, Error> = .failure(CoachLinkServiceError.invalidCode)
        private(set) var joinCalls = 0
        private(set) var lookupCalls = 0

        func currentLink() async throws -> CoachLink? { nil }

        func lookupInvite(code: String) async throws -> CoachLookup? {
            lookupCalls += 1
            guard let found = try lookup.get() else { return nil }
            return CoachLookup(
                inviteID: found.inviteID,
                coachID: found.coachID,
                displayName: found.displayName,
                code: code,
                planMode: found.planMode,
                groupPlan: found.groupPlan
            )
        }

        func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
            joinCalls += 1
            return try join.get()
        }

        func leaveCoach(linkID: UUID) async throws {}
    }

    @MainActor
    private final class StubPlans: GroupPlanAthleteContext {
        var profileValue = OnboardingProfile.empty
        var plan: TrainingPlanSnapshot?
        var missing = false
        var generateResult = true
        private(set) var generateCalls = 0
        private(set) var requests: [TrainingGoalRequest] = []
        var holdGenerate = false
        private var releaseGenerate: CheckedContinuation<Void, Never>?
        private var generateEntered: CheckedContinuation<Void, Never>?

        func profile() -> OnboardingProfile { profileValue }

        func activePlan() async -> TrainingPlanSnapshot? { plan }

        func isActivePlanConfirmedMissing() async -> Bool { missing }

        func generateAndPersist(_ request: TrainingGoalRequest) async -> Bool {
            generateCalls += 1
            requests.append(request)
            if holdGenerate {
                holdGenerate = false
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    releaseGenerate = continuation
                    generateEntered?.resume()
                    generateEntered = nil
                }
            }
            return generateResult
        }

        func waitUntilGenerateBlocked() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if releaseGenerate != nil {
                    continuation.resume()
                    return
                }
                generateEntered = continuation
            }
        }

        func releaseGenerateHold() {
            releaseGenerate?.resume()
            releaseGenerate = nil
        }
    }

    private let athleteID = UUID()
    private let danaInvite = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let danaCoach = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))! }

    private func settings(race: Date, goal: String = "distance", distance: String = "half-marathon") -> GroupPlanSettings {
        GroupPlanSettings(goal: goal, targetDistance: distance, raceDate: race, level: "beginner", runsPerWeek: 3)
    }

    private func dana(mode: CoachPlanMode?, settings: GroupPlanSettings? = nil) -> CoachLookup {
        CoachLookup(
            inviteID: danaInvite,
            coachID: danaCoach,
            displayName: "Dana",
            code: "ABC234",
            planMode: mode,
            groupPlan: settings
        )
    }

    private var joinedDana: CoachLink {
        CoachLink(id: danaInvite, coachID: danaCoach, coachName: "Dana", consentedAt: Date(timeIntervalSince1970: 0))
    }

    private func model(
        lookup: CoachLookup,
        plans: StubPlans,
        join: Result<JoinCoachOutcome, Error> = .success(.joined(
            CoachLink(id: UUID(uuidString: "11111111-0000-4000-8000-000000000001")!,
                      coachID: UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!,
                      coachName: "Dana",
                      consentedAt: Date(timeIntervalSince1970: 0))
        ))
    ) -> (JoinCoachViewModel, StubRepository, StubPlans) {
        let repository = StubRepository()
        repository.lookup = .success(lookup)
        repository.join = join
        let fixedToday = today
        let viewModel = JoinCoachViewModel(
            code: "ABC234",
            repository: repository,
            plans: plans,
            now: { fixedToday },
            calendar: calendar
        )
        return (viewModel, repository, plans)
    }

    func testConfirmCopyMatchesTheStory() {
        let race = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let group = settings(race: race)
        XCTAssertEqual(GroupPlanConfirmCopy.title(coach: "Dana"), "Dana's group plan")
        XCTAssertEqual(
            GroupPlanConfirmCopy.detailsLine(group, calendar: calendar),
            "Half marathon · Race 15 Mar · Beginner · 3 runs a week"
        )
        XCTAssertEqual(
            GroupPlanConfirmCopy.replaces("10K, week 4"),
            "This replaces your current plan (10K, week 4)."
        )
        XCTAssertFalse(GroupPlanConfirmCopy.replaces("10K, week 4").localizedCaseInsensitiveContains("archived"))
        XCTAssertEqual(GroupPlanConfirmCopy.useButton(coach: "Dana"), "Use Dana's plan")
        XCTAssertEqual(GroupPlanConfirmCopy.building, "Building your plan…")
        XCTAssertEqual(GroupPlanConfirmCopy.generationFailed, "We couldn't build your plan. You're not linked yet.")
        XCTAssertEqual(
            GroupPlanConfirmCopy.joinFailed(coach: "Dana"),
            "Couldn't connect you to Dana. Nothing was shared."
        )
    }

    func testGroupShareShowsConfirmAndDoesNotLink() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let plans = StubPlans()
        let (viewModel, repository, _) = model(lookup: dana(mode: .group, settings: settings(race: race)), plans: plans)

        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        guard case .groupConfirm(let confirm) = viewModel.phase else {
            return XCTFail("expected the group plan confirm")
        }
        XCTAssertNil(confirm.replacement)
        XCTAssertFalse(confirm.planBuilt)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(viewModel.joinedCoach)
        XCTAssertEqual(plans.generateCalls, 0)
    }

    func testNoCurrentPlanOmitsTheReplaceSentence() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let plans = StubPlans()
        plans.plan = nil
        let (viewModel, _, _) = model(lookup: dana(mode: .group, settings: settings(race: race)), plans: plans)
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        guard case .groupConfirm(let confirm) = viewModel.phase else {
            return XCTFail("expected the group plan confirm")
        }
        XCTAssertNil(confirm.replacement)
    }

    func testCurrentPlanIncludesTheReplaceSentence() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let plans = StubPlans()
        plans.plan = TrainingPlanSnapshot(
            id: UUID(),
            title: "10K",
            startDate: calendar.date(byAdding: .day, value: -21, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 63, to: today)!,
            totalWeeks: 12,
            planType: "basic"
        )
        let (viewModel, repository, _) = model(lookup: dana(mode: .group, settings: settings(race: race)), plans: plans)
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        guard case .groupConfirm(let confirm) = viewModel.phase else {
            return XCTFail("expected the group plan confirm")
        }
        let summary = GroupPlanConfirmCopy.currentPlanSummary(plans.plan!, today: today, calendar: calendar)
        XCTAssertEqual(confirm.replacement, GroupPlanConfirmCopy.replaces(summary))
        XCTAssertTrue(confirm.replacement?.hasPrefix("This replaces your current plan (") == true)
        XCTAssertFalse(confirm.replacement?.localizedCaseInsensitiveContains("archived") == true)
        XCTAssertEqual(repository.joinCalls, 0)
    }

    func testCancelReturnsToConsentWithoutLinking() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let shown = dana(mode: .group, settings: settings(race: race))
        let (viewModel, repository, _) = model(lookup: shown, plans: StubPlans())
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        viewModel.cancelGroupPlan()

        XCTAssertEqual(viewModel.phase, .consent(shown, athleteID: athleteID))
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(viewModel.joinedCoach)
    }

    func testUseBuildsTheGroupPlanThenLinks() async throws {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let group = settings(race: race)
        let plans = StubPlans()
        plans.profileValue.displayName = "Yoni"
        plans.profileValue.age = 31
        let (viewModel, repository, _) = model(lookup: dana(mode: .group, settings: group), plans: plans)
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        await viewModel.useGroupPlan(athleteID: athleteID)

        XCTAssertEqual(plans.generateCalls, 1)
        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(viewModel.joinedCoach, joinedDana)
        XCTAssertEqual(viewModel.followUp, .today)
        let request = try XCTUnwrap(plans.requests.first)
        XCTAssertEqual(request.webPlanGoal, group.goal)
        XCTAssertEqual(request.resolvedTargetDistance, group.targetDistance)
        XCTAssertEqual(request.targetDate, calendar.startOfDay(for: race))
        XCTAssertEqual(request.weeklyRunDays, group.runsPerWeek)
        XCTAssertEqual(request.planWeekCount, 10)
        XCTAssertNil(request.planStartDate)
        XCTAssertEqual(request.age, 31)
    }

    func testBuildingPhaseShowsBeforeThePlanExists() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let plans = StubPlans()
        plans.holdGenerate = true
        let (viewModel, repository, _) = model(lookup: dana(mode: .group, settings: settings(race: race)), plans: plans)
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        let task = Task { await viewModel.useGroupPlan(athleteID: athleteID) }
        await plans.waitUntilGenerateBlocked()
        XCTAssertEqual(viewModel.phase, .building(coachName: "Dana"))
        XCTAssertEqual(repository.joinCalls, 0)
        plans.releaseGenerateHold()
        await task.value
        XCTAssertEqual(repository.joinCalls, 1)
    }

    func testGenerationFailureCreatesNoLink() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let plans = StubPlans()
        plans.generateResult = false
        let (viewModel, repository, _) = model(lookup: dana(mode: .group, settings: settings(race: race)), plans: plans)
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        await viewModel.useGroupPlan(athleteID: athleteID)

        XCTAssertEqual(plans.generateCalls, 1)
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertNil(viewModel.joinedCoach)
        XCTAssertEqual(viewModel.groupFailureMessage, "We couldn't build your plan. You're not linked yet.")
        guard case .groupConfirm(let confirm) = viewModel.phase else {
            return XCTFail("stayed on confirm")
        }
        XCTAssertFalse(confirm.planBuilt)
    }

    func testJoinFailureRetriesTheLinkWithoutRegenerating() async {
        let race = calendar.date(byAdding: .day, value: 70, to: today)!
        let plans = StubPlans()
        let (viewModel, repository, _) = model(
            lookup: dana(mode: .group, settings: settings(race: race)),
            plans: plans,
            join: .failure(URLError(.networkConnectionLost))
        )
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)
        await viewModel.useGroupPlan(athleteID: athleteID)

        XCTAssertEqual(plans.generateCalls, 1)
        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertNil(viewModel.joinedCoach)
        XCTAssertEqual(viewModel.groupFailureMessage, "Couldn't connect you to Dana. Nothing was shared.")

        repository.join = .success(.joined(joinedDana))
        await viewModel.useGroupPlan(athleteID: athleteID)

        XCTAssertEqual(plans.generateCalls, 1)
        XCTAssertEqual(repository.joinCalls, 2)
        XCTAssertEqual(viewModel.joinedCoach, joinedDana)
    }

    func testIndividualModeSkipsTheConfirmAndKeepsAnExistingPlan() async {
        let plans = StubPlans()
        plans.plan = TrainingPlanSnapshot(
            id: UUID(), title: "10K", startDate: today, endDate: today, totalWeeks: 8, planType: "basic"
        )
        plans.missing = false
        let (viewModel, repository, _) = model(lookup: dana(mode: .individual), plans: plans)

        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        XCTAssertEqual(viewModel.joinedCoach, joinedDana)
        XCTAssertEqual(viewModel.followUp, .today)
        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(plans.generateCalls, 0)
        if case .groupConfirm = viewModel.phase {
            XCTFail("individual mode showed A4")
        }
    }

    func testIndividualModeWithNoPlanOpensBuildMyPlan() async {
        let plans = StubPlans()
        plans.missing = true
        let (viewModel, repository, _) = model(lookup: dana(mode: .individual), plans: plans)

        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        XCTAssertEqual(viewModel.joinedCoach, joinedDana)
        XCTAssertEqual(viewModel.followUp, .buildMyPlan)
        XCTAssertEqual(repository.joinCalls, 1)
        XCTAssertEqual(plans.generateCalls, 0)
    }

    func testMissingGroupSettingsDoesNotLink() async {
        let (viewModel, repository, plans) = model(lookup: dana(mode: .group, settings: nil), plans: StubPlans())
        await viewModel.continueTapped(athleteID: athleteID)
        await viewModel.share(athleteID: athleteID)

        XCTAssertEqual(viewModel.phase, .consent(dana(mode: .group, settings: nil), athleteID: athleteID))
        XCTAssertEqual(viewModel.errorMessage, "We couldn't build your plan. You're not linked yet.")
        XCTAssertEqual(repository.joinCalls, 0)
        XCTAssertEqual(plans.generateCalls, 0)
    }

    func testRaceBeyondSixteenWeeksStartsOnTheFinalSixteen() {
        let race = calendar.date(byAdding: .day, value: 20 * 7, to: today)!
        let window = GroupPlanRules.planWindow(raceDate: race, today: today, calendar: calendar)
        let expectedStart = calendar.date(byAdding: .day, value: -(16 * 7), to: race)!
        XCTAssertEqual(window.weeks, 16)
        XCTAssertEqual(window.startDate, expectedStart)
        XCTAssertGreaterThan(expectedStart, today)

        let request = GroupPlanRequest.make(
            settings: settings(race: race, goal: "habit", distance: "10k"),
            profile: OnboardingProfile.empty,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(request.planWeekCount, 16)
        XCTAssertEqual(request.planStartDate, expectedStart)
        XCTAssertEqual(request.webPlanGoal, "habit")
        XCTAssertEqual(request.resolvedTargetDistance, "10k")
        XCTAssertEqual(request.targetDate, race)
    }

    func testTwoAthletesGetTheSameGoalDistanceAndRaceDate() {
        let race = calendar.date(byAdding: .day, value: 20 * 7, to: today)!
        let group = settings(race: race)
        var yoni = OnboardingProfile.empty
        yoni.displayName = "Yoni"
        yoni.goal = "10K improvement"
        yoni.experience = "advanced"
        yoni.age = 30
        yoni.preferredDays = ["Mon"]
        yoni.weeklyRunDays = 5
        var noa = OnboardingProfile.empty
        noa.displayName = "Noa"
        noa.goal = "just for fun"
        noa.experience = "Building base"
        noa.age = 44
        noa.preferredDays = ["Fri", "Sun"]
        noa.weeklyRunDays = 2

        let first = GroupPlanRequest.make(settings: group, profile: yoni, today: today, calendar: calendar)
        let second = GroupPlanRequest.make(settings: group, profile: noa, today: today, calendar: calendar)

        XCTAssertEqual(first.webPlanGoal, second.webPlanGoal)
        XCTAssertEqual(first.resolvedTargetDistance, second.resolvedTargetDistance)
        XCTAssertEqual(first.targetDate, second.targetDate)
        XCTAssertEqual(first.planStartDate, second.planStartDate)
        XCTAssertEqual(first.planWeekCount, second.planWeekCount)
        XCTAssertEqual(first.webPlanGoal, "distance")
        XCTAssertEqual(first.resolvedTargetDistance, "half-marathon")
        XCTAssertEqual(first.targetDate, race)
        XCTAssertEqual(first.weeklyRunDays, 3)
        XCTAssertEqual(second.weeklyRunDays, 3)
        XCTAssertEqual(first.supabaseExperience, "beginner")
        XCTAssertEqual(second.supabaseExperience, "beginner")
        XCTAssertEqual(first.age, 30)
        XCTAssertEqual(second.age, 44)
        XCTAssertNotEqual(first.preferredDays, second.preferredDays)
    }

    func testLookupDecodesGroupSettingsAndALegacyRow() throws {
        let group = """
        {"invite_id":"11111111-0000-4000-8000-000000000001","coach_id":"AAAAAAAA-0000-4000-8000-00000000000A","display_name":"Dana","plan_mode":"group","goal":"distance","target_distance":"half-marathon","race_date":"2026-03-15","level":"beginner","runs_per_week":3}
        """
        let row = try JSONDecoder().decode(CoachInviteLookupRow.self, from: Data(group.utf8))
        let lookup = row.coachLookup(code: "ABC234")
        XCTAssertEqual(lookup.planMode, .group)
        XCTAssertEqual(lookup.groupPlan?.goal, "distance")
        XCTAssertEqual(lookup.groupPlan?.targetDistance, "half-marathon")
        XCTAssertEqual(lookup.groupPlan?.level, "beginner")
        XCTAssertEqual(lookup.groupPlan?.runsPerWeek, 3)
        XCTAssertEqual(lookup.groupPlan?.raceDateString(), "2026-03-15")

        let legacy = """
        {"invite_id":"11111111-0000-4000-8000-000000000001","coach_id":"AAAAAAAA-0000-4000-8000-00000000000A","display_name":"Dana"}
        """
        let old = try JSONDecoder().decode(CoachInviteLookupRow.self, from: Data(legacy.utf8))
        XCTAssertNil(old.coachLookup(code: "ABC234").planMode)
        XCTAssertNil(old.coachLookup(code: "ABC234").groupPlan)
    }
}
