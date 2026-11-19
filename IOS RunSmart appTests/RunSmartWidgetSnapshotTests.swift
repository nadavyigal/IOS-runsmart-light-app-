import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunSmartWidgetSnapshotTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!
    private var reloads = 0
    private var savedRuns: [RecordedRun] = []

    override func setUp() async throws {
        suiteName = "widget-snapshot-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        reloads = 0
        savedRuns = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeWriter() -> (RunSmartWidgetSnapshotWriter, RunSmartWidgetSnapshotStore) {
        let store = RunSmartWidgetSnapshotStore(defaults: defaults)
        let writer = RunSmartWidgetSnapshotWriter(
            snapshotStore: store,
            runs: { [unowned self] in self.savedRuns },
            reloadWidget: { [unowned self] in self.reloads += 1 },
            calendar: calendar
        )
        return (writer, store)
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func run(_ iso: String, km: Double) -> RecordedRun {
        RecordedRun(
            id: UUID(), providerActivityID: nil, source: .runSmart,
            startedAt: date(iso), endedAt: date(iso).addingTimeInterval(1_800),
            distanceMeters: km * 1_000, movingTimeSeconds: 1_800, averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: nil, routePoints: [], syncedAt: nil
        )
    }

    func testCountsOnlyThisWeeksRuns() {
        // Wednesday 2026-11-18; the week starts Monday 2026-11-16.
        savedRuns = [run("2026-11-16T07:00:00Z", km: 8), run("2026-11-18T06:00:00Z", km: 5.4), run("2026-11-14T07:00:00Z", km: 12)]
        let (writer, store) = makeWriter()
        writer.refresh(now: date("2026-11-18T20:00:00Z"))
        let snapshot = store.load()
        XCTAssertEqual(snapshot?.weekStart, date("2026-11-16T00:00:00Z"))
        XCTAssertEqual(snapshot?.weekDistanceMeters ?? 0, 13_400, accuracy: 0.001)
        XCTAssertNil(snapshot?.weekGoalMeters)
        XCTAssertEqual(reloads, 1)
    }

    func testGoalIsKeptForTheWeekAndDroppedNextWeek() {
        let (writer, store) = makeWriter()
        writer.recordWeekGoal(kilometers: 30, now: date("2026-11-17T08:00:00Z"))
        writer.refresh(isRunInProgress: true, now: date("2026-11-18T08:00:00Z"))
        XCTAssertEqual(store.load()?.weekGoalMeters, 30_000)
        XCTAssertEqual(store.load()?.isRunInProgress, true)

        writer.refresh(isRunInProgress: false, now: date("2026-11-23T08:00:00Z"))
        XCTAssertNil(store.load()?.weekGoalMeters)
        XCTAssertEqual(store.load()?.isRunInProgress, false)
    }

    func testNoPlanOrZeroGoalStoresNoGoal() {
        let (writer, store) = makeWriter()
        writer.recordWeekGoal(kilometers: 0, now: date("2026-11-17T08:00:00Z"))
        XCTAssertNil(store.load()?.weekGoalMeters)
        writer.recordWeekGoal(kilometers: nil, now: date("2026-11-17T09:00:00Z"))
        XCTAssertNil(store.load()?.weekGoalMeters)
    }

    func testTodayLoadRepairsAStaleDistance() {
        let (writer, store) = makeWriter()
        savedRuns = [run("2026-11-16T07:00:00Z", km: 8)]
        writer.refresh(now: date("2026-11-17T08:00:00Z"))
        savedRuns = [run("2026-11-16T07:00:00Z", km: 8), run("2026-11-17T07:00:00Z", km: 5)]
        writer.recordWeekGoal(kilometers: 30, now: date("2026-11-17T09:00:00Z"))
        XCTAssertEqual(store.load()?.weekDistanceMeters ?? 0, 13_000, accuracy: 0.001)
    }

    func testRunChangeNotificationRefreshesTheTotal() {
        let (writer, store) = makeWriter()
        let recorder = RunRecorder(store: .shared, checkpointStore: RunCheckpointStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        writer.bind(recorder: recorder)
        let now = Date()
        savedRuns = [RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart, startedAt: now.addingTimeInterval(-60),
                                 endedAt: now, distanceMeters: 4_200, movingTimeSeconds: 1_200, averagePaceSecondsPerKm: 286,
                                 averageHeartRateBPM: nil, routePoints: [], syncedAt: nil)]
        NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        let refreshed = expectation(description: "snapshot refreshed")
        DispatchQueue.main.async { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 2)
        XCTAssertEqual(store.load()?.weekDistanceMeters ?? 0, 4_200, accuracy: 0.001)
    }

    func testSameWorkoutFromTwoSourcesCountsOnce() {
        let start = date("2026-11-17T06:00:00Z")
        func copy(_ source: RunSmartDataSource, _ id: String, offset: TimeInterval, meters: Double) -> RecordedRun {
            RecordedRun(id: UUID(), providerActivityID: id, source: source, startedAt: start.addingTimeInterval(offset),
                        endedAt: start.addingTimeInterval(offset + 1_500), distanceMeters: meters, movingTimeSeconds: 1_500,
                        averagePaceSecondsPerKm: 300, averageHeartRateBPM: 148, routePoints: [], syncedAt: nil)
        }
        let runs = [copy(.garmin, "garmin-1", offset: 30, meters: 5_010), copy(.healthKit, "hk-1", offset: 40, meters: 5_000)]
        let visible = ActivityConsolidationService.userVisibleRecentRuns(runs, now: date("2026-11-17T09:00:00Z"), calendar: calendar)
        let meters = RunSmartWidgetSnapshotWriter.weekDistanceMeters(runs: visible, weekStart: date("2026-11-16T00:00:00Z"), calendar: calendar)
        XCTAssertEqual(meters, 5_010, accuracy: 20, "One workout, not two copies")
    }

    func testUnchangedSnapshotDoesNotReloadTheWidget() {
        let (writer, _) = makeWriter()
        writer.refresh(now: date("2026-11-18T08:00:00Z"))
        writer.refresh(now: date("2026-11-18T09:00:00Z"))
        writer.recordWeekGoal(kilometers: 30, now: date("2026-11-18T10:00:00Z"))
        writer.recordWeekGoal(kilometers: 30, now: date("2026-11-18T11:00:00Z"))
        XCTAssertEqual(reloads, 2)
    }

    func testClearRemovesTheSnapshotOnSignOut() {
        let (writer, store) = makeWriter()
        writer.recordWeekGoal(kilometers: 30, now: date("2026-11-17T08:00:00Z"))
        writer.clear()
        XCTAssertNil(store.load())
        XCTAssertEqual(reloads, 2)
        writer.clear()
        XCTAssertEqual(reloads, 2, "Clearing an empty store does not reload the widget")
    }

    func testMissingAppGroupIsANoOp() {
        let writer = RunSmartWidgetSnapshotWriter(
            snapshotStore: RunSmartWidgetSnapshotStore(defaults: nil),
            runs: { [] },
            reloadWidget: { [unowned self] in self.reloads += 1 },
            calendar: calendar
        )
        writer.refresh()
        writer.recordWeekGoal(kilometers: 30)
        XCTAssertEqual(reloads, 0)
    }

    // MARK: Widget content (PR 4)

    private func snapshot(weekStart: String, km: Double, goalKm: Double?, running: Bool, updated: String) -> RunSmartWidgetSnapshot {
        RunSmartWidgetSnapshot(updatedAt: date(updated), weekStart: date(weekStart), weekDistanceMeters: km * 1_000,
                               weekGoalMeters: goalKm.map { $0 * 1_000 }, isRunInProgress: running)
    }

    func testWidgetShowsRingWithGoal() {
        let content = RunSmartWeeklyWidgetContent.make(
            snapshot: snapshot(weekStart: "2026-11-16T00:00:00Z", km: 21.4, goalKm: 30, running: false, updated: "2026-11-18T08:00:00Z"),
            now: date("2026-11-18T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(content.distanceLabel, "21.4")
        XCTAssertEqual(content.goalLabel, "of 30 km")
        XCTAssertEqual(content.progress ?? 0, 21.4 / 30, accuracy: 0.0001)
        XCTAssertFalse(content.isRunInProgress)
    }

    func testWidgetWithoutGoalHasNoRing() {
        let content = RunSmartWeeklyWidgetContent.make(
            snapshot: snapshot(weekStart: "2026-11-16T00:00:00Z", km: 8.2, goalKm: nil, running: false, updated: "2026-11-18T08:00:00Z"),
            now: date("2026-11-18T09:00:00Z"), calendar: calendar)
        XCTAssertNil(content.progress)
        XCTAssertEqual(content.goalLabel, "km this week")
    }

    func testWidgetResetsInANewWeek() {
        let content = RunSmartWeeklyWidgetContent.make(
            snapshot: snapshot(weekStart: "2026-11-16T00:00:00Z", km: 21.4, goalKm: 30, running: false, updated: "2026-11-22T20:00:00Z"),
            now: date("2026-11-23T07:00:00Z"), calendar: calendar)
        XCTAssertEqual(content.distanceLabel, "0.0")
        XCTAssertNil(content.progress)
        XCTAssertEqual(RunSmartWeeklyWidgetContent.nextRefresh(after: date("2026-11-18T09:00:00Z"), snapshot: nil, calendar: calendar), date("2026-11-23T00:00:00Z"))
    }

    func testWidgetRunFlagExpiresAfterTwelveHours() {
        let fresh = RunSmartWeeklyWidgetContent.make(
            snapshot: snapshot(weekStart: "2026-11-16T00:00:00Z", km: 3, goalKm: 30, running: true, updated: "2026-11-18T08:00:00Z"),
            now: date("2026-11-18T09:00:00Z"), calendar: calendar)
        XCTAssertTrue(fresh.isRunInProgress)
        let old = RunSmartWeeklyWidgetContent.make(
            snapshot: snapshot(weekStart: "2026-11-16T00:00:00Z", km: 3, goalKm: 30, running: true, updated: "2026-11-18T08:00:00Z"),
            now: date("2026-11-18T21:00:00Z"), calendar: calendar)
        XCTAssertFalse(old.isRunInProgress)
    }

    func testLiveRunFlagRefreshesWhenItGoesStaleNotAtWeekEnd() {
        let live = snapshot(weekStart: "2026-11-16T00:00:00Z", km: 3, goalKm: 30, running: true, updated: "2026-11-17T09:00:00Z")
        XCTAssertEqual(RunSmartWeeklyWidgetContent.nextRefresh(after: date("2026-11-17T09:00:05Z"), snapshot: live, calendar: calendar), date("2026-11-17T21:00:00Z"))
        let idle = snapshot(weekStart: "2026-11-16T00:00:00Z", km: 3, goalKm: 30, running: false, updated: "2026-11-17T09:00:00Z")
        XCTAssertEqual(RunSmartWeeklyWidgetContent.nextRefresh(after: date("2026-11-17T09:00:05Z"), snapshot: idle, calendar: calendar), date("2026-11-23T00:00:00Z"))
    }

    func testTimeZoneChangeKeepsTheWeekInsteadOfShowingZero() {
        // Written in Tel Aviv (week starts 2026-11-15T22:00Z), read in London (2026-11-16T00:00Z).
        let content = RunSmartWeeklyWidgetContent.make(
            snapshot: snapshot(weekStart: "2026-11-15T22:00:00Z", km: 21.4, goalKm: 30, running: false, updated: "2026-11-18T08:00:00Z"),
            now: date("2026-11-18T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(content.distanceLabel, "21.4")
        XCTAssertNotNil(content.progress)
    }

    func testWidgetWithoutSnapshotShowsNoNumbers() {
        let content = RunSmartWeeklyWidgetContent.make(snapshot: nil, now: Date(), calendar: calendar)
        XCTAssertFalse(content.hasData)
        XCTAssertNil(content.progress)
    }
}
