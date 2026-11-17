import XCTest
@testable import IOS_RunSmart_app

/// Story 1.7: the invite stays hidden until Plan Mode is set, validation matches
/// the generator's week math, and a saved mode cannot be changed in the UI.
@MainActor
final class CoachPlanSetupTests: XCTestCase {
    private final class StubRepository: CoachPlanRepository, @unchecked Sendable {
        var setup = CoachPlanSetup(mode: nil, groupPlan: nil)
        var setError: Error?
        var saveError: Error?
        private(set) var setModes: [CoachPlanMode] = []
        private(set) var saved: [GroupPlanSettings] = []

        func loadPlanSetup() async throws -> CoachPlanSetup { setup }

        func setPlanMode(_ mode: CoachPlanMode) async throws {
            if let setError { throw setError }
            setModes.append(mode)
            setup.mode = mode
        }

        func saveGroupPlan(_ settings: GroupPlanSettings) async throws {
            if let saveError { throw saveError }
            saved.append(settings)
            setup.groupPlan = settings
        }
    }

    private struct Offline: Error {}

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!
    }

    private func settings(daysFromToday days: Int, distance: String = "5k") -> GroupPlanSettings {
        GroupPlanSettings(
            goal: "habit",
            targetDistance: distance,
            raceDate: calendar.date(byAdding: .day, value: days, to: today)!,
            level: "beginner",
            runsPerWeek: 3
        )
    }

    func testInviteStaysHiddenUntilAModeIsSaved() async {
        let repository = StubRepository()
        let model = CoachPlanSetupModel(repository: repository)
        await model.load()

        XCTAssertFalse(model.showsInvite)
        XCTAssertTrue(model.canChangeMode)
        XCTAssertFalse(model.showsLockedMode)

        model.pendingMode = .individual
        await model.confirmChoice()

        XCTAssertEqual(model.mode, .individual)
        XCTAssertTrue(model.showsInvite)
        XCTAssertFalse(model.canChangeMode)
        XCTAssertEqual(model.lockedCaption, "Set for the pilot")
        XCTAssertEqual(repository.setModes, [.individual])
    }

    func testFailedChoiceDoesNotLockTheModeOrShowTheInvite() async {
        let repository = StubRepository()
        repository.setError = Offline()
        let model = CoachPlanSetupModel(repository: repository)
        await model.load()
        model.pendingMode = .group

        await model.confirmChoice()

        XCTAssertNil(model.mode)
        XCTAssertTrue(model.canChangeMode)
        XCTAssertFalse(model.showsInvite)
        XCTAssertEqual(model.choiceError, "Couldn't save your choice. Try again.")
    }

    func testGroupInviteAppearsOnlyAfterSettingsAreSaved() async {
        let repository = StubRepository()
        let model = CoachPlanSetupModel(repository: repository)
        await model.load()
        model.pendingMode = .group
        await model.confirmChoice()

        XCTAssertFalse(model.showsInvite)
        XCTAssertTrue(model.showsGroupForm)

        await model.saveSettings(settings(daysFromToday: 28), today: today, calendar: calendar)

        XCTAssertTrue(model.showsInvite)
        XCTAssertEqual(model.savedMessage, "Saved. New athletes who join will get this plan.")
        XCTAssertEqual(repository.saved.count, 1)
        XCTAssertFalse(model.showsGroupForm)
        XCTAssertTrue(model.showsGroupMenu)
    }

    func testSettingsSaveFailureKeepsTheInviteHiddenAndOffersRetry() async {
        let repository = StubRepository()
        repository.setup.mode = .group
        let model = CoachPlanSetupModel(repository: repository)
        await model.load()
        repository.saveError = Offline()

        let draft = settings(daysFromToday: 28)
        await model.saveSettings(draft, today: today, calendar: calendar)

        XCTAssertFalse(model.showsInvite)
        XCTAssertEqual(model.settingsError, "Couldn't save these settings.")

        repository.saveError = nil
        await model.saveSettings(draft, today: today, calendar: calendar)

        XCTAssertNil(model.settingsError)
        XCTAssertTrue(model.showsInvite)
        XCTAssertEqual(repository.saved.count, 1)
    }

    func testPastAndTooCloseDatesAreErrorsAndSixteenWeeksIsInfo() {
        let past = GroupPlanRules.dateNotice(
            raceDate: calendar.date(byAdding: .day, value: -1, to: today)!,
            targetDistance: "5k",
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(past, .past)
        XCTAssertEqual(past?.message, "That date is in the past.")
        XCTAssertEqual(past?.blocksSave, true)

        let tooClose = GroupPlanRules.dateNotice(
            raceDate: calendar.date(byAdding: .day, value: 21, to: today)!,
            targetDistance: "5k",
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(tooClose, .tooClose)
        XCTAssertEqual(tooClose?.message, "That race is too close for this distance.")

        let ok = GroupPlanRules.dateNotice(
            raceDate: calendar.date(byAdding: .day, value: 22, to: today)!,
            targetDistance: "5k",
            today: today,
            calendar: calendar
        )
        XCTAssertNil(ok)

        let sixteen = GroupPlanRules.dateNotice(
            raceDate: calendar.date(byAdding: .day, value: 112, to: today)!,
            targetDistance: "5k",
            today: today,
            calendar: calendar
        )
        XCTAssertNil(sixteen)

        let beyond = GroupPlanRules.dateNotice(
            raceDate: calendar.date(byAdding: .day, value: 113, to: today)!,
            targetDistance: "marathon",
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(beyond, .coversFinal16Weeks)
        XCTAssertEqual(beyond?.message, "The plan covers the final 16 weeks")
        XCTAssertEqual(beyond?.blocksSave, false)
    }

    func testFarRaceStillSaves() async {
        let repository = StubRepository()
        repository.setup.mode = .group
        let model = CoachPlanSetupModel(repository: repository)
        await model.load()

        await model.saveSettings(settings(daysFromToday: 140, distance: "half-marathon"), today: today, calendar: calendar)

        XCTAssertEqual(repository.saved.count, 1)
        XCTAssertTrue(model.showsInvite)
    }

    func testBlockedDateDoesNotCallTheServer() async {
        let repository = StubRepository()
        repository.setup.mode = .group
        let model = CoachPlanSetupModel(repository: repository)
        await model.load()

        await model.saveSettings(settings(daysFromToday: -1), today: today, calendar: calendar)
        await model.saveSettings(settings(daysFromToday: 21, distance: "marathon"), today: today, calendar: calendar)

        XCTAssertTrue(repository.saved.isEmpty)
        XCTAssertFalse(model.showsInvite)
    }

    func testPickersUseOnlyGeneratorValues() {
        XCTAssertEqual(GroupPlanRules.goals, ["habit", "speed", "distance"])
        XCTAssertEqual(GroupPlanRules.targetDistances, ["5k", "10k", "half-marathon", "marathon"])
        XCTAssertEqual(GroupPlanRules.levels, ["beginner", "intermediate", "advanced"])
        XCTAssertEqual(Array(GroupPlanRules.runsPerWeek), [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(GroupPlanRules.minWeeksBeforeRace["5k"], 4)
        XCTAssertEqual(GroupPlanRules.minWeeksBeforeRace["10k"], 6)
        XCTAssertEqual(GroupPlanRules.minWeeksBeforeRace["half-marathon"], 8)
        XCTAssertEqual(GroupPlanRules.minWeeksBeforeRace["marathon"], 12)
    }
}
