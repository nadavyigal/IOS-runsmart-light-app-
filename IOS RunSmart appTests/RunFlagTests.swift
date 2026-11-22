import Combine
import Supabase
import XCTest
@testable import IOS_RunSmart_app

/// C7.4: the athlete's "Pain / something off" flag and the coach's "Mark handled". Covers the sharing
/// gate (AC9, flag-off), the offline outbox (AC4), remove (AC5), "{Coach} saw this", the 5 s undo (AC7),
/// the link-ended path, the pain group on Coach Today (AC6) and the C7.4 events (no flag text).

private nonisolated final class FakeFlagRepository: AthleteRunFlagRepository, @unchecked Sendable {
    var createResults: [Result<RunFlagWriteResult, Error>] = []
    var removeResults: [Result<RunFlagWriteResult, Error>] = []
    var serverStates: [AthleteFlagServerState] = []
    private(set) var created: [AthleteRunFlag] = []
    private(set) var removed: [UUID] = []

    func create(_ flag: AthleteRunFlag) async throws -> RunFlagWriteResult {
        created.append(flag)
        return try (createResults.isEmpty ? .success(.saved) : createResults.removeFirst()).get()
    }

    func remove(flagID: UUID) async throws -> RunFlagWriteResult {
        removed.append(flagID)
        return try (removeResults.isEmpty ? .success(.removed) : removeResults.removeFirst()).get()
    }

    func myFlags(ids: [UUID]) async throws -> [AthleteFlagServerState] { serverStates }
}

private nonisolated final class FakeCoachFlagRepository: CoachFlagRepository, @unchecked Sendable {
    var resolveResults: [Result<Date?, Error>] = []
    private(set) var resolved: [UUID] = []

    func flags(athleteIDs: [UUID]?, includeResolved: Bool) async throws -> [CoachRunFlag] { [] }

    func resolve(flagID: UUID) async throws -> Date? {
        resolved.append(flagID)
        return try (resolveResults.isEmpty ? .success(nil) : resolveResults.removeFirst()).get()
    }
}

/// A flag store with no flags and no network, for tests that build `CoachAthleteListModel`.
nonisolated final class NoFlagsRepository: CoachFlagRepository, @unchecked Sendable {
    var failRead = false
    func flags(athleteIDs: [UUID]?, includeResolved: Bool) async throws -> [CoachRunFlag] {
        if failRead { throw URLError(.timedOut) }
        return []
    }
    func resolve(flagID: UUID) async throws -> Date? { nil }
}

extension CoachFlagStore {
    @MainActor
    static func offline(_ repository: NoFlagsRepository = NoFlagsRepository()) -> CoachFlagStore {
        CoachFlagStore(repository: repository, defaults: UserDefaults(suiteName: "CoachFlagStore.\(UUID().uuidString)")!,
                       tracker: { NoFlagEvents() }, sleep: { _ in })
    }
}

private nonisolated final class NoFlagEvents: AnalyticsTracking, @unchecked Sendable {
    func track(_ event: String, properties: [String: Any]) {}
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}
}

private nonisolated final class FlagEventSpy: AnalyticsTracking, @unchecked Sendable {
    var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}

    var names: [String] { events.map(\.name) }
}

@MainActor
final class RunFlagTests: XCTestCase {
    private let userID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let linkID = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let start = Date(timeIntervalSince1970: 1_795_000_000)

    private var defaults: UserDefaults!
    private var repository: FakeFlagRepository!
    private var spy: FlagEventSpy!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RunFlagTests.\(UUID().uuidString)")
        repository = FakeFlagRepository()
        spy = FlagEventSpy()
        clock = start
    }

    private var sharing: RunSharingContext {
        RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana",
                          sharingActive: true, sharingSince: start.addingTimeInterval(-86_400))
    }

    private func makeService() -> AthleteRunFlagService {
        AthleteRunFlagService(
            repository: repository, defaults: defaults, keyPrefix: "test.flags",
            analytics: { [spy] in spy! }, now: { [unowned self] in self.clock },
            sharing: Empty().eraseToAnyPublisher()
        )
    }

    private func sharingService() async -> AthleteRunFlagService {
        let service = makeService()
        await service.apply(sharing)
        return service
    }

    private func run() -> RecordedRun {
        RecordedRun(
            id: UUID(uuidString: "C0C0C0C0-0000-4000-8000-000000000001")!, providerActivityID: nil, source: .runSmart,
            startedAt: start, endedAt: start.addingTimeInterval(1_800), distanceMeters: 5_000,
            movingTimeSeconds: 1_800, averagePaceSecondsPerKm: 360, averageHeartRateBPM: nil, routePoints: [],
            syncedAt: start
        )
    }

    // MARK: AC9 and flag-off: hidden and silent unless sharing

    func testNothingHappensUnlessSharing() async {
        let cases: [RunSharingContext] = [
            .off,
            RunSharingContext(v2Enabled: false, userID: userID, linkID: linkID, coachName: "Dana"),
            RunSharingContext(v2Enabled: true, userID: userID, linkID: nil, coachName: nil),   // solo
            RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana")  // no ack
        ]
        for context in cases {
            let service = makeService()
            await service.apply(context)
            XCTAssertFalse(service.isSharing)
            XCTAssertNil(service.coachName, "the row and '{Coach} will see this' stay hidden")
            await service.send(kind: .pain, note: "knee", run: run())
            XCTAssertTrue(service.flags.isEmpty)
            XCTAssertTrue(service.pending.isEmpty)
        }
        XCTAssertTrue(repository.created.isEmpty, "no v2 RPC call")
        XCTAssertTrue(spy.events.isEmpty, "no v2 event")
    }

    // MARK: AC1, AC2, AC3: send with and without a run

    func testSendWithRunCallsTheServerAndShowsSent() async throws {
        let service = await sharingService()
        await service.send(kind: .pain, note: "  left knee, last 2 reps  ", run: run())

        let sent = try XCTUnwrap(repository.created.first)
        XCTAssertEqual(sent.kind, .pain)
        XCTAssertEqual(sent.note, "left knee, last 2 reps")
        XCTAssertEqual(sent.runKey, RunShareKey(run: run()))
        XCTAssertEqual(service.flags(for: run()).map(\.status), [.sent])
        XCTAssertTrue(service.flags(for: nil).isEmpty, "a run flag is not a Today flag")
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertEqual(spy.names, ["flag_created"])
        XCTAssertEqual(spy.events[0].properties["kind"] as? String, "pain")
        XCTAssertEqual(spy.events[0].properties["has_run"] as? Bool, true)
    }

    func testRunlessFlagFromToday() async throws {
        let service = await sharingService()
        await service.send(kind: .off, note: "", run: nil)
        let sent = try XCTUnwrap(repository.created.first)
        XCTAssertNil(sent.runKey)
        XCTAssertNil(sent.note, "a blank note is not sent")
        XCTAssertEqual(service.flags(for: nil).count, 1)
        XCTAssertEqual(spy.events.last?.properties["has_run"] as? Bool, false)
    }

    func testNoteIsCappedAt500Characters() async throws {
        let service = await sharingService()
        await service.send(kind: .off, note: String(repeating: "x", count: 600), run: nil)
        XCTAssertEqual(try XCTUnwrap(repository.created.first?.note).count, RunFlagCopy.noteLimit)
    }

    // MARK: AC4: offline outbox, idempotent by client id

    func testOfflineFlagWaitsSurvivesRelaunchAndKeepsItsID() async throws {
        repository.createResults = [.failure(URLError(.notConnectedToInternet))]
        let service = await sharingService()
        await service.send(kind: .pain, note: "knee", run: run())
        let firstID = try XCTUnwrap(repository.created.first?.id)
        XCTAssertEqual(service.flags(for: run()).map(\.status), [.waiting], "Waiting to send")
        XCTAssertEqual(service.pending.count, 1)

        // Killed and relaunched: the queue and the flag come back from disk.
        let relaunched = makeService()
        XCTAssertEqual(relaunched.pending.count, 1)
        await relaunched.apply(sharing)
        XCTAssertEqual(repository.created.map(\.id), [firstID, firstID], "the retry sends the same p_id")
        XCTAssertTrue(relaunched.pending.isEmpty)
        XCTAssertEqual(relaunched.flags.first?.status, .sent)
    }

    func testKillSwitchKeepsTheFlagQueued() async {
        repository.createResults = [.failure(PostgrestError(code: "P0001", message: "v2_unavailable"))]
        let service = await sharingService()
        await service.send(kind: .pain, note: "", run: nil)
        XCTAssertEqual(service.pending.count, 1, "no athlete data is dropped while the switch is on")
        XCTAssertEqual(service.flags.first?.status, .waiting)
    }

    func testLinkEndedDropsTheFlagAndSaysSoOnce() async {
        repository.createResults = [.failure(PostgrestError(code: "P0001", message: "link_inactive"))]
        let service = await sharingService()
        await service.send(kind: .pain, note: "knee", run: run())
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertTrue(service.flags.isEmpty, "nothing reached the coach, so nothing is shown as sent")
        XCTAssertTrue(service.linkGoneNotice)
        XCTAssertEqual(RunFlagCopy.notSent(coach: "Dana"),
                       "You're no longer linked to \u{2068}Dana\u{2069}, so this flag wasn't sent.")
    }

    // MARK: AC5: remove until handled, and "{Coach} saw this"

    func testRemoveSentFlag() async throws {
        let service = await sharingService()
        await service.send(kind: .pain, note: "knee", run: run())
        let flag = try XCTUnwrap(service.flags.first)
        await service.remove(flag)
        XCTAssertEqual(repository.removed, [flag.id])
        XCTAssertTrue(service.flags.isEmpty)
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertEqual(spy.names, ["flag_created", "flag_removed"])
    }

    func testRemovingAnUnsentFlagNeverCallsTheServer() async throws {
        repository.createResults = [.failure(URLError(.notConnectedToInternet))]
        let service = await sharingService()
        await service.send(kind: .off, note: "", run: nil)
        await service.remove(try XCTUnwrap(service.flags.first))
        XCTAssertTrue(repository.removed.isEmpty)
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertTrue(service.flags.isEmpty)
    }

    func testCoachSawThisHidesRemove() async throws {
        let service = await sharingService()
        await service.send(kind: .pain, note: "knee", run: run())
        let id = try XCTUnwrap(service.flags.first?.id)
        repository.serverStates = [AthleteFlagServerState(id: id, resolvedAt: start)]
        await service.refreshStatuses()
        let flag = try XCTUnwrap(service.flags.first)
        XCTAssertEqual(flag.status, .seen)
        XCTAssertFalse(flag.canRemove)
        XCTAssertEqual(RunFlagCopy.saw(coach: "Dana"), "\u{2068}Dana\u{2069} saw this")
        // Removing a handled flag does nothing.
        await service.remove(flag)
        XCTAssertTrue(repository.removed.isEmpty)
    }

    func testEmptyStatusReadKeepsSentFlags() async throws {
        let service = await sharingService()
        await service.send(kind: .pain, note: "knee", run: run())
        repository.serverStates = []
        await service.refreshStatuses()
        XCTAssertEqual(service.flags.map(\.status), [.sent], "an empty read never wipes a sent flag")
    }

    func testLateRemoveOfAResolvedFlagIsDropped() {
        XCTAssertEqual(RunFlagFailure.classify(PostgrestError(code: "P0001", message: "flag_resolved")), .alreadyResolved)
        XCTAssertEqual(RunFlagFailure.classify(PostgrestError(code: "P0001", message: "v2_unavailable")), .keep)
        XCTAssertEqual(RunFlagFailure.classify(PostgrestError(code: "P0001", message: "consent_required")), .drop)
        XCTAssertEqual(RunFlagFailure.classify(URLError(.timedOut)), .keep)
    }

    // MARK: AC3: copy

    func testAthleteCopyHasTheSafetyLineAndNoPromise() {
        XCTAssertEqual(RunFlagCopy.safety, "If the pain is sharp or doesn't go away, check with a doctor or physio.")
        XCTAssertEqual(RunFlagKind.off.athleteLabel, "Something else")
        XCTAssertEqual(RunFlagKind.off.coachLabel, "Something off")
        XCTAssertEqual(RunFlagCopy.send(coach: "Dana"), "Send to \u{2068}Dana\u{2069}")
        XCTAssertEqual(RunFlagCopy.sent(coach: "Dana"), "Sent to \u{2068}Dana\u{2069}")
        let all = [RunFlagCopy.safety, RunFlagCopy.sent(coach: "Dana"), RunFlagCopy.willSee(coach: "Dana"),
                   RunFlagCopy.saw(coach: "Dana")].joined(separator: " ").lowercased()
        for promise in ["will call", "will reply", "within", "soon", "hours"] {
            XCTAssertFalse(all.contains(promise), "no response-time promise: \(promise)")
        }
    }

    // MARK: AC7: Mark handled with a 5 s undo

    private func coachFlag(_ kind: RunFlagKind = .pain, athlete: UUID? = nil, hoursAgo: Double = 2,
                           note: String? = nil) -> CoachRunFlag {
        CoachRunFlag(id: UUID(), athleteID: athlete ?? userID, kind: kind, note: note,
                     createdAt: start.addingTimeInterval(-hoursAgo * 3600))
    }

    private func makeStore(_ repo: FakeCoachFlagRepository) -> CoachFlagStore {
        CoachFlagStore(repository: repo, defaults: defaults, key: "test.resolves", tracker: { [spy] in spy! },
                       now: { [unowned self] in self.clock }, sleep: { _ in })
    }

    func testMarkHandledWaitsFiveSecondsAndCanBeUndone() async {
        let repo = FakeCoachFlagRepository()
        let store = makeStore(repo)
        let flag = coachFlag()
        store.markHandled(flag, coachID: coachID)
        XCTAssertEqual(store.toastFlagID, flag.id, "Marked handled · Undo")
        XCTAssertTrue(store.openFlags([flag]).isEmpty, "the row leaves the pain group at once")

        await store.flush(coachID: coachID)
        XCTAssertTrue(repo.resolved.isEmpty, "nothing leaves the phone inside the undo window")

        store.undo(flag.id)
        XCTAssertEqual(store.openFlags([flag]).map(\.id), [flag.id], "undo restores the open state locally")
        XCTAssertNil(store.toastFlagID)
        clock = start.addingTimeInterval(10)
        await store.flush(coachID: coachID)
        XCTAssertTrue(repo.resolved.isEmpty, "an undone resolve is never sent: no un-resolve RPC needed")
    }

    func testMarkHandledIsSentAfterTheWindowAndTracksMinutesOpen() async {
        let repo = FakeCoachFlagRepository()
        repo.resolveResults = [.success(start.addingTimeInterval(6))]
        let store = makeStore(repo)
        let flag = coachFlag(hoursAgo: 2)
        store.markHandled(flag, coachID: coachID)
        clock = start.addingTimeInterval(CoachFlagStore.undoWindow + 1)
        store.undo(flag.id)   // too late: the window has closed
        await store.flush(coachID: coachID)
        XCTAssertEqual(repo.resolved, [flag.id])
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(spy.names, ["flag_resolved"])
        XCTAssertEqual(spy.events[0].properties["minutes_open"] as? Int, 120)
    }

    func testQueuedResolveSurvivesRelaunch() async {
        let repo = FakeCoachFlagRepository()
        let flag = coachFlag()
        makeStore(repo).markHandled(flag, coachID: coachID)
        let relaunched = makeStore(repo)
        XCTAssertTrue(relaunched.isWaiting(flag.id), "Waiting to sync")
        clock = start.addingTimeInterval(60)
        await relaunched.flush(coachID: coachID)
        XCTAssertEqual(repo.resolved, [flag.id])
    }

    func testResolveKeepsOnKillSwitchAndDropsWhenTheAthleteLeft() async {
        let repo = FakeCoachFlagRepository()
        repo.resolveResults = [.failure(PostgrestError(code: "P0001", message: "v2_unavailable")),
                               .failure(PostgrestError(code: "P0001", message: "link_inactive"))]
        let store = makeStore(repo)
        let flag = coachFlag()
        store.markHandled(flag, coachID: coachID)
        clock = start.addingTimeInterval(60)
        await store.flush(coachID: coachID)
        XCTAssertTrue(store.isWaiting(flag.id), "kept while the switch is on")
        await store.flush(coachID: coachID)
        XCTAssertFalse(store.isWaiting(flag.id))
        XCTAssertEqual(store.failedAthletes, [userID])
        XCTAssertEqual(RunFlagCopy.actionFailed(athlete: "Yoni"),
                       "1 action couldn't be saved: \u{2068}Yoni\u{2069} is no longer linked to you.")
    }

    // MARK: AC6: the pain group on Coach Today

    private func todaySnapshot(_ athletes: [CoachAthleteSummary], flags: [CoachRunFlag], flagsLoaded: Bool = true) -> CoachTodaySnapshot {
        let week = CoachAthleteWeek(now: start, locale: Locale(identifier: "en_GB"), timeZone: .gmt)
        return CoachTodaySnapshot.make(athletes: athletes, workouts: [], runs: [], flags: flags, flagsLoaded: flagsLoaded,
                                       now: start, week: week, locale: Locale(identifier: "en_GB"))
    }

    private func athlete(_ index: Int, _ name: String, plan: Bool = true) -> CoachAthleteSummary {
        CoachAthleteSummary(athleteID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
                            displayName: name, linkedAt: start.addingTimeInterval(-86_400 * 30), hasActivePlan: plan)
    }

    func testPainGroupComesFirstWithPainBeforeOffAndOldestFirst() {
        let yoni = athlete(1, "Yoni"), noa = athlete(2, "Noa"), avi = athlete(3, "Avi"), maya = athlete(4, "Maya", plan: false)
        let flags = [
            coachFlag(.off, athlete: noa.athleteID, hoursAgo: 30),
            coachFlag(.pain, athlete: yoni.athleteID, hoursAgo: 3, note: String(repeating: "k", count: 80)),
            coachFlag(.pain, athlete: avi.athleteID, hoursAgo: 10),
            coachFlag(.off, athlete: avi.athleteID, hoursAgo: 1),
            coachFlag(.off, athlete: maya.athleteID, hoursAgo: 5)
        ]
        let result = todaySnapshot([yoni, noa, avi, maya], flags: flags)
        XCTAssertEqual(result.groups.first, .pain)
        let pain = result.rows(in: .pain)
        XCTAssertEqual(pain.map(\.name), ["Avi", "Yoni", "Noa", "Maya"], "pain before off, then the oldest flag first")
        XCTAssertEqual(pain[0].chipText, "Pain · 2", "several open flags")
        XCTAssertEqual(pain[0].flags.count, 2, "each flag stays separate for the day detail")
        XCTAssertEqual(pain[1].chipText, "Pain")
        XCTAssertEqual(pain[1].flagPreview, String(repeating: "k", count: 60) + "…", "60-character preview")
        XCTAssertEqual(pain[2].chipText, "Something off")
        XCTAssertEqual(pain[3].reason, .somethingOff, "an athlete with no plan still shows the flag")
        XCTAssertEqual(CoachTodayGroup.pain.title(count: 4), "Pain or something off (4)")
        XCTAssertEqual(result.needCount, 4, "flags count as needing the coach")
        XCTAssertTrue(pain[1].spokenSentence.hasPrefix("Yoni. Pain flagged "))
    }

    func testResolvedFlagsAndFailedReadShowNoPainGroup() {
        let yoni = athlete(1, "Yoni")
        var resolved = coachFlag(athlete: yoni.athleteID)
        resolved.resolvedAt = start
        XCTAssertFalse(todaySnapshot([yoni], flags: [resolved]).groups.contains(.pain))
        let failed = todaySnapshot([yoni], flags: [], flagsLoaded: false)
        XCTAssertFalse(failed.flagsLoaded)
        XCTAssertFalse(failed.groups.contains(.pain), "the flag group is not shown as empty")
        XCTAssertEqual(RunFlagCopy.flagsFailed, "Pain flags didn't load. Try again.")
    }

    func testDeletedRunAndCoachCopy() {
        let flag = CoachRunFlag(id: UUID(), athleteID: userID, runDeleted: true, kind: .off,
                                createdAt: Date(timeIntervalSince1970: 1_795_000_000))
        let row = todaySnapshot([athlete(1, "Yoni")], flags: [CoachRunFlag(
            id: flag.id, athleteID: athlete(1, "Yoni").athleteID, runDeleted: true, kind: .off, createdAt: flag.createdAt
        )]).rows[0]
        XCTAssertEqual(row.flagPreview, "Run deleted")
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = .gmt
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(RunFlagCopy.title(.off, date: flag.createdAt, calendar: gmt, locale: en), "Something off · Nov 18")
        XCTAssertEqual(RunFlagCopy.handledByYou(flag.createdAt, calendar: gmt, locale: en), "Handled by you · Nov 18")
        XCTAssertEqual(RunFlagCopy.markedHandledToast, "Marked handled · Undo")
    }

    // MARK: Analytics: ids, enums and minutes only

    func testFlagEventsCarryNoText() {
        let events: [CoachV2Analytics.Event] = [
            .flagCreated(kind: .pain, hasRun: true), .flagCreated(kind: .off, hasRun: false),
            .flagRemoved, .flagResolved(minutesOpen: 42)
        ]
        XCTAssertEqual(events.map(\.name), ["flag_created", "flag_created", "flag_removed", "flag_resolved"])
        for event in events {
            for (key, value) in event.properties {
                switch value {
                case .kind(let raw):
                    XCTAssertTrue(RunFlagKind(rawValue: raw) != nil, "\(key) is an enum value")
                case .flag, .count, .seconds, .id:
                    break
                }
            }
        }
    }
}
