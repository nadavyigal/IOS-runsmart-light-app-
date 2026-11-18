import CoreLocation
import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachRouteUploadTests: XCTestCase {
    private struct TestPreparer: RouteUploadPreparer {
        func prepare(_ points: [RunRoutePoint], distanceMeters: Double) -> RouteUploadPreparation {
            RouteUploadPreparation(
                points: CoachRouteCoordinate.encodePreparedPoints(points) ?? [],
                radiusMeters: 250
            )
        }
    }

    /// Deterministic draws for the radius range. Not used for production uploads.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private enum NetworkError: Error { case offline }

    private let owner = UUID()
    private let link = CoachLink(id: UUID(), coachID: UUID(), coachName: "Dana",
                                 consentedAt: Date(timeIntervalSince1970: 1_000))

    private func makeRun() -> RecordedRun {
        let start = link.consentedAt.addingTimeInterval(60)
        return RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart,
                           startedAt: start, endedAt: start.addingTimeInterval(300),
                           distanceMeters: 1_000, movingTimeSeconds: 300,
                           averagePaceSecondsPerKm: 300, averageHeartRateBPM: nil,
                           routePoints: [
                            .init(latitude: 32.123456, longitude: 34.987654, timestamp: start,
                                  horizontalAccuracy: 4, altitude: 2),
                            .init(latitude: 32.13, longitude: 35, timestamp: start.addingTimeInterval(4),
                                  horizontalAccuracy: 4, altitude: 3)
                           ], syncedAt: nil)
    }

    func testPolicyIsOnAndReleaseCoachModeStillUploadsNothing() throws {
        XCTAssertTrue(RouteUploadPolicy.isEnabled)
        XCTAssertFalse(RunSmartFeatures.coachModeEnabled(processArguments: [], isDebugBuild: false))
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults)
        outbox.stage(makeRun(), ownerID: owner, link: link, coachModeEnabled: false)
        XCTAssertTrue(outbox.pending.isEmpty)
    }

    func testEligibilityAndSharingAreScopedToConsent() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: TestPreparer())
        var health = makeRun()
        health.source = .healthKit
        var garmin = makeRun()
        garmin.source = .garmin
        var imported = makeRun()
        imported.providerActivityID = "external"
        var past = makeRun()
        past.startedAt = link.consentedAt.addingTimeInterval(-60)
        var noGPS = makeRun()
        noGPS.routePoints = []
        for run in [health, garmin, imported, past, noGPS] {
            outbox.stage(run, ownerID: owner, link: link, coachModeEnabled: true)
        }
        let eligible = makeRun()
        outbox.stage(eligible, ownerID: owner, link: link, coachModeEnabled: false)
        XCTAssertTrue(outbox.pending.isEmpty)
        outbox.stage(eligible, ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertEqual(outbox.pending.map(\.runID), [eligible.id])
        outbox.setSharing(false, ownerID: owner, linkID: link.id)
        outbox.stage(makeRun(), ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertTrue(outbox.pending.isEmpty)
        XCTAssertTrue(outbox.sharing(ownerID: owner, linkID: UUID()))
        XCTAssertTrue(outbox.sharing(ownerID: UUID(), linkID: link.id))
    }

    func testRetryUsesPersistedCoordinatesAfterFailure() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: TestPreparer())
        let run = makeRun()
        outbox.stage(run, ownerID: owner, link: link, coachModeEnabled: true)
        await outbox.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { _ in
            throw NetworkError.offline
        }
        let reopened = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: TestPreparer())
        XCTAssertEqual(reopened.pending.count, 1)
        await reopened.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in false }) { _ in
            XCTFail("Must not send without a current link")
            return .stopped
        }
        await reopened.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { _ in .missing }
        XCTAssertEqual(reopened.pending.count, 1)
        await reopened.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { item in
            XCTAssertEqual(item.runID, run.id)
            XCTAssertEqual(item.points, [.init(lat: 32.12346, lng: 34.98765), .init(lat: 32.13, lng: 35)])
            return .saved
        }
        XCTAssertTrue(reopened.pending.isEmpty)
    }

    func testMapControlRequiresRecordedRunAndCurrentLink() {
        var run = makeRun()
        XCTAssertNil(AthleteMapControl.key(run: run, owner: owner, link: nil, enabled: true))
        XCTAssertNil(AthleteMapControl.key(run: run, owner: nil, link: link, enabled: true))
        XCTAssertNil(AthleteMapControl.key(run: run, owner: owner, link: link, enabled: false))
        XCTAssertEqual(AthleteMapControl.key(run: run, owner: owner, link: link, enabled: true),
                       CoachMapKey(ownerID: owner, runID: run.id))
        run.providerActivityID = "import"
        XCTAssertNil(AthleteMapControl.key(run: run, owner: owner, link: link, enabled: true))
        run.providerActivityID = nil
        run.source = .healthKit
        XCTAssertNil(AthleteMapControl.key(run: run, owner: owner, link: link, enabled: true))
    }

    func testHideWhileUploadIsInFlightKeepsLatestChoice() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: TestPreparer())
        outbox.stage(makeRun(), ownerID: owner, link: link, coachModeEnabled: true)
        let key = try XCTUnwrap(outbox.pending.first?.mapKey)
        await outbox.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { item in
            outbox.setHidden(true, for: item.mapKey, linkID: link.id)
            return .saved
        }
        XCTAssertTrue(outbox.pending.isEmpty)
        outbox.recordServerState(false, for: key, expected: nil)
        XCTAssertEqual(outbox.choice(for: key), CoachMapChoice(hidden: true, needsSync: true))
    }

    func testHideBeforeUploadSurvivesRelaunchAndUnhideSendsOnce() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: TestPreparer())
        let run = makeRun()
        let key = CoachMapKey(ownerID: owner, runID: run.id)
        XCTAssertNil(outbox.choice(for: key))
        outbox.stage(run, ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertEqual(outbox.choice(for: key)?.hidden, false)
        outbox.setHidden(true, for: key, linkID: link.id)
        let reopened = CoachRouteOutbox(defaults: defaults, enabled: true)
        XCTAssertEqual(reopened.choice(for: key)?.needsSync, true)
        await reopened.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { _ in
            XCTFail("Hidden pending map uploaded")
            return .saved
        }
        let hidden = try XCTUnwrap(reopened.choice(for: key))
        XCTAssertTrue(hidden.canSync(activeLinkID: nil))
        XCTAssertTrue(hidden.canSync(activeLinkID: UUID()))
        reopened.acknowledge(hidden, for: key)
        reopened.recordServerState(nil, for: key, expected: reopened.choices[key])
        XCTAssertEqual(reopened.choice(for: key)?.hidden, true, "Detail refresh must preserve a withheld route")
        reopened.setHidden(false, for: key, linkID: link.id)
        reopened.acknowledge(hidden, for: key)
        XCTAssertEqual(reopened.choice(for: key)?.needsSync, true)
        XCTAssertFalse(try XCTUnwrap(reopened.choice(for: key)).canSync(activeLinkID: UUID()))
        XCTAssertTrue(try XCTUnwrap(reopened.choice(for: key)).canSync(activeLinkID: link.id))
        var sends = 0
        for _ in 0..<2 {
            await reopened.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { _ in
                sends += 1
                return .saved
            }
        }
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(AthleteMapControl.label(coach: "Dana", detail: true, hidden: true), "You hid this map from Dana")
        XCTAssertEqual(AthleteMapControl.label(coach: "Dana", detail: false, hidden: true), "Hide map from Dana")
    }

    func testWebCoordinateShapeAndCap() throws {
        let first = makeRun().routePoints[0]
        var last = first
        last.longitude = 35
        let points = try XCTUnwrap(CoachRouteCoordinate.encodePreparedPoints(
            Array(repeating: first, count: 999) + [last]
        ))
        XCTAssertEqual(points.count, 512)
        XCTAssertEqual(points.last?.lng, 35)
        let data = try JSONEncoder().encode(points)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Double]])
        XCTAssertEqual(Set(try XCTUnwrap(decoded.first).keys), Set(["lat", "lng"]))
        XCTAssertEqual(try JSONDecoder().decode([CoachRouteCoordinate].self, from: data), points)
    }

    func testDefaultPreparerWithholdsARouteThatIsOnlyItsEndpoints() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true)
        outbox.stage(makeRun(), ownerID: owner, link: link, coachModeEnabled: true)
        let item = try XCTUnwrap(outbox.pending.first)
        XCTAssertNil(outbox.choice(for: item.mapKey))
        XCTAssertEqual(item.status, .tooShort)
        XCTAssertTrue(item.points.isEmpty)
        XCTAssertGreaterThanOrEqual(item.radiusMeters, 200)
        XCTAssertLessThanOrEqual(item.radiusMeters, 300)
    }

    func testNoUploadedPointLiesWithin200MetersForManyRadii() {
        let route = northLine(meters: 4_000)
        let start = route[0]
        let finish = route[route.count - 1]
        var generator = SeededGenerator(state: 0x64)
        var radii: [Double] = []
        for _ in 0..<24 {
            let radius = RouteSharePrivacy.randomCoachUploadRadius(using: &generator)
            radii.append(radius)
            let prepared = PrivacyZoneRouteUploadPreparer(nextRadius: { radius })
                .prepare(route, distanceMeters: 4_000)
            XCTAssertEqual(prepared.status, .shared)
            XCTAssertGreaterThanOrEqual(prepared.points.count, 2)
            for point in prepared.points {
                XCTAssertGreaterThan(meters(from: start, to: point), 200)
                XCTAssertGreaterThan(meters(from: finish, to: point), 200)
                XCTAssertGreaterThan(meters(from: start, to: point), radius)
                XCTAssertGreaterThan(meters(from: finish, to: point), radius)
            }
        }
        XCTAssertGreaterThan(Set(radii.map { Int($0) }).count, 1)
    }

    func testRadiusStaysInside200To300AndVariesBetweenRuns() throws {
        var generator = SeededGenerator(state: 7)
        var samples: [Double] = []
        for _ in 0..<40 {
            let radius = RouteSharePrivacy.randomCoachUploadRadius(using: &generator)
            XCTAssertGreaterThanOrEqual(radius, RouteSharePrivacy.coachUploadRadiusRange.lowerBound)
            XCTAssertLessThanOrEqual(radius, RouteSharePrivacy.coachUploadRadiusRange.upperBound)
            samples.append(radius)
        }
        XCTAssertGreaterThan(Set(samples.map { Int($0) }).count, 1)

        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var drawn = [210.0, 280.0]
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: PrivacyZoneRouteUploadPreparer {
            drawn.removeFirst()
        })
        outbox.stage(recorded(northLine(meters: 3_000), distance: 3_000), ownerID: owner, link: link, coachModeEnabled: true)
        outbox.stage(recorded(northLine(meters: 3_000, startLatitude: 33), distance: 3_000), ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertEqual(outbox.pending.map(\.radiusMeters), [210, 280])
        XCTAssertTrue(drawn.isEmpty)
    }

    func testPointsNearTheStartAndAMidRunReturnToTheStartAreRemoved() throws {
        let radius = 250.0
        let route = loopThatPassesTheStart()
        let original = route
        let kept = RouteSharePrivacy.pointsOutsideEndpointRadius(route, radiusMeters: radius)
        XCTAssertEqual(route, original)
        XCTAssertFalse(kept.contains { meters(from: route[0], to: $0) <= radius })
        XCTAssertFalse(kept.contains { meters(from: route[route.count - 1], to: $0) <= radius })
        let revisit = try XCTUnwrap(route.first { $0.altitude == 99 })
        let nearFinish = try XCTUnwrap(route.first { $0.altitude == 77 })
        XCTAssertLessThanOrEqual(meters(from: route[0], to: revisit), radius)
        XCTAssertLessThanOrEqual(meters(from: route[route.count - 1], to: nearFinish), radius)
        XCTAssertFalse(kept.contains(revisit))
        XCTAssertFalse(kept.contains(nearFinish))
        XCTAssertTrue(kept.contains { meters(from: route[0], to: $0) > 1_000 })
        XCTAssertTrue(kept.allSatisfy { $0.startsNewSegment != true })
        let prepared = PrivacyZoneRouteUploadPreparer(nextRadius: { radius }).prepare(route, distanceMeters: 4_000)
        XCTAssertEqual(prepared.status, .shared)
        for point in prepared.points {
            XCTAssertGreaterThan(meters(from: route[0], to: point), radius)
            XCTAssertGreaterThan(meters(from: route[route.count - 1], to: point), radius)
        }
    }

    func testRunUnderOneKilometerUploadsNoRoute() throws {
        XCTAssertEqual(RouteSharePrivacy.coachUploadMinimumRunMeters, 1_000)
        let route = northLine(meters: 5_000)
        let prepared = PrivacyZoneRouteUploadPreparer(nextRadius: { 220 }).prepare(route, distanceMeters: 999)
        XCTAssertTrue(prepared.points.isEmpty)
        XCTAssertEqual(prepared.status, .tooShort)
        let exact = PrivacyZoneRouteUploadPreparer(nextRadius: { 220 }).prepare(route, distanceMeters: 1_000)
        XCTAssertEqual(exact.status, .shared)

        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: PrivacyZoneRouteUploadPreparer { 220 })
        outbox.stage(recorded(route, distance: 999), ownerID: owner, link: link, coachModeEnabled: true)
        let item = try XCTUnwrap(outbox.pending.first)
        XCTAssertEqual(item.status, .tooShort)
        XCTAssertTrue(item.points.isEmpty)
        XCTAssertEqual(item.radiusMeters, 220)
    }

    func testRunWhosePointsAllFallInsideTheZonesUploadsNoRoute() {
        let start = link.consentedAt.addingTimeInterval(120)
        var points: [RunRoutePoint] = (0..<8).map { index in
            RunRoutePoint(
                latitude: 32.2 + Double(index) * 10 * degreesPerMeter,
                longitude: 34.9,
                timestamp: start.addingTimeInterval(Double(index)),
                horizontalAccuracy: 5,
                altitude: 1
            )
        }
        points.append(points[0])
        let prepared = PrivacyZoneRouteUploadPreparer(nextRadius: { 200 }).prepare(points, distanceMeters: 2_000)
        XCTAssertTrue(prepared.points.isEmpty)
        XCTAssertEqual(prepared.status, .tooShort)
    }

    func testStatsAndSplitsStayOnTheFullRoute() {
        let points = northLine(meters: 5_000)
        var run = recorded(points, distance: 5_000)
        let splits = RunRecorder.kilometerSplits(from: run.routePoints)
        let length = RouteSharePrivacy.pathLengthMeters(run.routePoints)
        XCTAssertFalse(splits.isEmpty)
        let prepared = PrivacyZoneRouteUploadPreparer(nextRadius: { 250 })
            .prepare(run.routePoints, distanceMeters: run.distanceMeters)
        XCTAssertEqual(prepared.status, .shared)
        XCTAssertLessThan(prepared.points.count, run.routePoints.count)
        XCTAssertEqual(run.routePoints, points)
        XCTAssertEqual(run.distanceMeters, 5_000)
        XCTAssertEqual(run.averagePaceSecondsPerKm, 300)
        XCTAssertEqual(RunRecorder.kilometerSplits(from: run.routePoints), splits)
        XCTAssertEqual(RouteSharePrivacy.pathLengthMeters(run.routePoints), length, accuracy: 0.001)
    }

    func testRetryUsesTheSameRadius() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var draws = 0
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: PrivacyZoneRouteUploadPreparer {
            draws += 1
            return draws == 1 ? 230 : 290
        })
        let run = recorded(northLine(meters: 3_000), distance: 3_000)
        let expected = PrivacyZoneRouteUploadPreparer(nextRadius: { 230 }).prepare(run.routePoints, distanceMeters: 3_000)
        outbox.stage(run, ownerID: owner, link: link, coachModeEnabled: true)
        outbox.stage(run, ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertEqual(draws, 1)
        await outbox.retry(ownerID: owner, coachModeEnabled: true, canSend: { _ in true }) { item in
            XCTAssertEqual(item.radiusMeters, 230)
            XCTAssertEqual(item.status, .shared)
            XCTAssertEqual(item.points, expected.points)
            return .saved
        }
        XCTAssertEqual(draws, 1)
        XCTAssertTrue(outbox.pending.isEmpty)
    }

    func testShortRouteWriteDecodesTheDatabaseBigintID() throws {
        let rows = try JSONDecoder().decode(
            [CoachRunRowID].self, from: Data(#"[{"id":2147483648}]"#.utf8)
        )
        XCTAssertEqual(rows.first?.id, 2_147_483_648)
    }

    func testUploadPayloadNeverSerializesRawRoutePoints() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults, enabled: true, preparer: PrivacyZoneRouteUploadPreparer { 240 })
        let run = recorded(northLine(meters: 3_000), distance: 3_000)
        outbox.stage(run, ownerID: owner, link: link, coachModeEnabled: true)
        let item = try XCTUnwrap(outbox.pending.first)
        let data = try JSONEncoder().encode(CoachRunRouteParams(item: item))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let points = try XCTUnwrap(object["prepared_route"] as? [[String: Any]])
        XCTAssertFalse(points.isEmpty)
        for point in points {
            XCTAssertEqual(Set(point.keys), Set(["lat", "lng"]))
        }
        XCTAssertFalse(text.contains("timestamp"))
        XCTAssertFalse(text.contains("horizontalAccuracy"))
        XCTAssertFalse(text.contains("altitude"))
        XCTAssertFalse(text.contains("startsNewSegment"))
        XCTAssertFalse(text.contains("32.08501"))
        let withheld = try JSONEncoder().encode(CoachRouteTooShortUpdate())
        let withheldObject = try XCTUnwrap(JSONSerialization.jsonObject(with: withheld) as? [String: Any])
        XCTAssertEqual(Set(withheldObject.keys), Set(["route", "route_status"]))
        XCTAssertTrue(withheldObject["route"] is NSNull)
        XCTAssertEqual(withheldObject["route_status"] as? String, "too_short")
    }

    private let degreesPerMeter = 1.0 / 110_850.0

    private func northLine(meters: Double, spacing: Double = 20, startLatitude: Double = 32.0850123) -> [RunRoutePoint] {
        let count = Int((meters / spacing).rounded(.down)) + 1
        let start = link.consentedAt.addingTimeInterval(120)
        return (0..<count).map { index in
            RunRoutePoint(
                latitude: startLatitude + Double(index) * spacing * degreesPerMeter,
                longitude: 34.8,
                timestamp: start.addingTimeInterval(Double(index)),
                horizontalAccuracy: 5,
                altitude: 12
            )
        }
    }

    private func recorded(_ points: [RunRoutePoint], distance: Double) -> RecordedRun {
        let start = points[0].timestamp
        return RecordedRun(
            id: UUID(), providerActivityID: nil, source: .runSmart,
            startedAt: start, endedAt: points[points.count - 1].timestamp.addingTimeInterval(1),
            distanceMeters: distance, movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 300, averageHeartRateBPM: nil,
            routePoints: points, syncedAt: nil
        )
    }

    /// North for 1.5 km, back to 100 m from the start, then out to a finish 1.5 km east of that far point.
    private func loopThatPassesTheStart() -> [RunRoutePoint] {
        let start = link.consentedAt.addingTimeInterval(120)
        func point(_ north: Double, _ east: Double, at seconds: TimeInterval) -> RunRoutePoint {
            RunRoutePoint(
                latitude: 32.0 + north * degreesPerMeter,
                longitude: 34.8 + east * degreesPerMeter,
                timestamp: start.addingTimeInterval(seconds),
                horizontalAccuracy: 5,
                altitude: 4
            )
        }
        var points: [RunRoutePoint] = []
        var second = 0.0
        for north in stride(from: 0.0, through: 1_500, by: 100) {
            points.append(point(north, 0, at: second))
            second += 1
        }
        var revisit = point(100, 0, at: second)
        revisit.altitude = 99
        points.append(revisit)
        second += 1
        for north in stride(from: 200.0, through: 1_500, by: 100) {
            points.append(point(north, 0, at: second))
            second += 1
        }
        var nearFinish = point(1_500, 1_450, at: second)
        nearFinish.altitude = 77
        points.append(nearFinish)
        second += 1
        points.append(point(1_500, 1_500, at: second))
        return points
    }

    private func meters(from point: RunRoutePoint, to other: RunRoutePoint) -> Double {
        CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    private func meters(from point: RunRoutePoint, to coordinate: CoachRouteCoordinate) -> Double {
        CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: coordinate.lat, longitude: coordinate.lng))
    }
}
