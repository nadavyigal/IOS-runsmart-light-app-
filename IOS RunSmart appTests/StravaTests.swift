import XCTest
@testable import IOS_RunSmart_app

/// Record-a-run S12: Strava upload. Nothing here touches the network.
@MainActor
final class StravaTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(_ seconds: TimeInterval, lat: Double, altitude: Double? = nil, newSegment: Bool? = nil) -> RunRoutePoint {
        RunRoutePoint(
            latitude: lat,
            longitude: 34.78,
            timestamp: start.addingTimeInterval(seconds),
            horizontalAccuracy: 5,
            altitude: altitude,
            startsNewSegment: newSegment
        )
    }

    private func makeRun(
        id: UUID = UUID(),
        route: [RunRoutePoint] = [],
        source: RunSmartDataSource = .runSmart,
        distance: Double = 5_000,
        seconds: TimeInterval = 1_800,
        title: String? = nil,
        notes: String? = nil,
        stravaID: Int? = nil
    ) -> RecordedRun {
        RecordedRun(
            id: id,
            providerActivityID: nil,
            source: source,
            startedAt: start,
            endedAt: start.addingTimeInterval(seconds),
            distanceMeters: distance,
            movingTimeSeconds: seconds,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: route,
            syncedAt: nil,
            title: title,
            notes: notes,
            stravaActivityID: stravaID
        )
    }

    private func twoSegmentRoute() -> [RunRoutePoint] {
        [
            point(0, lat: 32.0000, altitude: 12.34),
            point(10, lat: 32.0001, altitude: 13.0),
            point(20, lat: 32.0002),
            point(100, lat: 32.0100, altitude: 20, newSegment: true),
            point(110, lat: 32.0101, altitude: 21)
        ]
    }

    // MARK: GPX

    func testGPXHasOneSegmentPerStretchWithTimesAndElevation() {
        let run = makeRun(route: twoSegmentRoute(), title: "Tempo")
        let draft = StravaActivityDraft(run: run)
        XCTAssertEqual(draft.segments.map(\.count), [3, 2])
        let gpx = GPXBuilder.gpx(for: draft)
        XCTAssertEqual(gpx.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt ").count - 1, 5)
        XCTAssertTrue(gpx.contains(#"<trkpt lat="32.0000000" lon="34.7800000"><ele>12.3</ele><time>2027-01-15T08:00:00Z</time></trkpt>"#), gpx)
        XCTAssertTrue(gpx.contains("<type>running</type>"))
        XCTAssertTrue(gpx.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        XCTAssertTrue(gpx.contains(#"<gpx version="1.1" creator="RunSmart" xmlns="http://www.topografix.com/GPX/1/1">"#))
    }

    func testGPXLeavesOutElevationWhenNotRecorded() {
        let draft = StravaActivityDraft(run: makeRun(route: twoSegmentRoute()))
        let lines = GPXBuilder.gpx(for: draft).components(separatedBy: "\n").filter { $0.contains("<trkpt") }
        XCTAssertEqual(lines.count, 5)
        XCTAssertFalse(lines[2].contains("<ele>"), "third point has no altitude")
        XCTAssertTrue(lines[1].contains("<ele>13.0</ele>"))
    }

    func testGPXEscapesNamesAndDropsControlCharacters() {
        let gpx = GPXBuilder.gpx(name: #"Dad & Me <5k> "fun" it's"# + "\u{0001}ok", startedAt: start, segments: [])
        XCTAssertTrue(gpx.contains("<name>Dad &amp; Me &lt;5k&gt; &quot;fun&quot; it&apos;sok</name>"), gpx)
        XCTAssertFalse(gpx.contains("\u{0001}"))
    }

    func testGPXTimesAreUTC() {
        let gpx = GPXBuilder.gpx(name: "x", startedAt: start, segments: [[StravaTrackPoint(latitude: 1, longitude: 2, time: start, elevation: nil)]])
        XCTAssertTrue(gpx.contains("<time>2027-01-15T08:00:00Z</time>"))
    }

    // MARK: Upload decision

    func testRunWithARouteUploadsAsGPX() {
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(route: twoSegmentRoute())), .uploadGPX)
    }

    func testRunWithFewerThanTwoPointsIsAManualActivity() {
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(route: [])), .createManual)
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(route: [point(0, lat: 32)])), .createManual)
    }

    func testRunAlreadyOnStravaIsNeverUploadedAgain() {
        let run = makeRun(route: twoSegmentRoute(), stravaID: 998_877)
        XCTAssertEqual(StravaUploadDecision.decide(for: run), .alreadyOnStrava(998_877))
    }

    func testImportedAndShortRunsAreNotSent() {
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(route: twoSegmentRoute(), source: .garmin)), .notEligible)
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(route: twoSegmentRoute(), source: .healthKit)), .notEligible)
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(distance: 50)), .notEligible)
        XCTAssertEqual(StravaUploadDecision.decide(for: makeRun(seconds: 30)), .notEligible)
    }

    func testOldStoredRunsWithoutTheFieldStillDecode() throws {
        let run = makeRun(route: twoSegmentRoute())
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
        json.removeValue(forKey: "stravaActivityID")
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(RecordedRun.self, from: data).stravaActivityID)
    }

    // MARK: Requests

    func testExternalIDIsRunSmartPlusRunID() {
        let id = UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000001")!
        XCTAssertEqual(StravaRequests.externalID(forRunID: id), "runsmart-a1b2c3d4-0000-4000-8000-000000000001.gpx")
    }

    func testUploadRequestHasTheRequiredMultipartFields() throws {
        let id = UUID()
        let draft = StravaActivityDraft(run: makeRun(id: id, route: twoSegmentRoute(), title: "Tempo Tuesday", notes: "Felt strong"))
        let request = StravaRequests.upload(draft: draft, gpx: Data("<gpx/>".utf8), accessToken: "tok", boundary: "BOUND")
        XCTAssertEqual(request.url?.absoluteString, "https://www.strava.com/api/v3/uploads")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=BOUND")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        func field(_ name: String) -> String? {
            guard let range = body.range(of: "name=\"\(name)\"\r\n\r\n") else { return nil }
            return body[range.upperBound...].components(separatedBy: "\r\n").first
        }
        XCTAssertEqual(field("data_type"), "gpx")
        XCTAssertEqual(field("activity_type"), "run")
        XCTAssertEqual(field("name"), "Tempo Tuesday")
        XCTAssertEqual(field("description"), "Felt strong")
        XCTAssertEqual(field("external_id"), "runsmart-\(id.uuidString.lowercased()).gpx")
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"runsmart-\(id.uuidString.lowercased()).gpx\""))
        XCTAssertTrue(body.contains("<gpx/>"))
        XCTAssertTrue(body.hasSuffix("--BOUND--\r\n"))
    }

    func testUploadRequestOmitsEmptyDescription() throws {
        let draft = StravaActivityDraft(run: makeRun(route: twoSegmentRoute(), notes: nil))
        let request = StravaRequests.upload(draft: draft, gpx: Data(), accessToken: "t", boundary: "B")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(body.contains("name=\"description\""))
    }

    func testManualActivityRequestFields() throws {
        let draft = StravaActivityDraft(run: makeRun(route: [], distance: 4_321.4, seconds: 1_500, title: "Treadmill & Co"))
        let request = StravaRequests.manualActivity(draft: draft, accessToken: "tok", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(request.url?.absoluteString, "https://www.strava.com/api/v3/activities")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=Treadmill%20%26%20Co"), body)
        XCTAssertTrue(body.contains("sport_type=Run"))
        XCTAssertTrue(body.contains("elapsed_time=1500"))
        XCTAssertTrue(body.contains("distance=4321"))
        XCTAssertTrue(body.contains("start_date_local=2027-01-15T08%3A00%3A00Z"), body)
    }

    func testStartDateLocalUsesTheWallClockOfTheTimeZone() {
        let text = StravaRequests.localStartString(start, timeZone: TimeZone(identifier: "Asia/Jerusalem")!)
        XCTAssertEqual(text, "2027-01-15T10:00:00Z")
    }

    func testTokenRequestGoesToTheEdgeFunctionWithBothHeaders() throws {
        let base = URL(string: "https://example.supabase.co/functions/v1")!
        let exchange = try StravaRequests.tokenRequest(.exchange(code: "abc"), functionsBaseURL: base, publishableKey: "pub", supabaseAccessToken: "jwt")
        XCTAssertEqual(exchange.url?.absoluteString, "https://example.supabase.co/functions/v1/strava_oauth")
        XCTAssertEqual(exchange.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        XCTAssertEqual(exchange.value(forHTTPHeaderField: "apikey"), "pub")
        XCTAssertEqual(String(decoding: try XCTUnwrap(exchange.httpBody), as: UTF8.self), #"{"action":"exchange","code":"abc"}"#)
        let refresh = try StravaRequests.tokenRequest(.refresh(refreshToken: "r1"), functionsBaseURL: base, publishableKey: "pub", supabaseAccessToken: "jwt")
        XCTAssertEqual(String(decoding: try XCTUnwrap(refresh.httpBody), as: UTF8.self), #"{"action":"refresh","refresh_token":"r1"}"#)
    }

    func testAuthorizeURLAsksForUploadScopeWithoutForcingApproval() throws {
        let url = StravaConfig.authorizeURL(clientID: "12345", state: "s1")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "www.strava.com")
        XCTAssertEqual(url.path, "/oauth/mobile/authorize")
        XCTAssertEqual(items["client_id"], "12345")
        XCTAssertEqual(items["redirect_uri"], "runsmart://strava-callback")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["approval_prompt"], "auto")
        XCTAssertEqual(items["scope"], "activity:write,read")
        XCTAssertEqual(items["state"], "s1")
    }

    func testDuplicateUploadErrorYieldsTheExistingActivityID() {
        XCTAssertEqual(StravaClient.duplicateActivityID(in: "runsmart-x.gpx duplicate of activity 4455667788"), 4_455_667_788)
        XCTAssertEqual(StravaClient.duplicateActivityID(in: "x duplicate of <a href='http://strava.com/activities/1234'>activity 1234</a>"), 1_234)
        XCTAssertNil(StravaClient.duplicateActivityID(in: "The file is empty"))
    }

    // MARK: Config gate and guest gate

    func testEmptyOrUnsubstitutedClientIDMeansNotConfigured() {
        XCTAssertNil(StravaConfig.clientID(from: [:]))
        XCTAssertNil(StravaConfig.clientID(from: ["RUNSMART_STRAVA_CLIENT_ID": ""]))
        XCTAssertNil(StravaConfig.clientID(from: ["RUNSMART_STRAVA_CLIENT_ID": "   "]))
        XCTAssertNil(StravaConfig.clientID(from: ["RUNSMART_STRAVA_CLIENT_ID": "$(RUNSMART_STRAVA_CLIENT_ID)"]))
        XCTAssertEqual(StravaConfig.clientID(from: ["RUNSMART_STRAVA_CLIENT_ID": " 98765 "]), "98765")
    }

    func testStravaUIIsHiddenWhenNoClientID() {
        XCTAssertEqual(StravaAvailability.resolve(clientID: nil, isSignedIn: true), .hidden)
        XCTAssertEqual(StravaAvailability.resolve(clientID: "", isSignedIn: true), .hidden)
        XCTAssertEqual(StravaAvailability.resolve(clientID: nil, isSignedIn: false), .hidden)
    }

    func testGuestsAreAskedToSignInAndSignedInRunnersCanConnect() {
        XCTAssertEqual(StravaAvailability.resolve(clientID: "1", isSignedIn: false), .signInRequired)
        XCTAssertEqual(StravaAvailability.resolve(clientID: "1", isSignedIn: true), .available)
    }

    func testServiceHidesEverythingWithoutAClientID() {
        let service = StravaConnectionService(
            tokenStore: InMemoryStravaTokenStore(tokens: sampleTokens(expiresIn: 3_600)),
            clientID: { nil }
        )
        XCTAssertEqual(service.availability(isSignedIn: true), .hidden)
        XCTAssertFalse(service.isConnected, "tokens from an older build are ignored while Strava is off")
    }

    // MARK: Token refresh

    private func sampleTokens(expiresIn: TimeInterval, now: Date = Date()) -> StravaTokens {
        StravaTokens(accessToken: "access", refreshToken: "refresh", expiresAt: now.addingTimeInterval(expiresIn), athleteID: 7, athleteName: "Dana R")
    }

    func testTokenNeedsRefreshWhenFiveMinutesOrLessRemain() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(StravaTokenPolicy.needsRefresh(expiresAt: now.addingTimeInterval(-10), now: now))
        XCTAssertTrue(StravaTokenPolicy.needsRefresh(expiresAt: now.addingTimeInterval(299), now: now))
        XCTAssertFalse(StravaTokenPolicy.needsRefresh(expiresAt: now.addingTimeInterval(300), now: now))
        XCTAssertFalse(StravaTokenPolicy.needsRefresh(expiresAt: now.addingTimeInterval(3_600), now: now))
    }

    func testValidTokenIsReturnedWithoutCallingStrava() async throws {
        let transport = ScriptedTransport(responses: [])
        let service = makeService(tokens: sampleTokens(expiresIn: 3_600), transport: transport)
        let token = try await service.validAccessToken()
        XCTAssertEqual(token, "access")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testExpiringTokenIsRefreshedThroughTheEdgeFunctionAndStored() async throws {
        let transport = ScriptedTransport(responses: [
            (200, #"{"access_token":"new-access","refresh_token":"new-refresh","expires_at":2000000000,"athlete_id":null,"athlete_name":null}"#)
        ])
        let store = InMemoryStravaTokenStore(tokens: sampleTokens(expiresIn: 60))
        let service = makeService(store: store, transport: transport)
        let token = try await service.validAccessToken()
        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.lastPathComponent, "strava_oauth")
        XCTAssertEqual(store.load()?.refreshToken, "new-refresh")
        XCTAssertEqual(store.load()?.athleteName, "Dana R", "the athlete name survives a refresh")
    }

    func testRefreshRejectedByStravaDisconnects() async {
        let transport = ScriptedTransport(responses: [(400, #"{"error":"Strava rejected the request"}"#)])
        let store = InMemoryStravaTokenStore(tokens: sampleTokens(expiresIn: 60))
        let service = makeService(store: store, transport: transport)
        do {
            _ = try await service.validAccessToken()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? StravaError, .notConnected)
        }
        XCTAssertNil(store.load())
        XCTAssertFalse(service.isConnected)
    }

    func testNoTokensMeansNotConnected() async {
        let service = makeService(tokens: nil, transport: ScriptedTransport(responses: []))
        do {
            _ = try await service.validAccessToken()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? StravaError, .notConnected)
        }
    }

    // MARK: Callback

    func testCallbackNeedsMatchingStateAndUploadScope() throws {
        let good = URL(string: "runsmart://strava-callback?state=s1&code=CODE&scope=read,activity:write")!
        XCTAssertEqual(try StravaCallback.code(from: good, expectedState: "s1"), "CODE")
        XCTAssertThrowsError(try StravaCallback.code(from: good, expectedState: "other")) { XCTAssertEqual($0 as? StravaError, .stateMismatch) }
        let readOnly = URL(string: "runsmart://strava-callback?state=s1&code=CODE&scope=read")!
        XCTAssertThrowsError(try StravaCallback.code(from: readOnly, expectedState: "s1")) { XCTAssertEqual($0 as? StravaError, .missingScope) }
        let denied = URL(string: "runsmart://strava-callback?error=access_denied&state=s1")!
        XCTAssertThrowsError(try StravaCallback.code(from: denied, expectedState: "s1")) { XCTAssertEqual($0 as? StravaError, .cancelled) }
    }

    func testConnectStoresTokensAfterTheExchange() async {
        let transport = ScriptedTransport(responses: [
            (200, #"{"access_token":"a","refresh_token":"r","expires_at":2000000000,"athlete_id":42,"athlete_name":"Dana R"}"#)
        ])
        let store = InMemoryStravaTokenStore()
        let authorizer = ScriptedAuthorizer { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
            return URL(string: "runsmart://strava-callback?state=\(state)&code=CODE&scope=read,activity:write")!
        }
        let service = makeService(store: store, transport: transport, authorizer: authorizer)
        await service.connect()
        XCTAssertTrue(service.isConnected)
        XCTAssertEqual(service.connectedAthleteName, "Dana R")
        XCTAssertEqual(store.load()?.accessToken, "a")
        XCTAssertEqual(String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self), #"{"action":"exchange","code":"CODE"}"#)
    }

    func testConnectWithoutASupabaseSessionDoesNotOpenStrava() async {
        let authorizer = ScriptedAuthorizer { _ in URL(string: "runsmart://strava-callback")! }
        let service = StravaConnectionService(
            tokenStore: InMemoryStravaTokenStore(),
            clientID: { "123" },
            supabaseAccessToken: { nil },
            makeClient: { fatalError("no client needed") },
            authorizer: authorizer
        )
        await service.connect()
        XCTAssertFalse(service.isConnected)
        XCTAssertEqual(authorizer.calls, 0)
        XCTAssertEqual(service.lastMessage, "Sign in to RunSmart to connect Strava.")
    }

    // MARK: Client upload

    func testGPXUploadPollsUntilStravaReturnsAnActivity() async throws {
        let transport = ScriptedTransport(responses: [
            (201, #"{"id":555,"status":"Your activity is still being processed.","error":null,"activity_id":null}"#),
            (200, #"{"id":555,"status":"Your activity is still being processed.","error":null,"activity_id":null}"#),
            (200, #"{"id":555,"status":"Your activity is ready.","error":null,"activity_id":9001}"#)
        ])
        let sleeps = SleepRecorder()
        let client = makeClient(transport: transport, sleeps: sleeps)
        let draft = StravaActivityDraft(run: makeRun(route: twoSegmentRoute()))
        let result = try await client.uploadGPX(draft: draft, accessToken: "tok")
        XCTAssertEqual(result, .onStrava(activityID: 9_001))
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/v3/uploads", "/api/v3/uploads/555", "/api/v3/uploads/555"])
        XCTAssertEqual(sleeps.values, [1, 2])
    }

    func testGPXUploadGivesUpAfterFivePollsButKeepsTheUploadID() async throws {
        var responses: [(Int, String)] = [(201, #"{"id":77,"error":null,"activity_id":null}"#)]
        responses += Array(repeating: (200, #"{"id":77,"error":null,"activity_id":null}"#), count: 5)
        let transport = ScriptedTransport(responses: responses)
        let sleeps = SleepRecorder()
        let client = makeClient(transport: transport, sleeps: sleeps)
        let result = try await client.uploadGPX(draft: StravaActivityDraft(run: makeRun(route: twoSegmentRoute())), accessToken: "tok")
        XCTAssertEqual(result, .processing(uploadID: 77))
        XCTAssertEqual(sleeps.values, [1, 2, 4, 8, 15])
        XCTAssertEqual(transport.requests.count, 6)
    }

    func testDuplicateRefusalCountsAsAlreadyOnStrava() async throws {
        let transport = ScriptedTransport(responses: [
            (400, #"{"id":1,"error":"runsmart-x.gpx duplicate of activity 31337","status":"There was an error processing your activity.","activity_id":null}"#)
        ])
        let result = try await makeClient(transport: transport).uploadGPX(
            draft: StravaActivityDraft(run: makeRun(route: twoSegmentRoute())), accessToken: "tok"
        )
        XCTAssertEqual(result, .onStrava(activityID: 31_337))
    }

    func testUnauthorizedUploadIsReported() async {
        let transport = ScriptedTransport(responses: [(401, #"{"message":"Authorization Error"}"#)])
        do {
            _ = try await makeClient(transport: transport).uploadGPX(
                draft: StravaActivityDraft(run: makeRun(route: twoSegmentRoute())), accessToken: "tok"
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? StravaError, .unauthorized)
        }
    }

    // MARK: Coordinator

    private func makeCoordinator(
        run: RecordedRun,
        stored: RecordedRun? = nil,
        transport: ScriptedTransport,
        connected: Bool = true,
        defaults: UserDefaults? = nil
    ) -> (StravaUploadCoordinator, FakeRunStore, StravaPendingLedger) {
        let suite = defaults ?? UserDefaults(suiteName: "StravaTests-\(UUID().uuidString)")!
        let tokens = connected ? sampleTokens(expiresIn: 3_600) : nil
        let connection = makeService(tokens: tokens, transport: transport)
        let runs = FakeRunStore(runs: [stored ?? run])
        let ledger = StravaPendingLedger(defaults: suite, key: "pending")
        let coordinator = StravaUploadCoordinator(
            connection: connection,
            store: runs,
            ledger: ledger,
            defaults: suite,
            makeClient: { self.makeClient(transport: transport) }
        )
        return (coordinator, runs, ledger)
    }

    func testSuccessfulUploadStoresTheActivityIDOnTheRun() async {
        let run = makeRun(route: twoSegmentRoute())
        let transport = ScriptedTransport(responses: [(201, #"{"id":5,"error":null,"activity_id":4242}"#)])
        let (coordinator, runs, ledger) = makeCoordinator(run: run, transport: transport)
        await coordinator.upload(run)
        XCTAssertEqual(runs.activityIDs[run.id], 4_242)
        XCTAssertEqual(coordinator.status(for: runs.storedRun(id: run.id)!), .onStrava(4_242))
        XCTAssertTrue(ledger.all().isEmpty)
    }

    func testRunAlreadyOnStravaMakesNoRequest() async {
        let run = makeRun(route: twoSegmentRoute(), stravaID: 11)
        let transport = ScriptedTransport(responses: [])
        let (coordinator, _, _) = makeCoordinator(run: run, transport: transport)
        await coordinator.upload(run)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(coordinator.status(for: run), .onStrava(11))
    }

    func testStoredActivityIDStopsAStaleCopyFromUploadingAgain() async {
        let stale = makeRun(route: twoSegmentRoute())
        var stored = stale
        stored.stravaActivityID = 77
        let transport = ScriptedTransport(responses: [])
        let (coordinator, _, _) = makeCoordinator(run: stale, stored: stored, transport: transport)
        await coordinator.upload(stale)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(coordinator.status(for: stale), .onStrava(77))
    }

    func testRunWithoutARouteIsCreatedAsAManualActivity() async {
        let run = makeRun(route: [])
        let transport = ScriptedTransport(responses: [(201, #"{"id":6060}"#)])
        let (coordinator, runs, _) = makeCoordinator(run: run, transport: transport)
        await coordinator.upload(run)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/v3/activities"])
        XCTAssertEqual(runs.activityIDs[run.id], 6_060)
    }

    func testFailureIsKeptForRetryAndRetrySucceeds() async {
        let run = makeRun(route: twoSegmentRoute())
        let transport = ScriptedTransport(responses: [
            (500, "{}"),
            (201, #"{"id":5,"error":null,"activity_id":808}"#)
        ])
        let (coordinator, runs, ledger) = makeCoordinator(run: run, transport: transport)
        await coordinator.upload(run)
        XCTAssertEqual(coordinator.status(for: run), .failed)
        XCTAssertEqual(ledger.all().map(\.runID), [run.id])
        XCTAssertNil(runs.activityIDs[run.id])

        await coordinator.retryPending()
        XCTAssertEqual(runs.activityIDs[run.id], 808)
        XCTAssertTrue(ledger.all().isEmpty)
    }

    func testStillProcessingUploadIsPolledNotResentOnRetry() async {
        let run = makeRun(route: twoSegmentRoute())
        var first: [(Int, String)] = [(201, #"{"id":9,"error":null,"activity_id":null}"#)]
        first += Array(repeating: (200, #"{"id":9,"error":null,"activity_id":null}"#), count: 5)
        first.append((200, #"{"id":9,"error":null,"activity_id":1212}"#))
        let transport = ScriptedTransport(responses: first)
        let (coordinator, runs, ledger) = makeCoordinator(run: run, transport: transport)
        await coordinator.upload(run)
        XCTAssertEqual(ledger.entry(for: run.id)?.uploadID, 9)
        XCTAssertEqual(coordinator.status(for: run), .sending)

        await coordinator.retryPending()
        XCTAssertEqual(transport.requests.last?.url?.path, "/api/v3/uploads/9")
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1, "the file is sent once")
        XCTAssertEqual(runs.activityIDs[run.id], 1_212)
    }

    func testAutoUploadFollowsTheSettingAndTheConnection() async {
        let run = makeRun(route: twoSegmentRoute())
        let transport = ScriptedTransport(responses: [(201, #"{"id":5,"error":null,"activity_id":1}"#)])
        let (coordinator, runs, _) = makeCoordinator(run: run, transport: transport)
        XCTAssertTrue(coordinator.autoUploadEnabled, "default on")

        coordinator.autoUploadEnabled = false
        await coordinator.autoUploadIfEnabled(run)
        XCTAssertTrue(transport.requests.isEmpty)

        coordinator.autoUploadEnabled = true
        await coordinator.autoUploadIfEnabled(run)
        XCTAssertEqual(runs.activityIDs[run.id], 1)

        let notConnectedTransport = ScriptedTransport(responses: [])
        let (offline, _, _) = makeCoordinator(run: run, transport: notConnectedTransport, connected: false)
        await offline.autoUploadIfEnabled(run)
        XCTAssertTrue(notConnectedTransport.requests.isEmpty)
    }

    func testStatusLinesMatchTheSummaryCopy() {
        XCTAssertEqual(StravaUploadStatus.sending.statusLine, "Sending to Strava...")
        XCTAssertEqual(StravaUploadStatus.onStrava(1).statusLine, "On Strava")
        XCTAssertEqual(StravaUploadStatus.failed.statusLine, "Strava upload failed. Retry")
        XCTAssertNil(StravaUploadStatus.ready.statusLine)
    }

    func testRPEUpdateKeepsTheStravaActivityIDOnTheStoredRun() {
        let store = RunSmartLocalStore.shared
        let id = UUID()
        var run = makeRun(id: id, route: twoSegmentRoute())
        run.startedAt = Date(timeIntervalSinceNow: -10_000_000) // far from real data
        store.saveRun(run)
        defer { _ = store.removeRun(run) }
        store.setStravaActivityID(31, forRunID: id)
        let updated = store.updateRunRPE(run, rpe: 6) // `run` is a stale copy without the id
        XCTAssertEqual(updated.stravaActivityID, 31)
        XCTAssertEqual(store.loadRuns().first(where: { $0.id == id })?.stravaActivityID, 31)
    }

    // MARK: Helpers

    private func makeService(
        tokens: StravaTokens?,
        transport: ScriptedTransport,
        authorizer: StravaAuthorizing? = nil
    ) -> StravaConnectionService {
        makeService(store: InMemoryStravaTokenStore(tokens: tokens), transport: transport, authorizer: authorizer)
    }

    private func makeService(
        store: InMemoryStravaTokenStore,
        transport: ScriptedTransport,
        authorizer: StravaAuthorizing? = nil
    ) -> StravaConnectionService {
        StravaConnectionService(
            tokenStore: store,
            clientID: { "123" },
            supabaseAccessToken: { "supabase-jwt" },
            makeClient: { self.makeClient(transport: transport) },
            authorizer: authorizer
        )
    }

    private func makeClient(transport: ScriptedTransport, sleeps: SleepRecorder = SleepRecorder()) -> StravaClient {
        StravaClient(
            transport: transport,
            functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
            publishableKey: "pub",
            sleep: { seconds in sleeps.record(seconds) }
        )
    }
}

// MARK: - Test doubles

private final class ScriptedTransport: StravaTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) { queue = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: (Int, String) = lock.withLock {
            requests.append(request)
            return queue.isEmpty ? (500, "{}") : queue.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: nil)!
        return (Data(next.1.utf8), response)
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    var values: [TimeInterval] { lock.withLock { recorded } }
    func record(_ seconds: TimeInterval) { lock.withLock { recorded.append(seconds) } }
}

@MainActor
private final class ScriptedAuthorizer: StravaAuthorizing {
    private let reply: (URL) -> URL
    private(set) var calls = 0
    init(reply: @escaping (URL) -> URL) { self.reply = reply }
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        calls += 1
        return reply(url)
    }
}

@MainActor
private final class FakeRunStore: StravaRunStoring {
    private var runs: [UUID: RecordedRun]
    private(set) var activityIDs: [UUID: Int] = [:]

    init(runs: [RecordedRun]) { self.runs = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) }) }

    func storedRun(id: UUID) -> RecordedRun? { runs[id] }

    func setStravaActivityID(_ activityID: Int, forRunID runID: UUID) {
        activityIDs[runID] = activityID
        runs[runID]?.stravaActivityID = activityID
    }
}
