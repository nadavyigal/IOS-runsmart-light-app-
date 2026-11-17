import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachRouteUploadTests: XCTestCase {
    private struct TestPreparer: RouteUploadPreparer {
        func prepare(_ points: [RunRoutePoint]) -> [CoachRouteCoordinate]? {
            CoachRouteCoordinate.encodePreparedPoints(points)
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

    func testShippingDefaultsNeverQueue() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = CoachRouteOutbox(defaults: defaults)
        XCTAssertFalse(RouteUploadPolicy.isEnabled)
        outbox.stage(makeRun(), ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertTrue(outbox.pending.isEmpty)
        let preparerDisabled = CoachRouteOutbox(defaults: defaults, enabled: true)
        preparerDisabled.stage(makeRun(), ownerID: owner, link: link, coachModeEnabled: true)
        XCTAssertTrue(preparerDisabled.pending.isEmpty)
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
}
