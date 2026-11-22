import XCTest
@testable import IOS_RunSmart_app

/// C7.3: effort (RPE) and run notes are shared with the human coach only while v2 is on,
/// the athlete is linked and has accepted the v2 copy (D7). Covers the sync rules, the
/// hide toggle, the one-time RPE backfill, the offline outbox and the C7.3 events.

private struct ServerError: Error, CustomStringConvertible {
    let description: String
}

private nonisolated final class FakeSharingRepository: AthleteRunSharingRepository, @unchecked Sendable {
    var results: [Result<RunShareWriteResult, Error>] = []
    var defaultResult: Result<RunShareWriteResult, Error> = .success(.saved)
    var serverRow = true
    private(set) var writes: [(change: RunShareChange, key: RunShareKey)] = []

    func write(_ change: RunShareChange, key: RunShareKey) async throws -> RunShareWriteResult {
        writes.append((change, key))
        let next = results.isEmpty ? defaultResult : results.removeFirst()
        return try next.get()
    }

    func hasServerRow(_ key: RunShareKey, ownerID: UUID) async throws -> Bool { serverRow }
}

private final class StubConsent: CoachConsentRepository, @unchecked Sendable {
    var status: CoachConsentStatus?
    private(set) var statusCalls = 0

    func status() async throws -> CoachConsentStatus? {
        statusCalls += 1
        return status
    }

    func acknowledge() async throws {}

    nonisolated deinit {}
}

private nonisolated final class EventSpy: AnalyticsTracking, @unchecked Sendable {
    var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}

    var names: [String] { events.map(\.name) }
}

final class AthleteRunSharingTests: XCTestCase {
    private let userID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let linkID = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let ackTime = Date(timeIntervalSince1970: 1_795_000_000)

    private var defaults: UserDefaults!
    private var repository: FakeSharingRepository!
    private var consent: StubConsent!
    private var spy: EventSpy!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AthleteRunSharingTests.\(UUID().uuidString)")
        repository = FakeSharingRepository()
        consent = StubConsent()
        spy = EventSpy()
        clock = ackTime
    }

    private func makeService() -> AthleteRunSharingService {
        AthleteRunSharingService(
            consent: consent,
            repository: repository,
            defaults: defaults,
            analytics: { [spy] in spy! },
            now: { [unowned self] in self.clock }
        )
    }

    private func status(sharing: Bool) -> CoachConsentStatus {
        CoachConsentStatus(linkID: linkID, coachName: "Dana", linkIsV2: true, needsV2Ack: !sharing, sharingActive: sharing)
    }

    private func run(startedAt: Date, rpe: Int? = nil, id: UUID = UUID()) -> RecordedRun {
        var run = RecordedRun(
            id: id,
            providerActivityID: nil,
            source: .runSmart,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: startedAt
        )
        run.rpe = rpe
        return run
    }

    private func sharingService(localRuns: [RecordedRun] = []) async -> AthleteRunSharingService {
        consent.status = status(sharing: true)
        let service = makeService()
        await service.refresh(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana", localRuns: localRuns)
        return service
    }

    // MARK: Policy (D7)

    func testPolicySharesNothingUnlessV2LinkedAndAccepted() {
        let since = ackTime
        let full = RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana",
                                     sharingActive: true, sharingSince: since)
        let after = since.addingTimeInterval(60)
        XCTAssertTrue(RunSharingPolicy.sharesNote(runStartedAt: after, context: full))
        XCTAssertTrue(RunSharingPolicy.sharesRPE(runStartedAt: after, context: full))

        var flagOff = full; flagOff.v2Enabled = false
        var solo = full; solo.linkID = nil
        var noAck = full; noAck.sharingActive = false
        var signedOut = full; signedOut.userID = nil
        for context in [flagOff, solo, noAck, signedOut] {
            XCTAssertFalse(RunSharingPolicy.sharesNote(runStartedAt: after, context: context))
            XCTAssertFalse(RunSharingPolicy.sharesRPE(runStartedAt: after, context: context))
            XCTAssertFalse(RunSharingPolicy.shouldSync(.noteHidden(true), runStartedAt: after, context: context))
        }
    }

    func testPolicyNeverSharesNotesBeforeTheAckAndLimitsRPEToFourteenDays() {
        let context = RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana",
                                        sharingActive: true, sharingSince: ackTime)
        let beforeAck = ackTime.addingTimeInterval(-60)
        XCTAssertFalse(RunSharingPolicy.sharesNote(runStartedAt: beforeAck, context: context))
        XCTAssertTrue(RunSharingPolicy.sharesRPE(runStartedAt: beforeAck, context: context))
        let thirteenDays = ackTime.addingTimeInterval(-13 * 86_400)
        let fifteenDays = ackTime.addingTimeInterval(-15 * 86_400)
        XCTAssertTrue(RunSharingPolicy.sharesRPE(runStartedAt: thirteenDays, context: context))
        XCTAssertFalse(RunSharingPolicy.sharesRPE(runStartedAt: fifteenDays, context: context))
    }

    // MARK: AC2: nothing leaves the phone without sharing

    func testFlagOffMakesNoCallQueuesNothingAndSendsNoEvent() async {
        let service = makeService()
        await service.refresh(v2Enabled: false, userID: userID, linkID: linkID, coachName: "Dana",
                              localRuns: [run(startedAt: ackTime, rpe: 6)])
        await service.record(.rpe(7), for: run(startedAt: ackTime))
        await service.record(.note("Felt strong"), for: run(startedAt: ackTime))
        await service.record(.noteHidden(true), for: run(startedAt: ackTime))

        XCTAssertEqual(consent.statusCalls, 0)
        XCTAssertTrue(repository.writes.isEmpty)
        XCTAssertTrue(service.outbox.pending.isEmpty)
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testSoloAthleteMakesNoCall() async {
        let service = makeService()
        await service.refresh(v2Enabled: true, userID: userID, linkID: nil, coachName: nil, localRuns: [])
        await service.record(.rpe(7), for: run(startedAt: ackTime))
        XCTAssertEqual(consent.statusCalls, 0)
        XCTAssertTrue(repository.writes.isEmpty)
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testBeforeTheAckEffortAndNotesStayOnThePhone() async {
        consent.status = status(sharing: false)
        let service = makeService()
        await service.refresh(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana",
                              localRuns: [run(startedAt: ackTime.addingTimeInterval(-3_600), rpe: 6)])
        clock = ackTime.addingTimeInterval(7_200)
        await service.record(.rpe(7), for: run(startedAt: ackTime.addingTimeInterval(3_600)))
        await service.record(.note("Felt strong"), for: run(startedAt: ackTime.addingTimeInterval(3_600)))

        XCTAssertTrue(repository.writes.isEmpty, "no backfill and no sync before the ack")
        XCTAssertEqual(spy.names, ["run_rpe_set", "run_note_saved"])
        XCTAssertEqual(spy.events.map { $0.properties["shared"] as? Bool }, [false, false])
    }

    // MARK: AC1 + AC3: sync after the ack

    func testAfterTheAckEffortAndNoteSyncForANewRun() async {
        let service = await sharingService()
        clock = ackTime.addingTimeInterval(7_200)
        let newRun = run(startedAt: ackTime.addingTimeInterval(3_600))
        await service.record(.rpe(7), for: newRun)
        await service.record(.note("Felt strong"), for: newRun)

        XCTAssertEqual(repository.writes.map(\.change), [.rpe(7), .note("Felt strong")])
        XCTAssertEqual(repository.writes.first?.key, RunShareKey(sourceProvider: "runsmart_ios", sourceActivityID: newRun.id.uuidString))
        XCTAssertTrue(service.outbox.pending.isEmpty)
        XCTAssertEqual(spy.events.filter { $0.name == "run_rpe_set" }.first?.properties["shared"] as? Bool, true)
    }

    func testANoteOnARunBeforeTheAckIsNeverSyncedEvenWhenEditedLater() async {
        let service = await sharingService()
        clock = ackTime.addingTimeInterval(86_400)
        let oldRun = run(startedAt: ackTime.addingTimeInterval(-86_400))
        await service.record(.note("edited after the ack"), for: oldRun)
        await service.record(.rpe(5), for: oldRun)

        XCTAssertEqual(repository.writes.map(\.change), [.rpe(5)], "effort inside 14 days syncs, the note never does")
        XCTAssertFalse(service.sharesNote(oldRun))
    }

    func testBackfillSyncsRPEOnlyForTheLastFourteenDaysOncePerLink() async {
        let recent = run(startedAt: ackTime.addingTimeInterval(-2 * 86_400), rpe: 6)
        var withNote = run(startedAt: ackTime.addingTimeInterval(-3 * 86_400), rpe: 4)
        withNote.notes = "old private note"
        let unrated = run(startedAt: ackTime.addingTimeInterval(-86_400))
        let tooOld = run(startedAt: ackTime.addingTimeInterval(-20 * 86_400), rpe: 8)

        let service = await sharingService(localRuns: [recent, withNote, unrated, tooOld])

        XCTAssertEqual(repository.writes.count, 2)
        XCTAssertTrue(repository.writes.allSatisfy { if case .rpe = $0.change { true } else { false } },
                      "the backfill never sends a note")
        XCTAssertEqual(Set(repository.writes.map(\.change)), [.rpe(6), .rpe(4)])
        XCTAssertEqual(spy.events.filter { $0.name == "rpe_backfill_done" }.first?.properties["count"] as? Int, 2)

        await service.refresh(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana",
                              localRuns: [recent, withNote])
        XCTAssertEqual(repository.writes.count, 2, "runs once per link")
        XCTAssertEqual(spy.names.filter { $0 == "rpe_backfill_done" }.count, 1)
    }

    func testBackfillFailureStaysQueuedAndRetries() async {
        repository.results = [.failure(ServerError(description: "offline"))]
        let service = await sharingService(localRuns: [run(startedAt: ackTime.addingTimeInterval(-86_400), rpe: 6)])
        XCTAssertEqual(service.outbox.pending.count, 1)

        await service.flush()
        XCTAssertTrue(service.outbox.pending.isEmpty)
        XCTAssertEqual(repository.writes.count, 2)
    }

    // MARK: AC5: hide note from the coach

    func testHideIsStoredOnThePhoneAndSent() async {
        let service = await sharingService()
        clock = ackTime.addingTimeInterval(7_200)
        let newRun = run(startedAt: ackTime.addingTimeInterval(3_600))
        await service.record(.noteHidden(true), for: newRun)

        XCTAssertTrue(service.isNoteHidden(newRun))
        XCTAssertEqual(repository.writes.map(\.change), [.noteHidden(true)])
        XCTAssertEqual(spy.events.last?.name, "run_note_hidden_toggled")
        XCTAssertEqual(spy.events.last?.properties["hidden"] as? Bool, true)

        await service.record(.noteHidden(false), for: newRun)
        XCTAssertFalse(service.isNoteHidden(newRun))
        XCTAssertEqual(repository.writes.last?.change, .noteHidden(false))
    }

    // MARK: Offline outbox

    func testKillSwitchKeepsChangesQueuedAcrossARelaunchAndFlushesOnce() async {
        let outbox = AthleteRunSharingOutbox(defaults: defaults)
        let key = RunShareKey(sourceProvider: "runsmart_ios", sourceActivityID: "RUN-1")
        outbox.enqueue(PendingRunShare(id: UUID(), ownerID: userID, key: key, change: .rpe(5), createdAt: ackTime))
        outbox.enqueue(PendingRunShare(id: UUID(), ownerID: userID, key: key, change: .rpe(6), createdAt: ackTime))
        outbox.enqueue(PendingRunShare(id: UUID(), ownerID: userID, key: key, change: .note("Hi"), createdAt: ackTime))
        XCTAssertEqual(outbox.pending.map(\.change), [.rpe(6), .note("Hi")], "only the newest change per kind")

        repository.defaultResult = .failure(ServerError(description: "PostgrestError: v2_unavailable"))
        let report = await outbox.flush(ownerID: userID, repository: repository, now: ackTime) { _ in true }
        XCTAssertEqual(report.kept, 1)
        XCTAssertEqual(outbox.pending.count, 2, "kill switch: nothing is dropped")
        XCTAssertTrue(outbox.isWaiting(ownerID: userID, key: key))

        // App killed and relaunched: the queue comes back from storage.
        let relaunched = AthleteRunSharingOutbox(defaults: defaults)
        XCTAssertEqual(relaunched.pending.map(\.change), [.rpe(6), .note("Hi")])

        repository.defaultResult = .success(.saved)
        let writesBefore = repository.writes.count
        await relaunched.flush(ownerID: userID, repository: repository, now: ackTime) { _ in true }
        await relaunched.flush(ownerID: userID, repository: repository, now: ackTime) { _ in true }
        XCTAssertTrue(relaunched.pending.isEmpty)
        XCTAssertEqual(repository.writes.count - writesBefore, 2, "two flushes send each change once")
    }

    func testEndedLinkOrMissingConsentDropsTheChange() async {
        let outbox = AthleteRunSharingOutbox(defaults: defaults)
        for token in ["link_inactive", "consent_required", "note_before_consent", "rpe_before_window"] {
            outbox.enqueue(PendingRunShare(id: UUID(), ownerID: userID,
                                           key: RunShareKey(sourceProvider: "runsmart_ios", sourceActivityID: token),
                                           change: .rpe(5), createdAt: ackTime))
            repository.results.append(.failure(ServerError(description: token)))
        }
        let report = await outbox.flush(ownerID: userID, repository: repository, now: ackTime) { _ in true }
        XCTAssertEqual(report.dropped, 4)
        XCTAssertTrue(outbox.pending.isEmpty)
        XCTAssertEqual(RunShareFailure.classify(ServerError(description: "v2_unavailable")), .keep)
        XCTAssertEqual(RunShareFailure.classify(URLError(.notConnectedToInternet)), .keep)
    }

    func testARunWithoutAServerRowWaitsThenGivesUp() async {
        let outbox = AthleteRunSharingOutbox(defaults: defaults)
        outbox.enqueue(PendingRunShare(id: UUID(), ownerID: userID,
                                       key: RunShareKey(sourceProvider: "runsmart_ios", sourceActivityID: "NO-ROW"),
                                       change: .rpe(5), createdAt: ackTime))
        repository.defaultResult = .success(.missing)
        await outbox.flush(ownerID: userID, repository: repository, now: ackTime.addingTimeInterval(3_600)) { _ in true }
        XCTAssertEqual(outbox.pending.count, 1)
        await outbox.flush(ownerID: userID, repository: repository, now: ackTime.addingTimeInterval(15 * 86_400)) { _ in true }
        XCTAssertTrue(outbox.pending.isEmpty)
    }

    func testAnotherAccountsQueueIsNotSent() async {
        let outbox = AthleteRunSharingOutbox(defaults: defaults)
        outbox.enqueue(PendingRunShare(id: UUID(), ownerID: UUID(),
                                       key: RunShareKey(sourceProvider: "runsmart_ios", sourceActivityID: "OTHER"),
                                       change: .rpe(5), createdAt: ackTime))
        await outbox.flush(ownerID: userID, repository: repository, now: ackTime) { _ in true }
        XCTAssertTrue(repository.writes.isEmpty)
    }

    // MARK: AC8: the visibility line needs a server row

    func testVisibilityNeedsAServerRow() async {
        let service = await sharingService()
        let newRun = run(startedAt: ackTime.addingTimeInterval(3_600))
        XCTAssertFalse(service.sharesRPE(newRun), "unknown server row: line hidden")

        repository.serverRow = false
        await service.resolveServerRow(for: newRun)
        XCTAssertFalse(service.sharesRPE(newRun))

        repository.serverRow = true
        await service.resolveServerRow(for: newRun)
        XCTAssertTrue(service.sharesRPE(newRun))
        XCTAssertTrue(service.sharesNote(newRun))
    }

    // MARK: Analytics (v1.3 section 3.8)

    func testEventsCarryOnlyFlagsAndCountsNeverValuesOrText() async {
        let service = await sharingService(localRuns: [run(startedAt: ackTime.addingTimeInterval(-86_400), rpe: 9)])
        clock = ackTime.addingTimeInterval(7_200)
        let newRun = run(startedAt: ackTime.addingTimeInterval(3_600))
        await service.record(.rpe(7), for: newRun)
        await service.record(.note("Knee felt sore"), for: newRun)
        await service.record(.noteHidden(true), for: newRun)

        XCTAssertEqual(spy.names, ["rpe_backfill_done", "run_rpe_set", "run_note_saved", "run_note_hidden_toggled"])
        for event in spy.events {
            for (key, value) in event.properties {
                XCTAssertTrue(value is Bool || value is Int, "\(event.name).\(key) must be a flag or a count")
                XCTAssertNotEqual(value as? Int, 7, "RPE value leaked in \(event.name)")
                XCTAssertNil(value as? String, "text in \(event.name)")
            }
        }
    }

    // MARK: Coach copy (AC4)

    func testCoachDayDetailCopy() {
        XCTAssertEqual(CoachRunSharingCopy.effort(7), "Effort 7/10")
        XCTAssertNil(CoachRunSharingCopy.effort(nil))
        XCTAssertNil(CoachRunSharingCopy.effort(11))
        XCTAssertEqual(CoachRunSharingCopy.quotedNote("Felt strong"), "\u{201C}Felt strong\u{201D}")
        XCTAssertEqual(CoachRunSharingCopy.attribution(athlete: "נועה"), "\u{2014} \u{2068}נועה\u{2069}")
    }

    func testRunSummaryFromAServerWithoutM1aDecodesAsNotShared() throws {
        let payload = Data("""
        {"id": 1, "athlete_id": "BBBBBBBB-0000-4000-8000-00000000000B", "workout_id": null,
         "completed_at": "2026-11-16T00:30:00+00:00", "type": "easy", "distance_km": 5,
         "duration_seconds": 1800, "pace": 360, "average_heart_rate": null, "source": "runsmart_ios"}
        """.utf8)
        let summary = try JSONDecoder().decode(CoachRunSummary.self, from: payload)
        XCTAssertNil(summary.rpe)
        XCTAssertFalse(summary.hasNote)
    }
}
