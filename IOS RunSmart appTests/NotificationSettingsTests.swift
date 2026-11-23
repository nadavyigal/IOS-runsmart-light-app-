import XCTest
@testable import IOS_RunSmart_app

/// C7.14: the coach (T5) and athlete notification settings. "Coach" is the human coach, not the AI coach.
/// The server side (M2a, C7.10) is faked here: no test touches Supabase or the system prompt.

private struct Offline: Error {}

private nonisolated final class SpyAnalytics: AnalyticsTracking, @unchecked Sendable {
    var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}
}

/// Holds a call until `open()`, so a test can look at the screen while a save is in flight.
actor NotifLatch {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

nonisolated final class NotifFakeStore: NotificationPrefsStore, @unchecked Sendable {
    var row = NotificationPrefs(timeZone: "Asia/Jerusalem")
    var failLoad = false
    var failUpdate = false
    var updateLatch: NotifLatch?
    private(set) var loadZones: [String] = []
    private(set) var updates: [NotificationPrefsPatch] = []

    func load(timeZone: String) async throws -> NotificationPrefs {
        loadZones.append(timeZone)
        if failLoad { throw Offline() }
        return row
    }

    func update(_ patch: NotificationPrefsPatch) async throws -> NotificationPrefs {
        updates.append(patch)
        if let updateLatch { await updateLatch.wait() }
        if failUpdate { throw Offline() }
        if let value = patch.coachRunFinished { row.coachRunFinished = value }
        if let value = patch.coachEveningSummary { row.coachEveningSummary = value }
        if let value = patch.coachPainFlag { row.coachPainFlag = value }
        if let value = patch.athleteCoachNote { row.athleteCoachNote = value }
        if let value = patch.athletePlanUpdates { row.athletePlanUpdates = value }
        if let value = patch.athleteBroadcasts { row.athleteBroadcasts = value }
        if let start = patch.quietStart, let time = QuietTime(postgres: start) { row.quietStart = time }
        if let end = patch.quietEnd, let time = QuietTime(postgres: end) { row.quietEnd = time }
        return row
    }
}

nonisolated final class NotifFakePermission: NotificationPermissionFlow, @unchecked Sendable {
    var current: NotificationPermissionStatus
    var afterTurnOn: NotificationPermissionStatus = .granted
    private(set) var turnOnAudiences: [NotificationSettingsAudience] = []

    init(_ status: NotificationPermissionStatus = .granted) { current = status }

    func status() async -> NotificationPermissionStatus { current }

    func turnOn(for audience: NotificationSettingsAudience) async -> NotificationPermissionStatus {
        turnOnAudiences.append(audience)
        current = afterTurnOn
        return afterTurnOn
    }
}

@MainActor
final class NotificationSettingsTests: XCTestCase {
    private func makeModel(
        _ audience: NotificationSettingsAudience = .coach,
        store: NotifFakeStore = NotifFakeStore(),
        permission: NotifFakePermission = NotifFakePermission(),
        analytics: SpyAnalytics = SpyAnalytics()
    ) -> (NotificationSettingsModel, NotifFakeStore, NotifFakePermission, SpyAnalytics) {
        let model = NotificationSettingsModel(
            audience: audience, store: store, permissionFlow: permission,
            analytics: { analytics }, timeZoneIdentifier: { "Asia/Jerusalem" }
        )
        return (model, store, permission, analytics)
    }

    // MARK: Time and rows

    func testQuietTimeReadsPostgresTimeText() {
        XCTAssertEqual(QuietTime(postgres: "21:30:00")?.minutes, 21 * 60 + 30)
        XCTAssertEqual(QuietTime(postgres: "07:00")?.minutes, 7 * 60)
        XCTAssertEqual(QuietTime(postgres: "07:00:00.5")?.minutes, 7 * 60)
        XCTAssertNil(QuietTime(postgres: "25:00:00"))
        XCTAssertNil(QuietTime(postgres: "late"))
        XCTAssertEqual(QuietTime(hour: 21, minute: 30).postgresText, "21:30:00")
        XCTAssertEqual(QuietTime(hour: 7, minute: 5).label, "07:05")
        XCTAssertEqual(QuietTime(hour: 0, minute: 1500), QuietTime(hour: 1, minute: 0))
        XCTAssertEqual(QuietTime(hour: 0, minute: -30), QuietTime(hour: 23, minute: 30))
    }

    func testRowDecodesTheServerShape() throws {
        let json = """
        {"user_id":"6f1d3c5e-3a0e-4d4b-8a40-6a2b6e0d2c11","coach_run_finished":true,"coach_evening_summary":false,
         "coach_pain_flag":true,"athlete_coach_note":true,"athlete_plan_updates":false,"athlete_broadcasts":true,
         "quiet_start":"21:30:00","quiet_end":"07:00:00","time_zone":"Asia/Jerusalem",
         "created_at":"2026-11-23T08:00:00Z","updated_at":"2026-11-23T08:00:00Z"}
        """
        let row = try JSONDecoder().decode(NotificationPrefs.self, from: Data(json.utf8))
        XCTAssertFalse(row.coachEveningSummary)
        XCTAssertFalse(row.athletePlanUpdates)
        XCTAssertEqual(row.quietStart, QuietTime(hour: 21, minute: 30))
        XCTAssertEqual(row.quietEnd, QuietTime(hour: 7, minute: 0))
        XCTAssertEqual(row.timeZone, "Asia/Jerusalem")
    }

    func testPatchSendsOnlyTheChangedFields() throws {
        func keys(_ patch: NotificationPrefsPatch) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any]
            return Set(try XCTUnwrap(object).keys)
        }
        XCTAssertEqual(try keys(.toggle(.coachPainFlag, false)), ["p_coach_pain_flag"])
        XCTAssertEqual(try keys(.toggle(.athleteBroadcasts, true)), ["p_athlete_broadcasts"])
        XCTAssertEqual(
            try keys(.quietHours(start: QuietTime(hour: 22, minute: 0), end: QuietTime(hour: 6, minute: 30))),
            ["p_quiet_start", "p_quiet_end"]
        )
    }

    func testEachAudienceSeesItsOwnThreeToggles() {
        XCTAssertEqual(NotificationSettingsAudience.coach.kinds,
                       [.coachRunFinished, .coachPainFlag, .coachEveningSummary])
        XCTAssertEqual(NotificationSettingsAudience.athlete(coachName: "Dana").kinds,
                       [.athleteCoachNote, .athletePlanUpdates, .athleteBroadcasts])
    }

    // MARK: Copy

    func testCoachCopyMatchesTheSpec() {
        let copy = NotificationSettingsCopy.self
        XCTAssertEqual(copy.coachSection, "Notify me when")
        XCTAssertEqual(copy.label(for: .coachRunFinished, coachName: nil), "An athlete finishes a run")
        XCTAssertEqual(copy.label(for: .coachPainFlag, coachName: nil), "An athlete flags pain or something off")
        XCTAssertEqual(copy.label(for: .coachEveningSummary, coachName: nil), "Evening summary at 20:00")
        XCTAssertEqual(copy.quietSection, "Quiet hours")
        XCTAssertEqual(copy.quietFooter, "Pushes during quiet hours arrive when quiet hours end.")
        XCTAssertEqual(copy.saveFailed, "Couldn't save. Try again")
        XCTAssertEqual(copy.permissionDenied, "Notifications are off for RunSmart. Turn them on in Settings.")
        XCTAssertEqual(copy.openSettings, "Open Settings")
        XCTAssertEqual(copy.quietEqualError, "Quiet hours need different start and end times")
    }

    func testAthleteLabelsIsolateTheCoachName() {
        let note = NotificationSettingsCopy.label(for: .athleteCoachNote, coachName: "דנה")
        XCTAssertEqual(note, "Notes from \u{2068}דנה\u{2069}")
        let messages = NotificationSettingsCopy.label(for: .athleteBroadcasts, coachName: "Dana")
        XCTAssertEqual(messages, "Messages from \u{2068}Dana\u{2069}")
        XCTAssertEqual(NotificationSettingsCopy.label(for: .athletePlanUpdates, coachName: "Dana"), "Plan updates")
    }

    // MARK: Flag off

    func testFlagOffMakesNoServerCallAndShowsNothing() async {
        let (model, store, permission, analytics) = makeModel()
        await model.load(v2Enabled: false)
        await model.setToggle(.coachRunFinished, to: false)
        await model.saveQuietHours()
        await model.turnOnNotifications()
        XCTAssertEqual(model.loadState, .idle)
        XCTAssertNil(model.prefs)
        XCTAssertNil(model.permission)
        XCTAssertTrue(store.loadZones.isEmpty)
        XCTAssertTrue(store.updates.isEmpty)
        XCTAssertTrue(permission.turnOnAudiences.isEmpty)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testTurningV2OffClearsTheScreen() async {
        let (model, _, _, _) = makeModel()
        await model.load(v2Enabled: true)
        XCTAssertEqual(model.loadState, .loaded)
        await model.load(v2Enabled: false)
        XCTAssertEqual(model.loadState, .idle)
        XCTAssertNil(model.prefs)
        XCTAssertFalse(model.isSaving)
    }

    // MARK: Load

    func testLoadReadsTheOwnRowWithTheDeviceTimeZone() async {
        let store = NotifFakeStore()
        store.row.coachEveningSummary = false
        store.row.quietStart = QuietTime(hour: 22, minute: 0)
        let (model, _, _, _) = makeModel(store: store)
        await model.load(v2Enabled: true)
        XCTAssertEqual(store.loadZones, ["Asia/Jerusalem"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.isOn(.coachEveningSummary))
        XCTAssertTrue(model.isOn(.coachRunFinished))
        XCTAssertEqual(model.quietFrom, QuietTime(hour: 22, minute: 0))
        XCTAssertEqual(model.quietTo, QuietTime(hour: 7, minute: 0))
    }

    func testLoadFailureShowsRetryAndRecovers() async {
        let store = NotifFakeStore()
        store.failLoad = true
        let (model, _, _, _) = makeModel(store: store)
        await model.load(v2Enabled: true)
        XCTAssertEqual(model.loadState, .failed)
        XCTAssertTrue(model.controlsDisabled)
        store.failLoad = false
        await model.load(v2Enabled: true)
        XCTAssertEqual(model.loadState, .loaded)
    }

    // MARK: Toggles (AC3)

    func testToggleSavesOnlyThatFieldAndTracksAnEnumEvent() async {
        let (model, store, _, analytics) = makeModel()
        await model.load(v2Enabled: true)
        await model.setToggle(.coachPainFlag, to: false)
        XCTAssertEqual(store.updates, [.toggle(.coachPainFlag, false)])
        XCTAssertFalse(model.isOn(.coachPainFlag))
        XCTAssertFalse(model.saveFailed)
        XCTAssertFalse(model.isSaving)
        let event = analytics.events.first
        XCTAssertEqual(event?.name, "notification_pref_changed")
        XCTAssertEqual(event?.properties["kind"] as? String, "coach_pain_flag")
        XCTAssertEqual(event?.properties["enabled"] as? Bool, false)
        XCTAssertEqual(Set(event?.properties.keys.map { $0 } ?? []), ["kind", "enabled"])
    }

    func testFailedToggleRevertsAndShowsTheRetryLine() async {
        let store = NotifFakeStore()
        let (model, _, _, analytics) = makeModel(store: store)
        await model.load(v2Enabled: true)
        store.failUpdate = true
        await model.setToggle(.coachRunFinished, to: false)
        XCTAssertTrue(model.isOn(.coachRunFinished), "the toggle goes back to the saved value")
        XCTAssertTrue(model.saveFailed)
        XCTAssertFalse(model.isSaving)
        XCTAssertTrue(analytics.events.isEmpty, "nothing was saved, so nothing is tracked")
        store.failUpdate = false
        await model.setToggle(.coachRunFinished, to: false)
        XCTAssertFalse(model.isOn(.coachRunFinished))
        XCTAssertFalse(model.saveFailed, "a new save clears the line")
    }

    func testTogglesAreDisabledWhileASaveIsInFlight() async {
        let store = NotifFakeStore()
        let latch = NotifLatch()
        store.updateLatch = latch
        let (model, _, _, _) = makeModel(store: store)
        await model.load(v2Enabled: true)

        let save = Task { await model.setToggle(.coachEveningSummary, to: false) }
        while !model.isSaving { await Task.yield() }
        XCTAssertTrue(model.controlsDisabled)
        XCTAssertTrue(model.isSavingToggle(.coachEveningSummary))
        XCTAssertFalse(model.isSavingToggle(.coachRunFinished))
        XCTAssertFalse(model.isOn(.coachEveningSummary), "shows the requested value while saving")

        await model.setToggle(.coachRunFinished, to: false)
        XCTAssertEqual(store.updates.count, 1, "a second change waits for the first")

        await latch.open()
        await save.value
        XCTAssertFalse(model.controlsDisabled)
        XCTAssertFalse(model.isSavingToggle(.coachEveningSummary))
    }

    func testAthleteTogglesSaveTheirOwnFields() async {
        let (model, store, _, _) = makeModel(.athlete(coachName: "Dana"))
        await model.load(v2Enabled: true)
        await model.setToggle(.athleteBroadcasts, to: false)
        await model.setToggle(.athletePlanUpdates, to: false)
        XCTAssertEqual(store.updates, [.toggle(.athleteBroadcasts, false), .toggle(.athletePlanUpdates, false)])
        XCTAssertEqual(model.coachName, "Dana")
        XCTAssertTrue(model.isOn(.athleteCoachNote))
    }

    // MARK: Quiet hours (AC5)

    func testEqualQuietTimesBlockSaveAndShowTheLine() async {
        let (model, store, _, _) = makeModel()
        await model.load(v2Enabled: true)
        model.quietFrom = QuietTime(hour: 7, minute: 0)
        model.quietTo = QuietTime(hour: 7, minute: 0)
        XCTAssertEqual(model.quietHoursError, "Quiet hours need different start and end times")
        XCTAssertFalse(model.canSaveQuietHours)
        await model.saveQuietHours()
        XCTAssertTrue(store.updates.isEmpty)
    }

    func testQuietHoursSaveSendsBothTimesOnce() async {
        let (model, store, _, _) = makeModel()
        await model.load(v2Enabled: true)
        XCTAssertFalse(model.canSaveQuietHours, "nothing changed yet")
        model.quietFrom = QuietTime(hour: 22, minute: 0)
        XCTAssertNil(model.quietHoursError)
        XCTAssertTrue(model.canSaveQuietHours)
        await model.saveQuietHours()
        XCTAssertEqual(store.updates, [.quietHours(start: QuietTime(hour: 22, minute: 0), end: .defaultEnd)])
        XCTAssertEqual(model.prefs?.quietStart, QuietTime(hour: 22, minute: 0))
        XCTAssertFalse(model.canSaveQuietHours, "saved, so nothing is left to save")
    }

    func testFailedQuietSaveKeepsTheChosenTimes() async {
        let store = NotifFakeStore()
        let (model, _, _, _) = makeModel(store: store)
        await model.load(v2Enabled: true)
        store.failUpdate = true
        model.quietTo = QuietTime(hour: 6, minute: 0)
        await model.saveQuietHours()
        XCTAssertTrue(model.saveFailed)
        XCTAssertEqual(model.quietTo, QuietTime(hour: 6, minute: 0))
        XCTAssertTrue(model.canSaveQuietHours, "Save can run again")
        XCTAssertEqual(model.prefs?.quietEnd, .defaultEnd, "the saved row is unchanged")
    }

    func testToggleSaveKeepsAnUnsavedQuietEdit() async {
        let (model, _, _, _) = makeModel()
        await model.load(v2Enabled: true)
        model.quietFrom = QuietTime(hour: 23, minute: 0)
        await model.setToggle(.coachRunFinished, to: false)
        XCTAssertEqual(model.quietFrom, QuietTime(hour: 23, minute: 0))
    }

    // MARK: Permission (AC4)

    func testDeniedShowsTheLineAndKeepsTogglesEditable() async {
        let permission = NotifFakePermission(.denied)
        let (model, store, _, _) = makeModel(permission: permission)
        await model.load(v2Enabled: true)
        XCTAssertEqual(model.permission, .denied)
        XCTAssertFalse(model.controlsDisabled)
        await model.setToggle(.coachRunFinished, to: false)
        XCTAssertEqual(store.updates.count, 1)
        await model.turnOnNotifications()
        XCTAssertTrue(permission.turnOnAudiences.isEmpty, "never prompt again after a denial")
    }

    func testNeverPromptedRunsThePrePermissionFlow() async {
        let permission = NotifFakePermission(.notDetermined)
        let (model, _, _, _) = makeModel(.athlete(coachName: "Dana"), permission: permission)
        await model.load(v2Enabled: true)
        XCTAssertEqual(model.permission, .notDetermined)
        await model.turnOnNotifications()
        XCTAssertEqual(permission.turnOnAudiences, [.athlete(coachName: "Dana")])
        XCTAssertEqual(model.permission, .granted)
        XCTAssertFalse(model.isTurningOn)
    }

    func testTurnOnThatEndsDeniedShowsTheDeniedLine() async {
        let permission = NotifFakePermission(.notDetermined)
        permission.afterTurnOn = .denied
        let (model, _, _, _) = makeModel(permission: permission)
        await model.load(v2Enabled: true)
        await model.turnOnNotifications()
        XCTAssertEqual(model.permission, .denied)
    }

    func testReturningFromSettingsRereadsThePermission() async {
        let permission = NotifFakePermission(.denied)
        let (model, _, _, _) = makeModel(permission: permission)
        await model.load(v2Enabled: true)
        permission.current = .granted
        await model.refreshPermission()
        XCTAssertEqual(model.permission, .granted)
    }

    func testSystemStatusMapping() {
        XCTAssertEqual(NotificationPermissionStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(NotificationPermissionStatus(.denied), .denied)
        XCTAssertEqual(NotificationPermissionStatus(.authorized), .granted)
        XCTAssertEqual(NotificationPermissionStatus(.provisional), .granted)
    }
}
