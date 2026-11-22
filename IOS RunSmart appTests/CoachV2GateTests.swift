import XCTest
@testable import IOS_RunSmart_app

/// C7.0 (with C7.12 and the N1 = B allowlist): `coachV2Enabled`, the 15-minute flag
/// cache, the capability report, and the roster's "needs the latest RunSmart" line.
/// "Coach" is the human coach, not the AI coach.

private struct Offline: Error {}

private final class StubGateRepository: CoachV2GateRepository, @unchecked Sendable {
    var flags: Result<[String: Bool], Error> = .success(["coach_v2": true, "coach_v2_push": true, "coach_v2_ai": true])
    var pilot: Result<Bool, Error> = .success(false)
    var reportResult: Result<Void, Error> = .success(())
    var roster: Result<[UUID: Bool], Error> = .success([:])
    private(set) var flagReads = 0
    private(set) var pilotReads = 0
    private(set) var reports: [CoachV2CapabilityReport] = []
    private(set) var rosterReads = 0

    func runtimeFlags() async throws -> [String: Bool] {
        flagReads += 1
        return try flags.get()
    }

    func pilotAccess() async throws -> Bool {
        pilotReads += 1
        return try pilot.get()
    }

    func reportCapabilities(_ report: CoachV2CapabilityReport) async throws {
        reports.append(report)
        try reportResult.get()
    }

    func rosterStatus() async throws -> [UUID: Bool] {
        rosterReads += 1
        return try roster.get()
    }

    nonisolated deinit {}
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_795_000_000)
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
    nonisolated deinit {}
}

@MainActor
final class CoachV2GateTests: XCTestCase {
    private let userA = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let userB = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "CoachV2GateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeGate(
        _ repository: StubGateRepository,
        channel: CoachV2Channel,
        arguments: [String] = [],
        clock: Clock = Clock()
    ) -> CoachV2Gate {
        CoachV2Gate(
            repository: repository,
            cache: CoachV2FlagCache(defaults: defaults),
            channel: channel,
            processArguments: arguments,
            appVersion: "1.2.7",
            appBuild: 50,
            now: { clock.now }
        )
    }

    // MARK: C7.0 AC1 + N1 = B: the flag matrix

    func testChannelComesFromBuildTypeAndReceipt() {
        XCTAssertEqual(RunSmartFeatures.coachV2Channel(isDebugBuild: true, receiptName: "sandboxReceipt"), .debug)
        XCTAssertEqual(RunSmartFeatures.coachV2Channel(isDebugBuild: false, receiptName: "sandboxReceipt"), .testflight)
        XCTAssertEqual(RunSmartFeatures.coachV2Channel(isDebugBuild: false, receiptName: "receipt"), .appStore)
        XCTAssertEqual(RunSmartFeatures.coachV2Channel(isDebugBuild: false, receiptName: nil), .appStore)
    }

    func testFlagMatrixWithTheKillSwitchOn() {
        func enabled(_ channel: CoachV2Channel, _ args: [String] = [], pilot: Bool = false) -> Bool {
            RunSmartFeatures.coachV2Enabled(channel: channel, processArguments: args, pilotAccess: pilot, v2FlagOn: true)
        }
        XCTAssertTrue(enabled(.debug, ["-enable-coach-v2"]), "Debug with the argument")
        XCTAssertFalse(enabled(.debug), "Debug without the argument")
        XCTAssertFalse(enabled(.debug, ["-enable-coach-mode"]), "the 1.x coach-mode argument does not turn on v2")
        XCTAssertFalse(enabled(.debug, pilot: true), "Debug without the argument, even with pilot access")
        XCTAssertTrue(enabled(.testflight), "TestFlight (sandbox receipt)")
        XCTAssertTrue(enabled(.testflight, pilot: false), "TestFlight needs no allowlist")
        XCTAssertFalse(enabled(.appStore, pilot: false), "App Store + unlisted coach")
        XCTAssertTrue(enabled(.appStore, pilot: true), "App Store + listed coach (or linked to one)")
    }

    func testKillSwitchOffTurnsV2OffInEveryBuild() {
        let cases: [(CoachV2Channel, [String], Bool)] = [
            (.debug, ["-enable-coach-v2"], false),
            (.debug, [], true),
            (.testflight, [], false),
            (.appStore, [], false),
            (.appStore, [], true),
        ]
        for (channel, args, pilot) in cases {
            XCTAssertFalse(
                RunSmartFeatures.coachV2Enabled(channel: channel, processArguments: args, pilotAccess: pilot, v2FlagOn: false),
                "kill switch off must win for \(channel) args=\(args) pilot=\(pilot)"
            )
        }
    }

    // MARK: C7.0 AC2: coachModeEnabled is unchanged

    func testCoachModeFlagBehavesExactlyAsOnMain() {
        XCTAssertTrue(RunSmartFeatures.coachModeEnabled(processArguments: [], isDebugBuild: false))
        XCTAssertFalse(RunSmartFeatures.coachModeEnabled(processArguments: [], isDebugBuild: true))
        XCTAssertTrue(RunSmartFeatures.coachModeEnabled(processArguments: ["-enable-coach-mode"], isDebugBuild: true))
        XCTAssertFalse(RunSmartFeatures.coachModeEnabled(processArguments: ["-enable-coach-v2"], isDebugBuild: true),
                       "the v2 argument must not turn on 1.x coach mode")
    }

    // MARK: Gate store: reads, cache, report (C7.0 AC3, C7.12 AC2)

    func testTestFlightSyncReadsFlagsAndReportsOnce() async {
        let repository = StubGateRepository()
        let gate = makeGate(repository, channel: .testflight)
        XCTAssertEqual(gate.state, .off, "off until the flags were read")

        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)
        XCTAssertEqual(repository.flagReads, 1)
        XCTAssertEqual(repository.pilotReads, 0, "pilot access only matters in App Store builds")
        XCTAssertEqual(repository.reports, [CoachV2CapabilityReport(coachV2: true, version: "1.2.7", build: 50, channel: .testflight)])

        // Launch fires the sign-in task and the scene-phase change: still one read, one report.
        await gate.sync(userID: userA)
        XCTAssertEqual(repository.flagReads, 1)
        XCTAssertEqual(repository.reports.count, 1)
    }

    func testAppStoreUnlistedCoachStaysOffAndReportsFalse() async {
        let repository = StubGateRepository()
        repository.pilot = .success(false)
        let gate = makeGate(repository, channel: .appStore)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .off)
        XCTAssertFalse(gate.isEnabled)
        XCTAssertEqual(repository.pilotReads, 1)
        XCTAssertEqual(repository.reports.last?.coachV2, false)
        XCTAssertEqual(repository.reports.last?.channel, .appStore)
    }

    func testAppStoreListedCoachTurnsOnAndReportsTrue() async {
        let repository = StubGateRepository()
        repository.pilot = .success(true)
        let gate = makeGate(repository, channel: .appStore)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)
        XCTAssertEqual(repository.reports.last?.coachV2, true)
    }

    func testDebugWithoutArgumentStaysOff() async {
        let repository = StubGateRepository()
        let gate = makeGate(repository, channel: .debug)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .off)
        XCTAssertEqual(repository.reports.last?.coachV2, false)
        XCTAssertEqual(repository.reports.last?.channel, .debug)

        let enabledRepository = StubGateRepository()
        let enabledGate = makeGate(enabledRepository, channel: .debug, arguments: ["-enable-coach-v2"])
        await enabledGate.sync(userID: userA)
        XCTAssertEqual(enabledGate.state, .on)
    }

    func testKillSwitchPausesWithinTheForegroundAfterTheCacheExpiresAndReturns() async {
        let repository = StubGateRepository()
        let clock = Clock()
        let gate = makeGate(repository, channel: .testflight, clock: clock)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)

        // Nadav flips the switch. Inside the 15-minute window the cached answer stands.
        repository.flags = .success(["coach_v2": false])
        clock.advance(minutes: 10)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)
        XCTAssertEqual(repository.flagReads, 1)

        // Next foreground after the window: flag-off UI in that same foreground.
        clock.advance(minutes: 6)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .paused)
        XCTAssertFalse(gate.isEnabled)

        // Back on: v2 returns on the next foreground after the window.
        repository.flags = .success(["coach_v2": true])
        clock.advance(minutes: 16)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)
        XCTAssertEqual(repository.reports.map(\.coachV2), [true],
                       "the capability never changed, so the switch caused no report")
    }

    func testKillSwitchOffStillReportsCapabilityTrue() async {
        // Overseer review round 1: the server applies the switch, so the report stays true.
        // Otherwise an athlete who doesn't reopen the app looks outdated after the switch returns.
        let repository = StubGateRepository()
        repository.flags = .success(["coach_v2": false])
        let gate = makeGate(repository, channel: .testflight)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .paused)
        XCTAssertEqual(repository.reports, [CoachV2CapabilityReport(coachV2: true, version: "1.2.7", build: 50, channel: .testflight)])
    }

    func testNoReportUntilFlagsWereReadForThisUser() async {
        // Overseer review round 1: a failed flag read must not overwrite a correct true with false.
        let repository = StubGateRepository()
        repository.flags = .failure(URLError(.notConnectedToInternet))
        let gate = makeGate(repository, channel: .testflight)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .off)
        XCTAssertTrue(repository.reports.isEmpty, "no flags read for this user: nothing reported")

        repository.flags = .success(["coach_v2": true])
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)
        XCTAssertEqual(repository.reports, [CoachV2CapabilityReport(coachV2: true, version: "1.2.7", build: 50, channel: .testflight)])
    }

    func testFailedPilotReadDoesNotReportFalse() async {
        let repository = StubGateRepository()
        repository.pilot = .failure(URLError(.notConnectedToInternet))
        let gate = makeGate(repository, channel: .appStore)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .off)
        XCTAssertTrue(repository.reports.isEmpty, "a failed pilot read is not a reason to report false")
    }

    func testKillSwitchOnAnUnlistedAppStoreBuildIsOffNotPaused() async {
        let repository = StubGateRepository()
        repository.flags = .success(["coach_v2": false])
        repository.pilot = .success(false)
        let gate = makeGate(repository, channel: .appStore)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .off, "a solo App Store user sees nothing new, not a paused line")
    }

    func testMissingCoachV2KeyCountsAsOff() async {
        let repository = StubGateRepository()
        repository.flags = .success(["coach_v2_push": true])
        let gate = makeGate(repository, channel: .testflight)
        await gate.sync(userID: userA)
        XCTAssertNotEqual(gate.state, .on)
    }

    func testOfflineDoesNotCrashAndRetriesNextForeground() async {
        let repository = StubGateRepository()
        repository.flags = .failure(URLError(.notConnectedToInternet))
        let gate = makeGate(repository, channel: .testflight)

        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .off, "no flags read yet: stay on 1.2.6 behavior")

        // Flags come back but the report fails: it is retried on the next foreground.
        repository.flags = .success(["coach_v2": true])
        repository.reportResult = .failure(URLError(.networkConnectionLost))
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)
        XCTAssertEqual(repository.flagReads, 2, "the failed read is retried on the next foreground")
        XCTAssertEqual(repository.reports.count, 1)

        repository.reportResult = .success(())
        await gate.sync(userID: userA)
        XCTAssertEqual(repository.reports.count, 2, "the failed report is retried on the next foreground")
        XCTAssertEqual(repository.reports.last?.coachV2, true)
    }

    func testFailedRefreshKeepsTheLastAnswerForTheSameUser() async {
        let repository = StubGateRepository()
        let clock = Clock()
        let gate = makeGate(repository, channel: .testflight, clock: clock)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)

        repository.flags = .failure(Offline())
        clock.advance(minutes: 20)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on, "a flaky connection keeps the last answer; the server still enforces the switch")
    }

    func testPilotAccessNeverCarriesToAnotherAccount() async {
        let repository = StubGateRepository()
        repository.pilot = .success(true)
        let gate = makeGate(repository, channel: .appStore)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)

        // B signs in on the same phone while offline.
        repository.pilot = .failure(Offline())
        repository.flags = .failure(Offline())
        await gate.sync(userID: userB)
        XCTAssertEqual(gate.state, .off)
        XCTAssertNil(CoachV2FlagCache(defaults: defaults).load(), "A's pilot access was dropped")
        XCTAssertEqual(repository.reports.count, 1, "B has no flags read yet, so nothing is reported for B")
    }

    func testSignOutClearsTheCacheAndTurnsOff() async {
        let repository = StubGateRepository()
        let gate = makeGate(repository, channel: .testflight)
        await gate.sync(userID: userA)
        XCTAssertEqual(gate.state, .on)

        await gate.sync(userID: nil)
        XCTAssertEqual(gate.state, .off)
        XCTAssertNil(CoachV2FlagCache(defaults: defaults).load())
        XCTAssertEqual(repository.reports.count, 1, "signed out: nothing is reported")
    }

    func testCacheFreshness() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = CoachV2FlagSnapshot(userID: userA, v2FlagOn: true, pilotAccess: false, fetchedAt: fetched)
        XCTAssertTrue(CoachV2FlagCache.isFresh(snapshot, for: userA, now: fetched.addingTimeInterval(14 * 60)))
        XCTAssertFalse(CoachV2FlagCache.isFresh(snapshot, for: userA, now: fetched.addingTimeInterval(15 * 60)))
        XCTAssertFalse(CoachV2FlagCache.isFresh(snapshot, for: userB, now: fetched))
        XCTAssertFalse(CoachV2FlagCache.isFresh(snapshot, for: userA, now: fetched.addingTimeInterval(-60)),
                       "a clock moved backwards forces a fresh read")
    }

    func testCapabilityReportEncodesTheRPCParameters() throws {
        let report = CoachV2CapabilityReport(coachV2: true, version: "1.2.7", build: 50, channel: .appStore)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        XCTAssertEqual(json?["p_coach_v2"] as? Bool, true)
        XCTAssertEqual(json?["p_version"] as? String, "1.2.7")
        XCTAssertEqual(json?["p_build"] as? Int, 50)
        XCTAssertEqual(json?["p_channel"] as? String, "app_store")
        XCTAssertEqual(json?["p_platform"] as? String, "ios")
    }

    // MARK: C7.0 AC6: roster line, and the flag-off case

    private func rosterModel(_ repository: StubGateRepository, athletes: [UUID]) -> CoachAthleteListModel {
        var service = MockCoachReadService()
        service.athletes = athletes.enumerated().map { index, id in
            CoachAthleteSummary(athleteID: id, displayName: "Athlete \(index)", linkedAt: Date(timeIntervalSince1970: 0), hasActivePlan: false)
        }
        // C7.2: counts and seen writes go to a stub, never to Supabase.
        let seen = CoachSeenStub()
        let outbox = CoachV2Outbox(defaults: UserDefaults(suiteName: "CoachV2GateTests-\(UUID().uuidString)")!, repository: seen)
        return CoachAthleteListModel(
            service: service, rosterStatus: { try await repository.rosterStatus() }, seen: seen, outbox: outbox
        )
    }

    func testFlagOffRosterMakesNoV2Call() async {
        let repository = StubGateRepository()
        let model = rosterModel(repository, athletes: [userB])
        await model.refresh(owner: userA)
        await model.applyCoachV2(.off)
        await model.applyCoachV2(.paused)
        await model.refresh(owner: userA)
        XCTAssertEqual(repository.rosterReads, 0)
        XCTAssertTrue(model.athletesNeedingUpdate.isEmpty)
    }

    func testV2CoachSeesWhichAthletesNeedTheLatestApp() async {
        let current = UUID(uuidString: "CCCCCCCC-0000-4000-8000-00000000000C")!
        let old = UUID(uuidString: "DDDDDDDD-0000-4000-8000-00000000000D")!
        let unknown = UUID(uuidString: "EEEEEEEE-0000-4000-8000-00000000000E")!
        let repository = StubGateRepository()
        repository.roster = .success([current: true, old: false])
        let model = rosterModel(repository, athletes: [current, old, unknown])

        await model.refresh(owner: userA)
        await model.applyCoachV2(.on)
        XCTAssertEqual(model.athletesNeedingUpdate, [old], "only an explicit false shows the line")

        // A roster refresh while v2 is on reloads the status too.
        repository.roster = .success([current: true, old: true])
        await model.refresh(owner: userA)
        XCTAssertTrue(model.athletesNeedingUpdate.isEmpty)

        // Kill switch: the line goes away with the rest of v2.
        repository.roster = .success([old: false])
        await model.refresh(owner: userA)
        XCTAssertEqual(model.athletesNeedingUpdate, [old])
        await model.applyCoachV2(.paused)
        XCTAssertTrue(model.athletesNeedingUpdate.isEmpty)
    }

    func testRosterStatusFailureShowsNoLine() async {
        let old = UUID(uuidString: "DDDDDDDD-0000-4000-8000-00000000000D")!
        let repository = StubGateRepository()
        repository.roster = .failure(URLError(.notConnectedToInternet))
        let model = rosterModel(repository, athletes: [old])
        await model.refresh(owner: userA)
        await model.applyCoachV2(.on)
        XCTAssertTrue(model.athletesNeedingUpdate.isEmpty)
        XCTAssertFalse(model.failure, "a failed v2 status read never fails the 1.2.6 roster")
    }

    // MARK: Analytics shell (S3)

    func testAnalyticsValuesCarryNoFreeText() {
        let id = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
        XCTAssertEqual(CoachV2Analytics.Value.id(id).raw as? String, "aaaaaaaa-0000-4000-8000-00000000000a")
        XCTAssertEqual(CoachV2Analytics.Value.count(3).raw as? Int, 3)
        XCTAssertEqual(CoachV2Analytics.Value.flag(true).raw as? Bool, true)
    }
}
