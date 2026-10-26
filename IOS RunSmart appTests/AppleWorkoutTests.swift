import XCTest
import WorkoutKit
@testable import IOS_RunSmart_app

final class AppleWorkoutTests: XCTestCase {
    private func workout(id: UUID = UUID(), complete: Bool = false) -> WorkoutSummary {
        WorkoutSummary(id: id, scheduledDate: Date().addingTimeInterval(86400), weekday: "Mon", date: "Tomorrow", kind: .intervals, title: "Intervals", distance: "3 x 400m", detail: "90 s recovery", isToday: false, isComplete: complete, targetPaceSecondsPerKm: 300)
    }

    private func makeActivity() -> RecordedRun {
        let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        return RecordedRun(id: UUID(), source: .healthKit, startedAt: start, endedAt: start.addingTimeInterval(1800), distanceMeters: 5000, movingTimeSeconds: 1800, averagePaceSecondsPerKm: 360, routePoints: [])
    }

    func testIntervalExportKeepsIdentityAndRecoveryOrder() throws {
        let item = workout()
        let plan = try AppleWorkoutFactory.makePlan(for: item)
        XCTAssertEqual(plan.id, item.id)
        guard case .custom(let custom) = plan.workout else { return XCTFail("Expected custom workout") }
        XCTAssertEqual(custom.warmup?.goal, .time(600, .seconds))
        XCTAssertEqual(custom.cooldown?.goal, .time(600, .seconds))
        let steps = try XCTUnwrap(custom.blocks.first?.steps)
        XCTAssertEqual(steps.map(\.purpose), [.work, .recovery, .work, .recovery, .work])
        XCTAssertEqual(steps[0].step.goal, .distance(400, .meters))
        XCTAssertEqual(steps[1].step.goal, .time(90, .seconds))
        let alert = try XCTUnwrap(steps[0].step.alert as? SpeedRangeAlert)
        XCTAssertEqual(alert.target.lowerBound.converted(to: .metersPerSecond).value, 1000 / 305.0, accuracy: 0.001)
        XCTAssertEqual(alert.target.upperBound.converted(to: .metersPerSecond).value, 1000 / 295.0, accuracy: 0.001)
    }

    func testIncompleteOrCompletedWorkoutCannotExport() {
        var item = workout()
        item.detail = "Recover between reps"
        XCTAssertThrowsError(try AppleWorkoutFactory.makePlan(for: item))
        XCTAssertThrowsError(try AppleWorkoutFactory.makePlan(for: workout(complete: true)))
    }

    func testExplicitIdentityDoesNotFallBackToAnotherWorkout() {
        let item = workout()
        var activity = makeActivity()
        activity.plannedWorkoutID = item.id
        XCTAssertEqual(TrainingPlanRepository.bestWorkoutMatch(for: activity, in: [item])?.id, item.id)
        XCTAssertNil(TrainingPlanRepository.bestWorkoutMatch(for: activity, in: [workout()]))
        var completed = item
        completed.isComplete = true
        XCTAssertNil(TrainingPlanRepository.bestWorkoutMatch(for: activity, in: [completed]))
    }

    func testLateImportKeepsEditsAndPreviouslyAvailableData() {
        var stored = makeActivity()
        stored.title = "My run"
        stored.averageHeartRateBPM = 140
        stored.plannedWorkoutID = UUID()
        stored.healthPlanLookupFailed = true
        var incoming = stored
        incoming.title = nil
        incoming.averageHeartRateBPM = nil
        incoming.plannedWorkoutID = nil
        incoming.healthPlanLookupFailed = nil
        let merged = HealthKitImportMerge.merge(incoming, stored: stored)
        XCTAssertEqual(merged.title, "My run")
        XCTAssertEqual(merged.averageHeartRateBPM, 140)
        XCTAssertEqual(merged.plannedWorkoutID, stored.plannedWorkoutID)
        XCTAssertEqual(merged.healthPlanLookupFailed, true)
    }
}

@MainActor
private final class WatchSchedulerSpy: AppleWorkoutScheduling {
    var isSupported = true
    var limit = 2
    var allowed = true
    var confirms = true
    var entries: [ScheduledWorkoutPlan] = []
    var holdAuthorization = false
    var authorizationStarted: (() -> Void)?
    var authorizationContinuation: CheckedContinuation<Bool, Never>?
    var requests = 0
    var writes = 0
    nonisolated deinit {}
    func authorize() async -> Bool {
        requests += 1
        if holdAuthorization {
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                authorizationStarted?()
            }
        }
        return allowed
    }
    func isAuthorized() async -> Bool { allowed }
    func scheduled() async -> [ScheduledWorkoutPlan] { entries }
    func schedule(_ plan: WorkoutPlan, at date: DateComponents) async {
        writes += 1
        if confirms { entries.append(ScheduledWorkoutPlan(plan, date: date)) }
    }
    func remove(_ plan: WorkoutPlan, at date: DateComponents) async {
        entries.removeAll { $0.plan.id == plan.id && $0.date == date }
    }
}

extension AppleWorkoutTests {
    func testRepeatedSendAndEditReplaceOneScheduledItem() async throws {
        let spy = WatchSchedulerSpy()
        let service = AppleWorkoutService(scheduler: spy)
        var item = workout()
        try await service.send(item)
        try await service.send(item)
        XCTAssertEqual(spy.entries.count, 1)
        item.detail = "120 s recovery"
        item.scheduledDate = item.scheduledDate.addingTimeInterval(86400)
        await service.reconcile(workouts: [item])
        XCTAssertEqual(spy.entries.count, 1)
        XCTAssertEqual(spy.entries.first?.plan, try AppleWorkoutFactory.makePlan(for: item))
        XCTAssertEqual(spy.entries.first?.date.day, Calendar.current.component(.day, from: item.scheduledDate))
        XCTAssertEqual(spy.requests, 2, "Reconcile must not prompt")
    }

    func testRegeneratedOrCanceledPlanRemovesOldExportWithoutAddingNewItems() async throws {
        let spy = WatchSchedulerSpy()
        let service = AppleWorkoutService(scheduler: spy)
        try await service.send(workout())
        await service.reconcile(workouts: [workout()])
        XCTAssertTrue(spy.entries.isEmpty)
    }

    func testDenialUnsupportedCapacityAndUnconfirmedScheduling() async throws {
        let spy = WatchSchedulerSpy()
        let service = AppleWorkoutService(scheduler: spy)
        spy.allowed = false
        do { try await service.send(workout()); XCTFail("Expected denied") } catch {}
        XCTAssertEqual(spy.writes, 0)
        spy.allowed = true
        spy.isSupported = false
        do { try await service.send(workout()); XCTFail("Expected unsupported") } catch {}
        XCTAssertEqual(spy.writes, 0)
        spy.isSupported = true
        spy.limit = 0
        do { try await service.send(workout()); XCTFail("Expected capacity limit") } catch {}
        XCTAssertEqual(spy.writes, 0)
        spy.limit = 2
        spy.confirms = false
        do { try await service.send(workout()); XCTFail("Expected unconfirmed") } catch {}
    }

    func testFailedPlanAssociationDefersHeuristicCompletion() {
        var activity = makeActivity()
        activity.healthPlanLookupFailed = true
        var item = workout()
        item.scheduledDate = activity.startedAt
        XCTAssertNil(TrainingPlanRepository.bestWorkoutMatch(for: activity, in: [item]))
    }

    func testConsolidationPreservesIdentityAndDoesNotBridgeDistinctPlans() {
        var a = makeActivity()
        a.plannedWorkoutID = UUID()
        var unlabeled = a
        unlabeled.id = UUID()
        unlabeled.plannedWorkoutID = nil
        unlabeled.source = .runSmart
        var b = a
        b.id = UUID()
        b.plannedWorkoutID = UUID()
        b.startedAt = b.startedAt.addingTimeInterval(1)
        let groups = ActivityConsolidationService.groups(for: [a, unlabeled, b])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(ActivityConsolidationService.canonicalRun(for: b, in: [a, unlabeled, b]).plannedWorkoutID, b.plannedWorkoutID)
        XCTAssertEqual(Set(groups.compactMap { $0.canonicalRun.plannedWorkoutID }), Set([a.plannedWorkoutID!, b.plannedWorkoutID!]))
    }
}

extension AppleWorkoutTests {
    func testMapperCarriesExactIdentityAndLookupFailure() {
        let identity = UUID()
        let snapshot = HealthKitWorkoutSnapshot(uuid: UUID(), startedAt: Date(), endedAt: Date(), duration: 1800,
            distanceMeters: 5000, averageHeartRateBPM: nil, routePoints: [], plannedWorkoutID: identity, planLookupFailed: true)
        let activity = HealthKitRecordedRunMapper.recordedRun(from: snapshot)
        XCTAssertEqual(activity.plannedWorkoutID, identity)
        XCTAssertEqual(activity.healthPlanLookupFailed, true)
    }

    func testLateRouteAndHeartRateEnrichOneStableRun() {
        let stored = makeActivity()
        var incoming = stored
        incoming.averageHeartRateBPM = 150
        incoming.routePoints = [RunRoutePoint(latitude: 32, longitude: 34, timestamp: stored.startedAt, horizontalAccuracy: 5)]
        let merged = HealthKitImportMerge.merge(incoming, stored: stored)
        XCTAssertEqual(merged.id, stored.id)
        XCTAssertEqual(merged.averageHeartRateBPM, 150)
        XCTAssertEqual(merged.routePoints.count, 1)
        let laterPoorRead = HealthKitImportMerge.merge(stored, stored: merged)
        XCTAssertEqual(laterPoorRead.routePoints.count, 1)
        XCTAssertEqual(laterPoorRead.averageHeartRateBPM, 150)
    }

    func testOldStoredRunWithoutNewFieldsStillDecodes() throws {
        let data = try JSONEncoder().encode(makeActivity())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "plannedWorkoutID")
        object.removeValue(forKey: "healthPlanLookupFailed")
        let decoded = try JSONDecoder().decode(RecordedRun.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.plannedWorkoutID)
        XCTAssertNil(decoded.healthPlanLookupFailed)
    }
}

extension AppleWorkoutTests {
    func testRemovalQueuedDuringAuthorizationCannotLeaveStaleExport() async throws {
        let spy = WatchSchedulerSpy()
        spy.holdAuthorization = true
        let authorizing = expectation(description: "Authorizing")
        spy.authorizationStarted = { authorizing.fulfill() }
        let service = AppleWorkoutService(scheduler: spy)
        let item = workout()
        let send = Task { try await service.send(item) }
        await fulfillment(of: [authorizing], timeout: 3)
        let reconciling = expectation(description: "Reconciliation started")
        let removal = Task {
            reconciling.fulfill()
            await service.reconcile(workouts: [])
        }
        await fulfillment(of: [reconciling], timeout: 3)
        spy.authorizationContinuation?.resume(returning: true)
        try await send.value
        await removal.value
        XCTAssertTrue(spy.entries.isEmpty)
    }
}

extension AppleWorkoutTests {
    func testNonGregorianPhoneCalendarSchedulesTheActualGregorianDay() async throws {
        let spy = WatchSchedulerSpy()
        let service = AppleWorkoutService(scheduler: spy)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(secondsFromGMT: 0)!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = buddhist.timeZone
        let item = workout()
        try await service.send(item, calendar: buddhist)
        XCTAssertEqual(spy.entries.first?.date.year, gregorian.component(.year, from: item.scheduledDate))
        XCTAssertEqual(spy.entries.first?.date.month, gregorian.component(.month, from: item.scheduledDate))
        XCTAssertEqual(spy.entries.first?.date.day, gregorian.component(.day, from: item.scheduledDate))
    }
}

extension AppleWorkoutTests {
    func testUnchangedHealthImportDoesNotWriteButStillRetriesExactCompletion() {
        var stored = makeActivity()
        stored.plannedWorkoutID = UUID()
        stored.syncedAt = Date(timeIntervalSince1970: 1000)
        var incoming = stored
        incoming.syncedAt = Date(timeIntervalSince1970: 2000)
        var writes: [RecordedRun] = []
        let batch = HealthKitImportBatch.apply([incoming], existing: [stored], isHidden: { _ in false }, save: { writes.append($0) })
        XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(batch.refreshed.isEmpty)
        XCTAssertTrue(batch.imported.isEmpty)
        XCTAssertEqual(batch.retries.map(\.id), [stored.id])
    }

    func testLateHealthDataWritesOnceThenStopsRefreshing() {
        let stored = makeActivity()
        var late = stored
        late.averageHeartRateBPM = 151
        var writes: [RecordedRun] = []
        let first = HealthKitImportBatch.apply([late], existing: [stored], isHidden: { _ in false }, save: { writes.append($0) })
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(first.refreshed.first?.averageHeartRateBPM, 151)
        let second = HealthKitImportBatch.apply([late], existing: writes, isHidden: { _ in false }, save: { writes.append($0) })
        XCTAssertTrue(second.refreshed.isEmpty)
        XCTAssertEqual(writes.count, 1)
    }

    func testRetryOnlySyncDoesNotUploadRematchOrGenerateReport() async {
        var retry = makeActivity()
        retry.plannedWorkoutID = UUID()
        let result = HealthKitImportResult(status: ConnectedDeviceStatus(provider: "HealthKit", state: .connected, permissions: []), runs: [], skippedDuplicates: 1, completionRetries: [retry])
        var uploads = 0
        var rematches = 0
        var reports = 0
        var completions = 0
        var planNotifications = 0
        let synced = await HealthKitImportProcessor.process(result,
            upload: { _ in uploads += 1; return 0 },
            complete: { _ in completions += 1; return true },
            processNewest: { _ in reports += 1 },
            refreshRuns: { rematches += 1 },
            notifyPlan: { planNotifications += 1 })
        XCTAssertNil(synced)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(planNotifications, 1)
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(rematches, 0)
        XCTAssertEqual(reports, 0)
    }
}

extension AppleWorkoutTests {
    func testHiddenAndUnresolvedHealthRunsDoNotRetryCompletion() {
        var stored = makeActivity()
        stored.plannedWorkoutID = UUID()
        var writes = 0
        let hidden = HealthKitImportBatch.apply([stored], existing: [stored], isHidden: { _ in true }, save: { _ in writes += 1 })
        XCTAssertTrue(hidden.retries.isEmpty)
        var unresolved = stored
        unresolved.healthPlanLookupFailed = true
        let failed = HealthKitImportBatch.apply([unresolved], existing: [stored], isHidden: { _ in false }, save: { _ in writes += 1 })
        XCTAssertTrue(failed.retries.isEmpty)
        XCTAssertEqual(writes, 1, "Persist failed association state, but never complete from it")
    }

    func testFailedRetryOnlySyncHasNoImportOrPlanSideEffects() async {
        var retry = makeActivity()
        retry.plannedWorkoutID = UUID()
        let result = HealthKitImportResult(status: ConnectedDeviceStatus(provider: "HealthKit", state: .connected, permissions: []), runs: [], skippedDuplicates: 1, completionRetries: [retry])
        var sideEffects = 0
        var attempts = 0
        _ = await HealthKitImportProcessor.process(result,
            upload: { _ in sideEffects += 1; return 0 },
            complete: { _ in attempts += 1; return false },
            processNewest: { _ in sideEffects += 1 },
            refreshRuns: { sideEffects += 1 },
            notifyPlan: { sideEffects += 1 })
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(sideEffects, 0)
    }
}

extension AppleWorkoutTests {
    func testUnchangedRawHealthSnapshotKeepsLocalRouteMatchAndConsolidation() {
        var stored = makeActivity()
        stored.consolidatedActivityID = "health-group"
        stored.routeMatchResult = RouteMatchingService.exactMatch(routeID: UUID())
        var raw = stored
        raw.consolidatedActivityID = nil
        raw.routeMatchResult = nil
        var writes = 0
        let batch = HealthKitImportBatch.apply([raw], existing: [stored], isHidden: { _ in false }, save: { _ in writes += 1 })
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(batch.refreshed.isEmpty)
        raw.distanceMeters += 100
        let changed = HealthKitImportMerge.merge(raw, stored: stored)
        XCTAssertNil(changed.routeMatchResult, "Provider geometry/distance changes must be rematched")
        XCTAssertEqual(changed.consolidatedActivityID, stored.consolidatedActivityID)
    }
}

extension AppleWorkoutTests {
    func testFailedUploadRetriesUnchangedHealthRunWithoutRematch() async {
        let raw = makeActivity()
        var saved: [RecordedRun] = []
        let first = HealthKitImportBatch.apply([raw], existing: [], isHidden: { _ in false }, save: { saved.append($0) })
        XCTAssertEqual(first.imported.first?.healthUploadPending, true)
        // A rejected upload leaves the persisted pending flag intact.
        let next = HealthKitImportBatch.apply([raw], existing: saved, isHidden: { _ in false }, save: { _ in XCTFail("Unchanged run must not be saved again") })
        XCTAssertTrue(next.refreshed.isEmpty)
        XCTAssertEqual(next.uploadRetries.map(\.id), [raw.id])
        let result = HealthKitImportResult(status: ConnectedDeviceStatus(provider: "HealthKit", state: .connected, permissions: []), runs: [], skippedDuplicates: 1, uploadRetries: next.uploadRetries)
        var uploaded: [RecordedRun] = []
        let count = await HealthKitImportProcessor.process(result,
            upload: { uploaded = $0; return 1 },
            complete: { _ in XCTFail("No plan identity"); return false },
            processNewest: { _ in XCTFail("No new run") },
            refreshRuns: { XCTFail("Upload-only retry must not rematch") },
            notifyPlan: { XCTFail("No completion") })
        XCTAssertEqual(count, 1)
        XCTAssertEqual(uploaded.map(\.id), [raw.id])
        var confirmed = saved[0]
        confirmed.healthUploadPending = false
        let afterSuccess = HealthKitImportBatch.apply([raw], existing: [confirmed], isHidden: { _ in false }, save: { _ in XCTFail("Confirmed unchanged run") })
        XCTAssertTrue(afterSuccess.uploadRetries.isEmpty)
    }
}

extension AppleWorkoutTests {
    func testOldUploadCannotConfirmNewerProviderDataButAllowsLocalEdits() {
        let uploaded = makeActivity()
        var current = uploaded
        current.notes = "Edited during upload"
        current.routeMatchResult = RouteMatchingService.exactMatch(routeID: UUID())
        XCTAssertTrue(HealthKitImportMerge.uploadConfirms(uploaded, stored: current))
        current.averageHeartRateBPM = 151
        XCTAssertFalse(HealthKitImportMerge.uploadConfirms(uploaded, stored: current))
    }
}

extension AppleWorkoutTests {
    func testPersistedEnrichmentRearmsUploadAndOnlyMatchingConfirmationClearsIt() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: "runsmart.runs")
        defer { defaults.set(previous, forKey: "runsmart.runs") }
        let store = RunSmartLocalStore.shared
        var old = makeActivity()
        old.providerActivityID = UUID().uuidString
        old.healthUploadPending = false
        store.saveRun(old)
        var enriched = old
        enriched.averageHeartRateBPM = 151
        enriched.healthUploadPending = true
        store.stageHealthImport(enriched)
        XCTAssertEqual(store.loadRuns().first { $0.id == old.id }?.healthUploadPending, true)
        store.markRunSynced(old)
        XCTAssertEqual(store.loadRuns().first { $0.id == old.id }?.healthUploadPending, true, "Stale upload must not clear a newer payload")
        store.markRunSynced(enriched)
        XCTAssertEqual(store.loadRuns().first { $0.id == old.id }?.healthUploadPending, false)
        store.saveRunKeepingLocalEdits(enriched) // processNewest may still hold the pre-upload copy.
        XCTAssertEqual(store.loadRuns().first { $0.id == old.id }?.healthUploadPending, false)
    }
}

extension AppleWorkoutTests {
    func testFractionalHealthTimestampsMatchStoredWholeSecondPrecision() throws {
        var stored = makeActivity()
        stored.routePoints = [RunRoutePoint(latitude: 32, longitude: 34, timestamp: stored.startedAt, horizontalAccuracy: 5)]
        stored.routeMatchResult = RouteMatchingService.exactMatch(routeID: UUID())
        var raw = stored
        raw.startedAt = raw.startedAt.addingTimeInterval(0.456)
        raw.endedAt = raw.endedAt.addingTimeInterval(0.789)
        raw.routePoints[0].timestamp = raw.routePoints[0].timestamp.addingTimeInterval(0.123)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(RecordedRun.self, from: encoder.encode(raw))
        raw.routeMatchResult = nil
        let batch = HealthKitImportBatch.apply([raw], existing: [persisted], isHidden: { _ in false }, save: { _ in XCTFail("Timestamp representation is not new data") })
        XCTAssertTrue(batch.refreshed.isEmpty)
        XCTAssertTrue(HealthKitImportMerge.uploadConfirms(raw, stored: persisted))
    }
}
