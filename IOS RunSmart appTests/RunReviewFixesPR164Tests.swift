import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Review fixes on PR 164: stale copies, Health duplicates, share-map privacy.
@MainActor
final class RunReviewFixesPR164Tests: XCTestCase {
    private let store = RunSmartLocalStore.shared

    /// A provider run far in the past so it cannot collide with real data in the test host.
    private func providerRun(providerID: String = "garmin-\(UUID().uuidString)") -> RecordedRun {
        RecordedRun(
            id: UUID(),
            providerActivityID: providerID,
            source: .garmin,
            startedAt: Date(timeIntervalSinceNow: -20_000_000),
            endedAt: Date(timeIntervalSinceNow: -20_000_000 + 1_800),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil
        )
    }

    private func ownRun() -> RecordedRun {
        var run = providerRun()
        run.providerActivityID = nil
        run.source = .runSmart
        return run
    }

    // MARK: Provider re-sync keeps what the runner set

    func testProviderResyncKeepsEffortTitleNotesAndStravaID() {
        let first = providerRun()
        store.saveRun(first)
        defer { _ = store.removeRun(first) }
        _ = store.updateRunRPE(first, rpe: 7)
        _ = store.updateRunDetails(first, title: "Long one", notes: "Hot day")
        store.setStravaActivityID(99, forRunID: first.id)

        var fresh = first // a new copy from Garmin: nothing local on it
        fresh.rpe = nil
        fresh.title = nil
        fresh.notes = nil
        fresh.stravaActivityID = nil
        fresh.distanceMeters = 5_100
        store.saveRun(fresh)

        let stored = try? XCTUnwrap(store.loadRuns().first { $0.id == first.id })
        XCTAssertEqual(stored?.distanceMeters, 5_100, "the provider data still replaces the old data")
        XCTAssertEqual(stored?.rpe, 7)
        XCTAssertEqual(stored?.title, "Long one")
        XCTAssertEqual(stored?.notes, "Hot day")
        XCTAssertEqual(stored?.stravaActivityID, 99)
    }

    func testRunnerCanStillClearEffortAndNotesOnAProviderRun() {
        let run = providerRun()
        store.saveRun(run)
        defer { _ = store.removeRun(run) }
        _ = store.updateRunRPE(run, rpe: 5)
        _ = store.updateRunDetails(run, title: nil, notes: "x")
        _ = store.updateRunRPE(run, rpe: nil)
        _ = store.updateRunDetails(run, title: nil, notes: nil)
        let stored = store.loadRuns().first { $0.id == run.id }
        XCTAssertNil(stored?.rpe)
        XCTAssertNil(stored?.notes)
    }

    // MARK: Stale copies written after an await

    func testSyncMarkChangesOnlyTheSyncTime() {
        let run = ownRun()
        store.saveRun(run)
        defer { _ = store.removeRun(run) }
        let stale = run // read before the upsert started
        _ = store.updateRunRPE(run, rpe: 8)
        _ = store.updateRunDetails(run, title: "Tempo", notes: "Felt strong")
        store.setStravaActivityID(5, forRunID: run.id)

        store.markRunSynced(stale, at: Date(timeIntervalSince1970: 1_700_000_000))

        let stored = store.loadRuns().first { $0.id == run.id }
        XCTAssertEqual(stored?.syncedAt, Date(timeIntervalSince1970: 1_700_000_000).roundedToISOSecond)
        XCTAssertEqual(stored?.rpe, 8)
        XCTAssertEqual(stored?.title, "Tempo")
        XCTAssertEqual(stored?.notes, "Felt strong")
        XCTAssertEqual(stored?.stravaActivityID, 5)
    }

    func testSyncMarkDoesNotBringBackADeletedRun() {
        let run = ownRun()
        store.saveRun(run)
        _ = store.removeRun(run)
        store.markRunSynced(run)
        XCTAssertNil(store.loadRuns().first { $0.id == run.id })
    }

    func testRouteMatchSaveKeepsEditsMadeWhileTheMatchWasComputed() {
        let run = ownRun()
        store.saveRun(run)
        defer { _ = store.removeRun(run) }
        var stale = run
        stale.routeMatchResult = RouteMatchingService.exactMatch(routeID: UUID())
        _ = store.updateRunRPE(run, rpe: 4)
        _ = store.updateRunDetails(run, title: "Easy", notes: "Slow start")

        let saved = store.saveRunKeepingLocalEdits(stale)

        let stored = store.loadRuns().first { $0.id == run.id }
        XCTAssertEqual(stored?.routeMatchResult, stale.routeMatchResult, "the match is saved")
        XCTAssertEqual(stored?.rpe, 4)
        XCTAssertEqual(stored?.title, "Easy")
        XCTAssertEqual(stored?.notes, "Slow start")
        XCTAssertEqual(saved.rpe, 4, "the returned copy is the merged one")
    }

    func testMergeHelperPrefersStoredLocalFieldsAndFallsBackToTheNewCopy() {
        var stored = ownRun()
        stored.rpe = 3
        var incoming = stored
        incoming.rpe = nil
        incoming.title = "From incoming"
        let merged = incoming.keepingLocalFields(from: stored)
        XCTAssertEqual(merged.rpe, 3)
        XCTAssertEqual(merged.title, "From incoming")
        XCTAssertEqual(incoming.keepingLocalFields(from: nil), incoming)
    }

    // MARK: Health: one save per run, unknown is not "missing"

    func testFailedDuplicateCheckWritesNothing() {
        XCTAssertTrue(HealthKitSavePolicy.shouldWrite(alreadySaved: false))
        XCTAssertFalse(HealthKitSavePolicy.shouldWrite(alreadySaved: true))
        XCTAssertFalse(HealthKitSavePolicy.shouldWrite(alreadySaved: nil), "a failed query is unknown, not empty")
    }

    func testSavesForTheSameRunNeverOverlap() async {
        let gate = HealthKitSaveGate()
        let runID = UUID()
        let probe = OverlapProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await gate.acquire(runID)
                    await probe.enter()
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    await probe.leave()
                    await gate.release(runID)
                }
            }
        }
        let result = await probe.result()
        XCTAssertEqual(result.entered, 6)
        XCTAssertEqual(result.maximumAtOnce, 1)
    }

    func testDifferentRunsDoNotWaitForEachOther() async {
        let gate = HealthKitSaveGate()
        let first = UUID()
        await gate.acquire(first)
        await gate.acquire(UUID()) // returns at once
        await gate.release(first)
    }

    // MARK: Share map privacy

    private let degreesPerMeter = 1.0 / 110_850.0

    private func point(northMeters: Double, eastMeters: Double, index: Int, newSegment: Bool? = nil) -> RunRoutePoint {
        RunRoutePoint(
            latitude: 32.0 + northMeters * degreesPerMeter,
            longitude: 34.78 + eastMeters * degreesPerMeter / cos(32.0 * .pi / 180),
            timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 3),
            horizontalAccuracy: 5,
            altitude: nil,
            startsNewSegment: newSegment
        )
    }

    private func meters(_ a: RunRoutePoint, _ b: RunRoutePoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Out 600 m north, 300 m east, then back south and west through a point 60 m from the start, then
    /// away again, so the route passes the start in the middle and finishes elsewhere.
    private func routePassingNearTheStart() -> [RunRoutePoint] {
        var path: [(Double, Double)] = []
        for step in 0...60 { path.append((Double(step) * 10, 0)) } // north to 600 m
        for step in 1...30 { path.append((600, Double(step) * 10)) } // east to 300 m
        for step in 1...54 { path.append((600 - Double(step) * 10, 300)) } // south to 60 m north
        for step in 1...30 { path.append((60, 300 - Double(step) * 10)) } // west to the start's meridian: 60 m from the start
        for step in 1...50 { path.append((60 + Double(step) * 10, 0)) } // away north again, 500 m, finish
        return path.enumerated().map { point(northMeters: $0.element.0, eastMeters: $0.element.1, index: $0.offset) }
    }

    func testNoSharedPointIsWithinTwoHundredMetersOfTheStartOrFinishInAStraightLine() throws {
        let route = routePassingNearTheStart()
        let shared = try XCTUnwrap(RouteSharePrivacy.shareableRoute(route))
        let first = route[0]
        let last = route[route.count - 1]
        XCTAssertFalse(shared.isEmpty)
        for p in shared {
            XCTAssertGreaterThanOrEqual(meters(p, first), 199.9)
            XCTAssertGreaterThanOrEqual(meters(p, last), 199.9)
        }
    }

    func testHidingTheMiddleStartsANewSegmentSoNoLineCrossesTheHiddenArea() throws {
        let route = routePassingNearTheStart()
        let shared = try XCTUnwrap(RouteSharePrivacy.shareableRoute(route))
        let segments = RoutePointSegments.split(shared)
        XCTAssertGreaterThanOrEqual(segments.count, 2, "the pass near the start splits the line")
        for segment in segments {
            for (a, b) in zip(segment, segment.dropFirst()) {
                XCTAssertLessThan(meters(a, b), 25, "points inside one segment are neighbours, never a jump across the hidden area")
            }
        }
    }

    func testPlainOutAndBackStillTrimsOnlyTheEnds() throws {
        let route = (0...100).map { point(northMeters: Double($0) * 10, eastMeters: 0, index: $0) }
        let shared = try XCTUnwrap(RouteSharePrivacy.shareableRoute(route))
        XCTAssertEqual(RoutePointSegments.split(shared).count, 1)
        XCTAssertEqual(shared.count, 61, accuracy: 3)
    }
}

private extension Date {
    /// `RunSmartLocalStore` stores dates as ISO 8601 seconds.
    var roundedToISOSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded()) }
}

private actor OverlapProbe {
    private var current = 0
    private var maximum = 0
    private var entries = 0
    func enter() { current += 1; entries += 1; maximum = max(maximum, current) }
    func leave() { current -= 1 }
    func result() -> (entered: Int, maximumAtOnce: Int) { (entries, maximum) }
}
