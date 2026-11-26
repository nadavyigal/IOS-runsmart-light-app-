import XCTest
@preconcurrency import UserNotifications
@testable import IOS_RunSmart_app

/// C7.10 remote push foundation: the in-context permission flow (T6, P10), token registration,
/// sign-out, prefs and time zone, and the tap router for every §3.5 kind.
/// "Coach" is the human coach, not the AI coach.

private struct Offline: Error {}

@MainActor
final class NotificationTapCompletionTests: XCTestCase {
    func testRemoteTapCompletesOnMainThreadAndBuffersUntilHandlerIsInstalled() async {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        defer { center.delegate = previousDelegate }
        let service = PushService(center: center)
        let completion = expectation(description: "Notification center completion")

        await Task.detached {
            service.handleNotificationTap(userInfo: ["rs": ["kind": "coachRunFinished"]]) {
                XCTAssertTrue(Thread.isMainThread)
                completion.fulfill()
            }
        }.value
        await fulfillment(of: [completion], timeout: 2)

        var received: RemotePushPayload?
        service.configureRemoteTaps { received = $0 }
        XCTAssertEqual(received?.kind, .coachRunFinished)
    }

    func testLocalTapRoutesBeforeCompletingOnMainThread() async {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        defer { center.delegate = previousDelegate }
        let service = PushService(center: center)
        let routed = expectation(description: "Local destination")
        let completion = expectation(description: "Notification center completion")
        service.configureNavigation { destination in
            XCTAssertEqual(destination, .plan)
            routed.fulfill()
        }

        await Task.detached {
            service.handleNotificationTap(userInfo: ["destination": "plan"]) {
                XCTAssertTrue(Thread.isMainThread)
                completion.fulfill()
            }
        }.value
        await fulfillment(of: [routed, completion], timeout: 2, enforceOrder: true)
    }
}

private final class FakePushRepository: RemotePushRepository, @unchecked Sendable {
    var registerResult: Result<Void, Error> = .success(())
    var unregisterDelay: UInt64 = 0
    var unregisterError: Error?
    var prefsZone: String?
    private(set) var registered: [(token: String, environment: RemotePushEnvironment, bundleID: String?)] = []
    private(set) var unregistered: [String] = []
    private(set) var prefsReads: [String] = []
    private(set) var zonesSet: [String] = []

    var callCount: Int { registered.count + unregistered.count + prefsReads.count + zonesSet.count }

    func register(token: String, environment: RemotePushEnvironment, bundleID: String?) async throws {
        registered.append((token, environment, bundleID))
        try registerResult.get()
    }

    func unregister(token: String) async throws {
        unregistered.append(token)
        if unregisterDelay > 0 { try await Task.sleep(nanoseconds: unregisterDelay) }
        if let unregisterError { throw unregisterError }
    }

    func prefs(timeZone: String) async throws -> RemoteNotificationPrefs {
        prefsReads.append(timeZone)
        let json = #"{"time_zone":"\#(prefsZone ?? timeZone)","coach_run_finished":true}"#
        return try JSONDecoder().decode(RemoteNotificationPrefs.self, from: Data(json.utf8))
    }

    func setTimeZone(_ timeZone: String) async throws {
        zonesSet.append(timeZone)
    }
}

@MainActor
private final class FakePushSystem: RemotePushSystem {
    var status: UNAuthorizationStatus = .notDetermined
    var grant = true
    private(set) var statusReads = 0
    private(set) var prompts = 0
    private(set) var registrations = 0
    private(set) var deviceUnregistrations = 0

    func authorizationStatus() async -> UNAuthorizationStatus {
        statusReads += 1
        return status
    }

    func requestAuthorization() async throws -> Bool {
        prompts += 1
        status = grant ? .authorized : .denied
        return grant
    }

    func registerForRemoteNotifications() {
        registrations += 1
    }

    func unregisterForRemoteNotifications() {
        deviceUnregistrations += 1
    }
}

private nonisolated final class SpyAnalytics: AnalyticsTracking, @unchecked Sendable {
    var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}

    var names: [String] { events.map(\.name) }
}

@MainActor
final class RemotePushRegistrarTests: XCTestCase {
    private let user = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let otherUser = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let tokenBytes = Data((0..<32).map { UInt8($0) })
    private var tokenHex: String { tokenBytes.map { String(format: "%02x", $0) }.joined() }

    private var defaults: UserDefaults!
    private var repository: FakePushRepository!
    private var system: FakePushSystem!
    private var analytics: SpyAnalytics!
    private var zone = "Asia/Jerusalem"
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RemotePushTests.\(UUID().uuidString)")
        repository = FakePushRepository()
        system = FakePushSystem()
        analytics = SpyAnalytics()
        zone = "Asia/Jerusalem"
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeRegistrar(timeout: TimeInterval = 3) -> RemotePushRegistrar {
        RemotePushRegistrar(
            repository: repository,
            system: system,
            store: RemotePushStateStore(defaults: defaults),
            analytics: { [analytics] in analytics! },
            timeZone: { [unowned self] in self.zone },
            bundleID: "com.runsmart.lite",
            environment: .sandbox,
            now: { [unowned self] in self.clock },
            unregisterTimeout: timeout
        )
    }

    // MARK: Flag off

    func testFlagOffRendersNothingAndCallsNothing() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: false)
        await registrar.coachTodayOpened()
        await registrar.athleteConsentAcknowledged(coachName: "Dana")
        await registrar.turnOn(.coach)
        await registrar.foreground()
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()

        XCTAssertFalse(registrar.showsCoachPrimer)
        XCTAssertNil(registrar.athletePrimer)
        XCTAssertEqual(system.statusReads, 0)
        XCTAssertEqual(system.prompts, 0)
        XCTAssertEqual(system.registrations, 0)
        XCTAssertEqual(repository.callCount, 0, "no v2 RPC with the flag off")
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testFlagOffTapOpensTodayWithNoNoticeAndNoEvent() {
        let registrar = makeRegistrar()
        let route = registrar.route(
            for: RemotePushPayload(kind: .coachRunFinished, athleteID: otherUser),
            context: RemotePushRouteContext(v2Enabled: false, isCoach: true, activeAthletes: [:])
        )
        XCTAssertEqual(route, RemotePushRoute(destination: .today))
        XCTAssertNil(registrar.tapNotice)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    // MARK: AC4: no prompt on sign-in

    func testFreshSignInShowsNoPrompt() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.foreground()
        XCTAssertFalse(registrar.showsCoachPrimer)
        XCTAssertNil(registrar.athletePrimer)
        XCTAssertEqual(system.prompts, 0)
        XCTAssertEqual(system.registrations, 0)
        XCTAssertEqual(repository.callCount, 0)
    }

    // MARK: AC2: coach T6

    func testCoachTurnOnPromptsRegistersAndCreatesPrefs() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        XCTAssertTrue(registrar.showsCoachPrimer)
        XCTAssertEqual(system.prompts, 0, "T6 shows before any system prompt")
        XCTAssertEqual(analytics.names, ["push_permission_prompted"])
        XCTAssertEqual(analytics.events[0].properties["role"] as? String, "coach")

        await registrar.turnOn(.coach)
        XCTAssertFalse(registrar.showsCoachPrimer)
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 1)
        XCTAssertEqual(analytics.names.last, "push_permission_result")
        XCTAssertEqual(analytics.events.last?.properties["granted"] as? Bool, true)

        await registrar.didRegister(deviceToken: tokenBytes)
        XCTAssertEqual(repository.registered.count, 1)
        XCTAssertEqual(repository.registered.first?.token, tokenHex)
        XCTAssertEqual(repository.registered.first?.environment, .sandbox)
        XCTAssertEqual(repository.registered.first?.bundleID, "com.runsmart.lite")
        // AC9: the first prefs read carries the device time zone.
        XCTAssertEqual(repository.prefsReads, ["Asia/Jerusalem"])
        XCTAssertTrue(repository.zonesSet.isEmpty)
    }

    func testT6ShowsOnceAndPromptedFiresOnce() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        await registrar.coachTodayOpened()
        XCTAssertEqual(analytics.names, ["push_permission_prompted"])

        // A relaunch: the card comes back until it is answered, the event does not.
        let relaunched = makeRegistrar()
        relaunched.update(userID: user, v2Enabled: true)
        await relaunched.coachTodayOpened()
        XCTAssertTrue(relaunched.showsCoachPrimer)
        XCTAssertEqual(analytics.names, ["push_permission_prompted"])
    }

    func testNotNowShowsNoSystemPromptAndNeverShowsAgain() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        registrar.notNow(.coach)
        XCTAssertFalse(registrar.showsCoachPrimer)
        XCTAssertEqual(system.prompts, 0)

        await registrar.coachTodayOpened()
        XCTAssertFalse(registrar.showsCoachPrimer)
        let relaunched = makeRegistrar()
        relaunched.update(userID: user, v2Enabled: true)
        await relaunched.coachTodayOpened()
        XCTAssertFalse(relaunched.showsCoachPrimer)
        XCTAssertEqual(system.prompts, 0)
    }

    func testAnswerIsPerAccount() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        registrar.notNow(.coach)
        registrar.update(userID: otherUser, v2Enabled: true)
        await registrar.coachTodayOpened()
        XCTAssertTrue(registrar.showsCoachPrimer, "another account on this phone gets its own T6")
    }

    // MARK: AC4: never re-prompt after a denial

    func testDeniedNeverCallsTheSystemPrompt() async {
        system.status = .denied
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        await registrar.athleteConsentAcknowledged(coachName: "Dana")
        XCTAssertFalse(registrar.showsCoachPrimer)
        XCTAssertNil(registrar.athletePrimer)
        await registrar.turnOn(.coach)
        await registrar.turnOn(.athlete)
        XCTAssertEqual(system.prompts, 0)
        XCTAssertEqual(system.registrations, 0)
    }

    func testDenyingTheSystemPromptRegistersNothing() async {
        system.grant = false
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        await registrar.turnOn(.coach)
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 0)
        XCTAssertEqual(analytics.events.last?.properties["granted"] as? Bool, false)
        await registrar.turnOn(.coach)
        XCTAssertEqual(system.prompts, 1, "never asked twice")
    }

    func testAlreadyAllowedRegistersInContextWithoutACard() async {
        system.status = .authorized
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.coachTodayOpened()
        XCTAssertFalse(registrar.showsCoachPrimer)
        XCTAssertEqual(system.prompts, 0)
        XCTAssertEqual(system.registrations, 1)
    }

    // MARK: AC3: athlete P10

    func testAthletePrimerAfterConsent() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.athleteConsentAcknowledged(coachName: "Dana")
        XCTAssertEqual(registrar.athletePrimer?.coachName, "Dana")
        XCTAssertEqual(analytics.events.last?.properties["role"] as? String, "athlete")

        await registrar.turnOn(.athlete)
        XCTAssertNil(registrar.athletePrimer)
        XCTAssertEqual(system.prompts, 1)
        XCTAssertEqual(system.registrations, 1)
    }

    func testAthleteNotNowAndCopy() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.athleteConsentAcknowledged(coachName: "Dana")
        registrar.notNow(.athlete)
        XCTAssertNil(registrar.athletePrimer)
        await registrar.athleteConsentAcknowledged(coachName: "Dana")
        XCTAssertNil(registrar.athletePrimer)
        XCTAssertEqual(system.prompts, 0)

        XCTAssertEqual(RemotePushCopy.athletePrimerTitle(coach: "Dana"), "Get \u{2068}Dana\u{2069}'s notes and plan updates")
        XCTAssertEqual(
            RemotePushCopy.athletePrimerBody(coach: "Dana"),
            "We'll only notify you when \u{2068}Dana\u{2069} writes to you or changes your plan."
        )
        XCTAssertEqual(RemotePushCopy.coachPrimerTitle, "Know when your athletes run")
        XCTAssertEqual(
            RemotePushCopy.coachPrimerBody,
            "Get a ping when someone finishes a run or flags pain, and a summary at 20:00."
        )
    }

    // MARK: Tokens

    func testSameTokenIsSentOncePerDay() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.didRegister(deviceToken: tokenBytes)
        XCTAssertEqual(repository.registered.count, 1)
        clock = clock.addingTimeInterval(25 * 60 * 60)
        await registrar.didRegister(deviceToken: tokenBytes)
        XCTAssertEqual(repository.registered.count, 2)
        XCTAssertEqual(repository.prefsReads.count, 1, "prefs are read once")
    }

    func testFailedRegisterIsRetriedOnForeground() async {
        repository.registerResult = .failure(Offline())
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        XCTAssertEqual(registrar.pendingToken, tokenHex)
        XCTAssertTrue(repository.prefsReads.isEmpty)

        repository.registerResult = .success(())
        await registrar.foreground()
        XCTAssertNil(registrar.pendingToken)
        XCTAssertEqual(repository.registered.count, 2)
        XCTAssertEqual(repository.prefsReads.count, 1)
    }

    func testTokenArrivingBeforeV2IsSentOnceV2IsOn() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: false)
        await registrar.didRegister(deviceToken: tokenBytes)
        XCTAssertEqual(repository.callCount, 0)
        registrar.update(userID: user, v2Enabled: true)
        await registrar.foreground()
        XCTAssertEqual(repository.registered.count, 1)
    }

    // MARK: AC9: time zone on foreground

    func testTimeZoneUpdatesOnForegroundOnlyWhenItChanges() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.foreground()
        XCTAssertTrue(repository.zonesSet.isEmpty)

        zone = "Europe/London"
        await registrar.foreground()
        XCTAssertEqual(repository.zonesSet, ["Europe/London"])
        await registrar.foreground()
        XCTAssertEqual(repository.zonesSet, ["Europe/London"], "sent once")
    }

    func testFirstReadOnAnotherDevicesZoneMovesItHere() async {
        repository.prefsZone = "America/New_York"
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        XCTAssertEqual(repository.zonesSet, ["Asia/Jerusalem"])
    }

    // MARK: AC5: sign-out removes only this device's token

    func testSignOutUnregistersOnlyThisDevicesToken() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()
        XCTAssertEqual(repository.unregistered, [tokenHex])

        // Nothing left to remove.
        await registrar.signOut()
        XCTAssertEqual(repository.unregistered, [tokenHex])
    }

    func testSignOutWithoutARegistrationCallsNothing() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.signOut()
        XCTAssertEqual(repository.callCount, 0)
    }

    func testOfflineSignOutIsBounded() async {
        repository.unregisterDelay = 5_000_000_000
        let registrar = makeRegistrar(timeout: 0.2)
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        let started = Date()
        await registrar.signOut()
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        // The local record goes anyway; a second sign-out sends nothing.
        await registrar.signOut()
        XCTAssertEqual(repository.unregistered.count, 1)
    }

    // A sign-out whose server call fails must not leave the old account's coach pushes
    // (pain flags) reaching the next person on this phone.

    func testFailedUnregisterDropsTheDeviceToken() async {
        repository.unregisterError = Offline()
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()
        XCTAssertEqual(repository.unregistered, [tokenHex])
        XCTAssertEqual(system.deviceUnregistrations, 1)
    }

    func testTimedOutUnregisterDropsTheDeviceToken() async {
        repository.unregisterDelay = 5_000_000_000
        let registrar = makeRegistrar(timeout: 0.2)
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()
        XCTAssertEqual(system.deviceUnregistrations, 1)
    }

    func testSuccessfulUnregisterKeepsTheDeviceToken() async {
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()
        XCTAssertEqual(repository.unregistered, [tokenHex])
        XCTAssertEqual(system.deviceUnregistrations, 0)
    }

    func testPendingUnregisterIsRetriedOnTheSameAccountsNextSignInAndClearedOnSuccess() async {
        repository.unregisterError = Offline()
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()
        registrar.update(userID: nil, v2Enabled: false)
        XCTAssertEqual(repository.unregistered, [tokenHex])

        // Another account on this phone: its session may not remove the first account's row.
        repository.unregisterError = nil
        registrar.update(userID: otherUser, v2Enabled: true)
        await registrar.foreground()
        XCTAssertEqual(repository.unregistered, [tokenHex], "not retried for another account")
        await registrar.signOut()
        registrar.update(userID: nil, v2Enabled: false)

        // The same account signs in again: the removal is retried once and then forgotten.
        registrar.update(userID: user, v2Enabled: true)
        await registrar.foreground()
        XCTAssertEqual(repository.unregistered, [tokenHex, tokenHex])
        await registrar.foreground()
        XCTAssertEqual(repository.unregistered, [tokenHex, tokenHex], "cleared after success")
    }

    func testPendingUnregisterRetriesEvenWithV2Off() async {
        repository.unregisterError = Offline()
        let registrar = makeRegistrar()
        registrar.update(userID: user, v2Enabled: true)
        await registrar.didRegister(deviceToken: tokenBytes)
        await registrar.signOut()
        registrar.update(userID: nil, v2Enabled: false)

        repository.unregisterError = nil
        registrar.update(userID: user, v2Enabled: false)
        await registrar.foreground()
        XCTAssertEqual(repository.unregistered, [tokenHex, tokenHex], "cleanup of a live coach-push row")
    }

    // MARK: AC8: taps

    func testTapTracksPushOpenedAndShowsTheNotice() {
        let registrar = makeRegistrar()
        let route = registrar.route(
            for: RemotePushPayload(kind: .coachRunFinished, athleteID: otherUser),
            context: RemotePushRouteContext(v2Enabled: true, isCoach: true, activeAthletes: [:])
        )
        XCTAssertEqual(route.destination, .coachToday)
        XCTAssertEqual(registrar.tapNotice, RemotePushCopy.athleteGone(nil))
        XCTAssertEqual(analytics.names, ["push_opened"])
        XCTAssertEqual(analytics.events[0].properties["kind"] as? String, "coachRunFinished")
    }

    func testAnalyticsCarryOnlyEnums() {
        let events: [CoachV2Analytics.Event] = [
            .pushPermissionPrompted(role: .coach),
            .pushPermissionResult(role: .athlete, granted: true),
            .pushOpened(kind: .athleteCoachNote),
        ]
        XCTAssertEqual(events.map(\.name), ["push_permission_prompted", "push_permission_result", "push_opened"])
        XCTAssertEqual(events[1].properties.keys.sorted(), ["granted", "role"])
        XCTAssertEqual(events[2].properties.keys.sorted(), ["kind"])
    }
}

/// AC8: a router test for each §3.5 kind, the gone-target cases, and the payload parser.
final class RemotePushRouterTests: XCTestCase {
    private let dana = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let gone = UUID(uuidString: "CCCCCCCC-0000-4000-8000-00000000000C")!
    private let flag = UUID(uuidString: "DDDDDDDD-0000-4000-8000-00000000000D")!
    private let note = UUID(uuidString: "EEEEEEEE-0000-4000-8000-00000000000E")!
    private let workout = UUID(uuidString: "FFFFFFFF-0000-4000-8000-00000000000F")!

    private var coach: RemotePushRouteContext {
        RemotePushRouteContext(v2Enabled: true, isCoach: true, activeAthletes: [dana: "Dana"], openFlagIDs: [flag])
    }

    private var athlete: RemotePushRouteContext {
        RemotePushRouteContext(v2Enabled: true, hasActiveCoachLink: true, coachName: "Ron", feedbackIDs: [note], workoutIDs: [workout])
    }

    private func route(_ payload: RemotePushPayload, _ context: RemotePushRouteContext) -> RemotePushRoute {
        RemotePushRouter.route(payload, context: context)
    }

    // coachRunFinished -> coach athlete day detail

    func testCoachRunFinishedOpensTheDayDetail() {
        let result = route(RemotePushPayload(kind: .coachRunFinished, athleteID: dana, day: "2026-11-23", runID: "42"), coach)
        XCTAssertEqual(result, RemotePushRoute(destination: .coachAthlete(id: dana, name: "Dana", dayISO: "2026-11-23")))
    }

    func testCoachRunFinishedForAGoneAthleteOpensCoachTodayWithANotice() {
        let result = route(RemotePushPayload(kind: .coachRunFinished, athleteID: gone, day: "2026-11-23"), coach)
        XCTAssertEqual(result, RemotePushRoute(destination: .coachToday, notice: "This athlete is no longer linked to you."))
    }

    func testCoachRunFinishedBeforeTheRosterLoadedClaimsNothing() {
        var context = coach
        context.activeAthletes = nil
        XCTAssertEqual(route(RemotePushPayload(kind: .coachRunFinished, athleteID: dana), context), RemotePushRoute(destination: .coachToday))
    }

    func testCoachPushOnANonCoachAccountOpensToday() {
        var context = coach
        context.isCoach = false
        for kind in [RemotePushKind.coachRunFinished, .coachPainFlag, .athleteCoachReply, .coachEveningSummary, .coachDigest] {
            XCTAssertEqual(route(RemotePushPayload(kind: kind, athleteID: dana), context), RemotePushRoute(destination: .today), "\(kind)")
        }
    }

    // coachEveningSummary -> coach Today, filtered to "Missed today" (C7.6 AC5, T2)

    func testCoachEveningSummaryOpensCoachTodayFilteredToMissed() {
        XCTAssertEqual(
            route(RemotePushPayload(kind: .coachEveningSummary, day: "2026-11-23"), coach),
            RemotePushRoute(destination: .coachTodayMissed(dayISO: "2026-11-23"))
        )
        // No day in the payload: today's list. No athlete id, so never a "no longer linked" notice.
        var unloaded = coach
        unloaded.activeAthletes = nil
        XCTAssertEqual(
            route(RemotePushPayload(kind: .coachEveningSummary), unloaded),
            RemotePushRoute(destination: .coachTodayMissed(dayISO: nil))
        )
    }

    // coachPainFlag -> athlete detail

    func testCoachPainFlagOpensTheAthlete() {
        let result = route(RemotePushPayload(kind: .coachPainFlag, athleteID: dana, day: "2026-11-22", flagID: flag), coach)
        XCTAssertEqual(result, RemotePushRoute(destination: .coachAthlete(id: dana, name: "Dana", dayISO: "2026-11-22")))
    }

    func testCoachPainFlagAlreadyResolvedOpensTheAthleteWithANotice() {
        var context = coach
        context.openFlagIDs = []
        let result = route(RemotePushPayload(kind: .coachPainFlag, athleteID: dana, flagID: flag), context)
        XCTAssertEqual(result, RemotePushRoute(destination: .coachAthlete(id: dana, name: "Dana", dayISO: nil), notice: RemotePushCopy.flagHandled))
    }

    func testCoachPainFlagWithFlagsNotLoadedClaimsNothing() {
        var context = coach
        context.openFlagIDs = nil
        let result = route(RemotePushPayload(kind: .coachPainFlag, athleteID: dana, flagID: flag), context)
        XCTAssertNil(result.notice)
    }

    func testCoachPainFlagForAGoneAthlete() {
        let result = route(RemotePushPayload(kind: .coachPainFlag, athleteID: gone, flagID: flag), coach)
        XCTAssertEqual(result, RemotePushRoute(destination: .coachToday, notice: RemotePushCopy.athleteGone(nil)))
    }

    // athleteCoachReply (coach receives) -> feedback thread on the athlete detail

    func testAthleteCoachReplyOpensTheThread() {
        let result = route(RemotePushPayload(kind: .athleteCoachReply, athleteID: dana, feedbackID: note), coach)
        XCTAssertEqual(result, RemotePushRoute(destination: .coachAthlete(id: dana, name: "Dana", dayISO: nil)))
    }

    func testAthleteCoachReplyFromAGoneAthlete() {
        let result = route(RemotePushPayload(kind: .athleteCoachReply, athleteID: gone, feedbackID: note), coach)
        XCTAssertEqual(result.destination, .coachToday)
        XCTAssertEqual(result.notice, RemotePushCopy.athleteGone(nil))
    }

    // C7.5 coachDigest ("While you were away: ...", "{n} more athletes finished runs") -> coach Today

    func testCoachDigestOpensCoachToday() {
        XCTAssertEqual(route(RemotePushPayload(kind: .coachDigest), coach), RemotePushRoute(destination: .coachToday))
        // No athlete id, so no roster check and no "no longer linked" notice, even with the roster unloaded.
        var unloaded = coach
        unloaded.activeAthletes = nil
        XCTAssertEqual(route(RemotePushPayload(kind: .coachDigest), unloaded), RemotePushRoute(destination: .coachToday))
    }

    // C7.5 athleteNotesDigest ("{Coach} left you {n} notes") -> My coach

    func testAthleteNotesDigestOpensMyCoach() {
        let result = route(RemotePushPayload(kind: .athleteNotesDigest, coachID: UUID()), athlete)
        XCTAssertEqual(result, RemotePushRoute(destination: .myCoach))
    }

    func testAthleteNotesDigestAfterTheLinkEnded() {
        var context = athlete
        context.hasActiveCoachLink = false
        let result = route(RemotePushPayload(kind: .athleteNotesDigest), context)
        XCTAssertEqual(result, RemotePushRoute(destination: .today, notice: "You're no longer linked to \u{2068}Ron\u{2069}."))
    }

    func testAthleteNotesDigestBeforeTheLinkLoadedClaimsNothing() {
        var context = athlete
        context.hasActiveCoachLink = nil
        XCTAssertEqual(route(RemotePushPayload(kind: .athleteNotesDigest), context), RemotePushRoute(destination: .today))
    }

    func testCollapsedKindsParseFromTheServerPayload() {
        let coachID = UUID()
        XCTAssertEqual(RemotePushPayload(userInfo: ["rs": ["v": 1, "kind": "coachDigest"]]), RemotePushPayload(kind: .coachDigest))
        XCTAssertEqual(
            RemotePushPayload(userInfo: ["rs": ["v": 1, "kind": "athleteNotesDigest", "coach_id": coachID.uuidString.lowercased()]]),
            RemotePushPayload(kind: .athleteNotesDigest, coachID: coachID)
        )
    }

    func testFlagOffCollapsedKindsOpenToday() {
        let off = RemotePushRouteContext(v2Enabled: false, isCoach: true, hasActiveCoachLink: true)
        for kind in [RemotePushKind.coachDigest, .athleteNotesDigest] {
            XCTAssertEqual(route(RemotePushPayload(kind: kind), off), RemotePushRoute(destination: .today), "\(kind)")
        }
    }

    // athleteCoachNote -> the note on My coach

    func testAthleteCoachNoteOpensMyCoach() {
        XCTAssertEqual(route(RemotePushPayload(kind: .athleteCoachNote, feedbackID: note), athlete), RemotePushRoute(destination: .myCoach))
    }

    func testAthleteCoachNoteThatIsGone() {
        let result = route(RemotePushPayload(kind: .athleteCoachNote, feedbackID: UUID()), athlete)
        XCTAssertEqual(result, RemotePushRoute(destination: .myCoach, notice: RemotePushCopy.noteGone))
    }

    func testAthleteCoachNoteAfterTheLinkEnded() {
        var context = athlete
        context.hasActiveCoachLink = false
        let result = route(RemotePushPayload(kind: .athleteCoachNote, feedbackID: note), context)
        XCTAssertEqual(result, RemotePushRoute(destination: .today, notice: "You're no longer linked to \u{2068}Ron\u{2069}."))
    }

    func testAthleteCoachNoteBeforeTheLinkLoadedClaimsNothing() {
        var context = athlete
        context.hasActiveCoachLink = nil
        XCTAssertEqual(route(RemotePushPayload(kind: .athleteCoachNote, feedbackID: note), context), RemotePushRoute(destination: .today))
    }

    // athletePlanPublished -> Plan tab

    func testAthletePlanPublishedOpensPlan() {
        XCTAssertEqual(route(RemotePushPayload(kind: .athletePlanPublished), athlete), RemotePushRoute(destination: .plan))
        var ended = athlete
        ended.hasActiveCoachLink = false
        XCTAssertEqual(route(RemotePushPayload(kind: .athletePlanPublished), ended).destination, .plan)
    }

    // athletePlanUpdated -> the change-list card (Today)

    func testAthletePlanUpdatedOpensTheChangeList() {
        XCTAssertEqual(route(RemotePushPayload(kind: .athletePlanUpdated, workoutID: workout), athlete), RemotePushRoute(destination: .today))
    }

    func testAthletePlanUpdatedForADeletedWorkout() {
        let result = route(RemotePushPayload(kind: .athletePlanUpdated, workoutID: UUID()), athlete)
        XCTAssertEqual(result, RemotePushRoute(destination: .plan, notice: "This workout was changed."))
    }

    func testAthletePlanUpdatedAfterTheLinkEnded() {
        var context = athlete
        context.hasActiveCoachLink = false
        let result = route(RemotePushPayload(kind: .athletePlanUpdated), context)
        XCTAssertEqual(result.destination, .plan)
        XCTAssertEqual(result.notice, RemotePushCopy.coachLinkEnded("Ron"))
    }

    // athleteBroadcast -> Today

    func testAthleteBroadcastOpensToday() {
        XCTAssertEqual(route(RemotePushPayload(kind: .athleteBroadcast), athlete), RemotePushRoute(destination: .today))
    }

    func testAthleteBroadcastAfterTheLinkEnded() {
        var context = athlete
        context.hasActiveCoachLink = false
        context.coachName = nil
        let result = route(RemotePushPayload(kind: .athleteBroadcast), context)
        XCTAssertEqual(result, RemotePushRoute(destination: .today, notice: "You're no longer linked to this coach."))
    }

    func testSelfTestOpensToday() {
        XCTAssertEqual(route(RemotePushPayload(kind: .selfTest), athlete), RemotePushRoute(destination: .today))
    }

    func testEveryKindIsRoutedWithTheFlagOffToToday() {
        let off = RemotePushRouteContext(v2Enabled: false, isCoach: true, activeAthletes: [dana: "Dana"], hasActiveCoachLink: true)
        for kind in RemotePushKind.allCases {
            XCTAssertEqual(route(RemotePushPayload(kind: kind, athleteID: dana), off), RemotePushRoute(destination: .today), "\(kind)")
        }
    }

    func testGoneAthleteNoticeIsolatesTheName() {
        XCTAssertEqual(RemotePushCopy.athleteGone("Dana"), "\u{2068}Dana\u{2069} is no longer linked to you.")
    }

    // Payload

    func testPayloadParsesTheServerShape() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["body": "Dana finished a 5 km run"]],
            "rs": [
                "v": 1, "kind": "coachPainFlag", "athlete_id": dana.uuidString.lowercased(), "day": "2026-11-23",
                "run_id": "42", "flag_id": flag.uuidString.lowercased(), "feedback_id": "not-a-uuid", "workout_id": workout.uuidString,
            ],
        ]
        let payload = RemotePushPayload(userInfo: userInfo)
        XCTAssertEqual(payload, RemotePushPayload(kind: .coachPainFlag, athleteID: dana, day: "2026-11-23", runID: "42", flagID: flag, workoutID: workout))
    }

    func testPayloadRejectsLocalRemindersAndUnknownKinds() {
        XCTAssertNil(RemotePushPayload(userInfo: ["type": "workoutDue", "destination": "today"]))
        XCTAssertNil(RemotePushPayload(userInfo: ["rs": ["kind": "somethingNew"]]))
        XCTAssertNil(RemotePushPayload(userInfo: ["rs": "coachRunFinished"]))
        let badDay = RemotePushPayload(userInfo: ["rs": ["kind": "coachRunFinished", "day": "tomorrow", "run_id": "4x"]])
        XCTAssertNil(badDay?.day)
        XCTAssertNil(badDay?.runID)
    }

    func testKindsMatchTheServerList() {
        // supabase/functions/_shared/apns.ts REMOTE_PUSH_KINDS
        XCTAssertEqual(RemotePushKind.allCases.map(\.rawValue), [
            "coachRunFinished", "coachEveningSummary", "coachPainFlag", "athleteCoachNote", "athleteCoachReply",
            "athletePlanPublished", "athletePlanUpdated", "athleteBroadcast", "coachDigest", "athleteNotesDigest",
            "selfTest",
        ])
    }
}
