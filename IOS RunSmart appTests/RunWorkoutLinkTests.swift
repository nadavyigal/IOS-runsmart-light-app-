import XCTest
@testable import IOS_RunSmart_app

/// Story 0.2: a run links to at most one workout and a workout to at most one run.
final class RunWorkoutLinkTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ value: String, hour: Double = 7) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: value)!.addingTimeInterval(hour * 3600)
    }

    private func workout(
        _ id: String,
        day: String = "2026-11-10",
        distance: String = "5.0 km",
        minutes: Int? = nil,
        complete: Bool = false
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(uuidString: id)!, scheduledDate: date(day, hour: 0), planID: nil, weekday: "", date: "",
            kind: .easy, title: "Easy Run", distance: distance, detail: "", isToday: false, isComplete: complete,
            durationMinutes: minutes, targetPaceSecondsPerKm: nil, intensity: nil, trainingPhase: nil, workoutStructure: nil
        )
    }

    private func run(
        _ providerID: String,
        day: String = "2026-11-10",
        hour: Double = 7,
        km: Double,
        source: RunSmartDataSource = .garmin,
        pinnedTo planned: String? = nil
    ) -> RecordedRun {
        let started = date(day, hour: hour)
        let seconds = km * 330
        var run = RecordedRun(
            id: UUID(), providerActivityID: providerID, source: source,
            startedAt: started, endedAt: started.addingTimeInterval(seconds),
            distanceMeters: km * 1_000, movingTimeSeconds: seconds, averagePaceSecondsPerKm: 330,
            averageHeartRateBPM: nil, routePoints: [], syncedAt: Date()
        )
        run.plannedWorkoutID = planned.flatMap(UUID.init(uuidString:))
        return run
    }

    private let idA = "AAAAAAAA-0000-0000-0000-000000000001"
    private let idB = "AAAAAAAA-0000-0000-0000-000000000002"

    // MARK: matching

    func testPinnedIdMatchesItsWorkoutEvenOnAnotherDay() {
        let target = workout(idA, day: "2026-11-12", distance: "10.0 km")
        let pinned = run("p1", km: 3, pinnedTo: idA)

        let pairs = TrainingPlanRepository.assignRuns([pinned], to: [workout(idB), target], calendar: calendar)

        XCTAssertEqual(pairs.map { $0.1.id }, [target.id])
    }

    func testPinnedIdThatIsMissingOrCompletedNeverFallsBackToAnotherWorkout() {
        let sameDay = workout(idB)
        let pinned = run("p1", km: 5, pinnedTo: idA)
        XCTAssertTrue(TrainingPlanRepository.assignRuns([pinned], to: [sameDay], calendar: calendar).isEmpty)

        let completed = workout(idA, complete: true)
        XCTAssertTrue(TrainingPlanRepository.assignRuns([pinned], to: [completed, sameDay], calendar: calendar).isEmpty)
    }

    func testHeuristicMatchesSameDayWithinThresholds() {
        let planned = workout(idA, distance: "8.0 km", minutes: 45)
        let matching = run("h1", km: 8.1)
        let tooFar = run("h2", km: 12)

        XCTAssertEqual(TrainingPlanRepository.assignRuns([matching], to: [planned], calendar: calendar).first?.1.id, planned.id)
        XCTAssertTrue(TrainingPlanRepository.assignRuns([tooFar], to: [planned], calendar: calendar).isEmpty)
    }

    func testAssignmentAgreesWithBestWorkoutMatchForOneRun() {
        let near = workout(idA, distance: "5.0 km")
        let far = workout(idB, distance: "6.5 km")
        let candidate = run("h1", km: 5.2)

        let single = TrainingPlanRepository.bestWorkoutMatch(for: candidate, in: [far, near], calendar: calendar)
        let assigned = TrainingPlanRepository.assignRuns([candidate], to: [far, near], calendar: calendar)

        XCTAssertEqual(single?.id, near.id)
        XCTAssertEqual(assigned.first?.1.id, single?.id)
    }

    func testTwoRunsOneWorkoutBetterDistanceWinsAndOtherStaysUnlinked() {
        let planned = workout(idA, distance: "8.0 km")
        let close = run("close", hour: 18, km: 8.1)
        let loose = run("loose", hour: 7, km: 6.8)

        for runs in [[loose, close], [close, loose]] {
            let pairs = TrainingPlanRepository.assignRuns(runs, to: [planned], calendar: calendar)
            XCTAssertEqual(pairs.count, 1)
            XCTAssertEqual(pairs.first?.0.providerActivityID, "close")
        }
    }

    func testTwoRunsTwoWorkoutsEachLinkOnce() {
        let short = workout(idA, distance: "5.0 km")
        let long = workout(idB, distance: "10.0 km")
        let morning = run("morning", hour: 7, km: 10.2)
        let evening = run("evening", hour: 18, km: 5.1)

        let pairs = TrainingPlanRepository.assignRuns([morning, evening], to: [short, long], calendar: calendar)

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(Set(pairs.map { $0.0.providerActivityID! }).count, 2)
        XCTAssertEqual(Set(pairs.map { $0.1.id }).count, 2)
        XCTAssertEqual(pairs.first { $0.0.providerActivityID == "morning" }?.1.id, long.id)
        XCTAssertEqual(pairs.first { $0.0.providerActivityID == "evening" }?.1.id, short.id)
    }

    func testNoMatchKeepsRunUnlinkedAndNothingIsApplied() async {
        let defaults = freshDefaults()
        let userID = UUID()
        var applied = 0

        let report = await RunWorkoutBackfill.runOnce(
            userID: userID, defaults: defaults, dryRun: false, calendar: calendar,
            loadRuns: { [self.run("extra", day: "2026-11-11", km: 5)] },
            loadWorkouts: { [self.workout(self.idA, day: "2026-11-10")] },
            apply: { _, _ in applied += 1; return true }
        )

        XCTAssertEqual(report, RunWorkoutBackfillReport(candidateRuns: 1, matched: 0, unmatched: 1, applied: 0, dryRun: false))
        XCTAssertEqual(applied, 0)
        XCTAssertTrue(RunWorkoutLinkOutbox(defaults: defaults, key: "links").pending().isEmpty, "a miss is never queued")
    }

    func testAlreadyCompletedWorkoutIsNotRelinked() {
        let taken = workout(idA, distance: "5.0 km", complete: true)
        let lateRun = run("late", hour: 19, km: 5)

        XCTAssertTrue(TrainingPlanRepository.assignRuns([lateRun], to: [taken], calendar: calendar).isEmpty)
        XCTAssertNil(TrainingPlanRepository.bestWorkoutMatch(for: lateRun, in: [taken], calendar: calendar))
    }

    func testWorkoutTakenByAnotherRunDropsTheQueuedLink() async {
        let outbox = freshOutbox()
        let record = enqueue(outbox, run("late", km: 5))

        let completed = await outbox.retryPending(authUserID: record.authUserID) { _ in .notAvailable }

        XCTAssertEqual(completed, [])
        XCTAssertTrue(outbox.pending().isEmpty)
    }

    // MARK: backfill

    func testBackfillRunsOnceAndSecondRunChangesNothing() async {
        let defaults = freshDefaults()
        let userID = UUID()
        var workouts = [workout(idA, distance: "8.0 km")]
        var runs = [run("r1", km: 8.1)]
        var applyCalls = 0

        func pass() async -> RunWorkoutBackfillReport? {
            await RunWorkoutBackfill.runOnce(
                userID: userID, defaults: defaults, dryRun: false, calendar: calendar,
                loadRuns: { runs }, loadWorkouts: { workouts },
                apply: { run, planned in
                    applyCalls += 1
                    // What the server state would now say: workout complete, run linked.
                    workouts = workouts.map { var w = $0; if w.id == planned.id { w.isComplete = true }; return w }
                    runs.removeAll { $0.providerActivityID == run.providerActivityID }
                    return true
                }
            )
        }

        let first = await pass()
        let second = await pass()

        XCTAssertEqual(first?.applied, 1)
        XCTAssertNil(second, "the per-install flag skips the second pass")
        XCTAssertEqual(applyCalls, 1)
        XCTAssertTrue(defaults.bool(forKey: RunWorkoutBackfill.flagKey(for: userID)))

        // Even with the flag cleared, linked runs and completed workouts leave nothing to do.
        defaults.removeObject(forKey: RunWorkoutBackfill.flagKey(for: userID))
        let third = await pass()
        XCTAssertEqual(third?.matched, 0)
        XCTAssertEqual(applyCalls, 1)
    }

    func testUpgradeRecoversAnEstablishedLegacyLinkBeforeCompetingMatches() async throws {
        let defaults = freshDefaults()
        let userID = UUID()
        defaults.set(true, forKey: "runsmart.runs.workoutLinkBackfill.v2.\(userID.uuidString)")
        let planned = workout(idA)
        let unrelated = workout(idB)
        let linked = run("legacy-garmin", day: "2026-08-01", km: 7.2, pinnedTo: idB)
        let competing = run("later-candidate", km: 5, pinnedTo: idA)
        var written: [String] = []
        let report = await RunWorkoutBackfill.runOnce(
            userID: userID, defaults: defaults, dryRun: false, calendar: calendar,
            loadRuns: { [competing] },
            loadWorkouts: { [planned, unrelated] },
            loadLinkedRuns: { incomplete in
                XCTAssertEqual(Set(incomplete.map(\.id)), Set([planned.id, unrelated.id]))
                return [RunWorkoutBackfillIncumbent(workoutID: planned.id, run: linked)]
            },
            apply: { source, target in
                written.append(source.providerActivityID ?? "")
                XCTAssertEqual(target.id, planned.id, "The persisted association outranks both pins")
                XCTAssertEqual(DBWorkoutCompletionUpdate(run: source).actualDistanceKm, 7.2)
                return true
            }
        )
        XCTAssertEqual(report, RunWorkoutBackfillReport(candidateRuns: 2, matched: 1, unmatched: 1, applied: 1, dryRun: false))
        XCTAssertEqual(written, ["legacy-garmin"])
        XCTAssertTrue(defaults.bool(forKey: RunWorkoutBackfill.flagKey(for: userID)))
    }

    func testUpgradeReadsActualsFromTheExactLinkedServerRunWithoutALocalCopy() throws {
        let json = """
        {"workout_id":"\(idA)","source_provider":"runsmart_ios","source_activity_id":"previous-run",
         "completed_at":"2026-08-01T07:00:00Z","distance":6.25,"duration":1919,"pace":307,"heart_rate":146}
        """
        let row = try JSONDecoder().decode(DBRunBackfillRow.self, from: Data(json.utf8))
        let incumbent = try XCTUnwrap(DBRunBackfillRow.incumbents(from: [row], localRuns: [], isHidden: { _ in false }).first)
        let activity = try XCTUnwrap(incumbent.run)
        XCTAssertEqual(incumbent.workoutID, UUID(uuidString: idA))
        XCTAssertEqual(activity.runSourceKey, RunSourceKey(sourceProvider: "runsmart_ios", sourceActivityID: "previous-run"))
        XCTAssertEqual(DBWorkoutCompletionUpdate(run: activity).actualDistanceKm, 6.25)
        XCTAssertEqual(DBWorkoutCompletionUpdate(run: activity).actualDurationMinutes, 32)
        XCTAssertEqual(DBWorkoutCompletionUpdate(run: activity).actualPace, 307)

        let hidden = try XCTUnwrap(DBRunBackfillRow.incumbents(from: [row], localRuns: [], isHidden: { _ in true }).first)
        XCTAssertEqual(hidden.workoutID, incumbent.workoutID)
        XCTAssertNil(hidden.run)
    }

    func testUpgradeLeavesAnUnusableIncumbentReservedAndRetriesAFailedRead() async {
        let defaults = freshDefaults()
        let userID = UUID()
        let planned = workout(idA)
        let competing = run("competing", km: 5, pinnedTo: idA)

        let failed = await RunWorkoutBackfill.runOnce(
            userID: userID, defaults: defaults, dryRun: false,
            loadRuns: { [competing] }, loadWorkouts: { [planned] }, loadLinkedRuns: { _ in nil },
            apply: { _, _ in XCTFail("No write is safe before reading incumbent links"); return false }
        )
        XCTAssertNil(failed)
        XCTAssertFalse(defaults.bool(forKey: RunWorkoutBackfill.flagKey(for: userID)))

        let repaired = await RunWorkoutBackfill.runOnce(
            userID: userID, defaults: defaults, dryRun: false,
            loadRuns: { [competing] }, loadWorkouts: { [planned] },
            loadLinkedRuns: { _ in [RunWorkoutBackfillIncumbent(workoutID: planned.id, run: nil)] },
            apply: { _, _ in XCTFail("A hidden or invalid incumbent still reserves its workout"); return false }
        )
        XCTAssertEqual(repaired?.matched, 0)
    }

    func testDryRunLogsCountsWritesNothingAndLeavesTheFlagUnset() async {
        let defaults = freshDefaults()
        let userID = UUID()
        var applied = 0

        let report = await RunWorkoutBackfill.runOnce(
            userID: userID, defaults: defaults, dryRun: true, calendar: calendar,
            loadRuns: { [self.run("r1", km: 5), self.run("r2", day: "2026-11-01", km: 5)] },
            loadWorkouts: { [self.workout(self.idA)] },
            apply: { _, _ in applied += 1; return true }
        )

        XCTAssertEqual(report, RunWorkoutBackfillReport(candidateRuns: 2, matched: 1, unmatched: 1, applied: 0, dryRun: true))
        XCTAssertEqual(applied, 0)
        XCTAssertFalse(defaults.bool(forKey: RunWorkoutBackfill.flagKey(for: userID)))
    }

    func testBackfillStaysPendingWhenDataCannotBeLoaded() async {
        let defaults = freshDefaults()
        let userID = UUID()

        let report = await RunWorkoutBackfill.runOnce(
            userID: userID, defaults: defaults, dryRun: false, calendar: calendar,
            loadRuns: { nil }, loadWorkouts: { [] }, apply: { _, _ in true }
        )

        XCTAssertNil(report)
        XCTAssertFalse(defaults.bool(forKey: RunWorkoutBackfill.flagKey(for: userID)))
    }

    // MARK: link outbox and keys

    func testRunSourceKeyMatchesTheKeyDBRunInsertUpsertsOn() throws {
        let identity = RunSmartIdentity(authUserID: UUID(), profileUUID: nil, numericUserID: 7)
        for source in [RunSmartDataSource.garmin, .healthKit, .runSmart] {
            for providerID in ["abc-123", nil] {
                let candidate = run(providerID ?? "unused", km: 5, source: source)
                var recorded = candidate
                recorded.providerActivityID = providerID
                let data = try JSONEncoder().encode(DBRunInsert(run: recorded, identity: identity, kind: .easy, notes: nil))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

                XCTAssertEqual(json["source_provider"] as? String, recorded.runSourceKey.sourceProvider)
                XCTAssertEqual(json["source_activity_id"] as? String, recorded.runSourceKey.sourceActivityID)
            }
        }
    }

    func testRunNotSyncedKeepsTheCompletionWithoutCountingAnAttemptUntilItExpires() async {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let outbox = RunWorkoutLinkOutbox(defaults: freshDefaults(), key: "links", now: { clock })
        let activity = run("waiting", km: 5)
        let record = enqueue(outbox, activity)

        for _ in 0..<(RunWorkoutLinkOutbox.maxAttempts + 2) {
            _ = await outbox.retryPending(authUserID: record.authUserID) { _ in .runNotSynced }
        }
        XCTAssertEqual(outbox.pending(), [record])

        clock = clock.addingTimeInterval(RunWorkoutLinkOutbox.maxAge + 1)
        _ = await outbox.retryPending(authUserID: record.authUserID) { _ in
            XCTFail("Expired match must not be submitted")
            return .completed
        }
        XCTAssertTrue(outbox.pending().isEmpty)
    }

    func testThrownCompletionWritesAreDroppedAfterMaxAttempts() async {
        let outbox = freshOutbox()
        let record = enqueue(outbox, run("offline", km: 5))

        for _ in 0..<RunWorkoutLinkOutbox.maxAttempts {
            _ = await outbox.retryPending(authUserID: record.authUserID) { _ in throw URLError(.notConnectedToInternet) }
        }

        XCTAssertTrue(outbox.pending().isEmpty)
    }

    func testRetryRestoresExactMatchAndPayloadAndOnlyRunsForItsOwner() async {
        let defaults = freshDefaults()
        let outbox = RunWorkoutLinkOutbox(defaults: defaults, key: "links")
        let activity = run("from-health", km: 5.1, source: .healthKit)
        let record = enqueue(outbox, activity)
        let result = await outbox.attempt(record) { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertNil(result)
        let restored = RunWorkoutLinkOutbox(defaults: defaults, key: "links")
        XCTAssertEqual(restored.pending().first?.attemptCount, 1)
        let other = await restored.retryPending(authUserID: UUID()) { _ in
            XCTFail("Other user must not submit this record")
            return .completed
        }
        XCTAssertEqual(other, [])
        XCTAssertEqual(restored.pending().count, 1)

        let completed = await restored.retryPending(authUserID: record.authUserID) { sent in
            XCTAssertEqual(sent.id, record.id)
            XCTAssertEqual(sent.key, activity.runSourceKey)
            XCTAssertEqual(sent.workoutID, record.workoutID)
            XCTAssertEqual(sent.payload, DBWorkoutCompletionUpdate(run: activity))
            return .alreadyCompleted
        }
        XCTAssertEqual(completed, [record.workoutID])
        XCTAssertTrue(restored.pending().isEmpty)
    }

    func testRetryRestoresMissingRunBeforeResubmittingTheSameMatch() async {
        let outbox = freshOutbox()
        let record = enqueue(outbox, run("needs-upload", km: 5))
        var calls: [String] = []
        let completed = await outbox.retryPending(authUserID: record.authUserID, restoreRun: { key in
            XCTAssertEqual(key, record.key)
            calls.append("restore")
            return true
        }, send: { sent in
            XCTAssertEqual(sent, record)
            calls.append("send")
            return calls.count == 1 ? .runNotSynced : .completed
        })
        XCTAssertEqual(calls, ["send", "restore", "send"])
        XCTAssertEqual(completed, [record.workoutID])
        XCTAssertTrue(outbox.pending().isEmpty)
    }

    func testHiddenRunIsRemovedFromRetryEvenWithoutALocalCopy() async {
        let activity = run("hidden", km: 5, source: .healthKit)
        let outbox = freshOutbox()
        let record = enqueue(outbox, activity)
        let completed = await outbox.retryPending(authUserID: record.authUserID, isHidden: { $0 == record.key }) { _ in
            XCTFail("A hidden run must not claim a workout from a previously synced row")
            return .completed
        }
        XCTAssertEqual(completed, [])
        XCTAssertTrue(outbox.pending().isEmpty)
    }

    func testRPCParametersPairRunIdentityWithActuals() throws {
        let activity = run("paired", km: 5.06)
        let record = enqueue(freshOutbox(), activity)
        let data = try JSONEncoder().encode(CompleteRunWorkoutParams(record: record))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["p_expected_athlete"] as? String, record.authUserID.uuidString)
        XCTAssertEqual(json["p_workout_id"] as? String, record.workoutID.uuidString)
        XCTAssertEqual(json["p_source_provider"] as? String, record.key.sourceProvider)
        XCTAssertEqual(json["p_source_activity_id"] as? String, record.key.sourceActivityID)
        XCTAssertEqual(json["p_actual_pace"] as? Int, 330)
        XCTAssertEqual(json["p_actual_distance_km"] as? Double, 5.06)
    }

    func testBackfillRowRebuildsRunAndPrefersTheDeviceCopyForItsPinnedId() throws {
        let json = #"{"source_provider":"garmin","source_activity_id":"g-1","completed_at":"2026-11-10T07:00:00+00:00","distance":8.1,"duration":2700,"heart_rate":150}"#
        let row = try JSONDecoder().decode(DBRunBackfillRow.self, from: Data(json.utf8))

        let rebuilt = try XCTUnwrap(row.recordedRun(local: nil))
        XCTAssertEqual(rebuilt.source, .garmin)
        XCTAssertEqual(rebuilt.distanceMeters, 8_100, accuracy: 0.1)
        XCTAssertEqual(rebuilt.startedAt, date("2026-11-10"))

        var local = run("g-1", km: 8.1, pinnedTo: idA)
        local.source = .garmin
        XCTAssertEqual(row.recordedRun(local: local)?.plannedWorkoutID, UUID(uuidString: idA))

        let strava = #"{"source_provider":"strava","source_activity_id":"s-1","completed_at":"2026-11-10T07:00:00+00:00","distance":5,"duration":1500,"heart_rate":null}"#
        let other = try JSONDecoder().decode(DBRunBackfillRow.self, from: Data(strava.utf8))
        XCTAssertNil(other.recordedRun(local: nil))
    }

    // MARK: review fixes

    func testOverlappingRetriesRunOnePassAndSendOncePerRecord() async {
        let outbox = freshOutbox()
        let record = enqueue(outbox, run("x", km: 5))
        let sends = SendCounter()

        async let first = outbox.retryPending(authUserID: record.authUserID) { _ in
            await sends.increment()
            try? await Task.sleep(nanoseconds: 300_000_000)
            return .completed
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let second = await outbox.retryPending(authUserID: record.authUserID) { _ in
            await sends.increment()
            return .completed
        }
        let completed = await first
        XCTAssertEqual(second, [])
        XCTAssertEqual(completed, [record.workoutID])
        let count = await sends.value
        XCTAssertEqual(count, 1)
        XCTAssertTrue(outbox.pending().isEmpty)
    }

    func testOldFailureDoesNotModifyANewerPendingRecord() {
        let outbox = freshOutbox()
        let activity = run("x", km: 5)
        let record = enqueue(outbox, activity)
        outbox.remove(record)
        let newer = enqueue(outbox, activity, userID: record.authUserID)

        outbox.recordFailure(record)

        XCTAssertNotEqual(record.id, newer.id)
        XCTAssertEqual(outbox.pending(), [newer])
    }

    func testNewHealthBatchRanksBeforeNewestReportInEitherArrivalOrder() async throws {
        let best = run("early-nearest", hour: 7, km: 5.1, source: .healthKit)
        let newest = run("late-farther", hour: 14, km: 5.9, source: .healthKit)
        let planned = workout(idA)
        for imports in [[best, newest], [newest, best]] {
            var winningRun: String?
            var reportedRun: String?
            let batch = HealthKitImportResult(
                status: ConnectedDeviceStatus(provider: "HealthKit", state: .connected, permissions: []),
                runs: imports, skippedDuplicates: 0
            )
            _ = await HealthKitImportProcessor.process(batch,
                upload: { $0.count },
                complete: { _ in XCTFail("New runs must compete as a batch"); return false },
                completeNewRuns: { runs in
                    let pairs = TrainingPlanRepository.assignRuns(runs, to: [planned], calendar: self.calendar)
                    winningRun = pairs.first?.0.providerActivityID
                    return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.runSourceKey, $0.1) })
                },
                processNewest: { activity, workout in
                    reportedRun = activity.providerActivityID
                    XCTAssertNil(workout, "The newest run must not rematch the reserved workout")
                },
                refreshRuns: {}, notifyPlan: {})
            XCTAssertEqual(winningRun, best.providerActivityID)
            XCTAssertEqual(reportedRun, newest.providerActivityID)
        }
    }

    func testBackfillSkipsHiddenRunsWithOrWithoutALocalCopy() throws {
        func row(_ id: String, provider: String = "garmin") throws -> DBRunBackfillRow {
            let json = #"{"source_provider":"\#(provider)","source_activity_id":"\#(id)","completed_at":"2026-11-10T07:00:00+00:00","distance":5,"duration":1500,"heart_rate":null}"#
            return try JSONDecoder().decode(DBRunBackfillRow.self, from: Data(json.utf8))
        }
        // Mirrors RunSmartLocalStore's hidden key: "<source>|<provider activity id>".
        let hiddenKeys: Set<String> = ["Garmin|hidden-no-copy", "Garmin|hidden-with-copy"]
        let isHidden: (RecordedRun) -> Bool = { hiddenKeys.contains("\($0.source.rawValue)|\($0.providerActivityID ?? $0.id.uuidString)") }
        let localCopy = run("hidden-with-copy", km: 5)

        let runs = DBRunBackfillRow.matchableRuns(
            from: [try row("visible"), try row("hidden-no-copy"), try row("hidden-with-copy")],
            localRuns: [localCopy],
            isHidden: isHidden
        )

        XCTAssertEqual(runs.map(\.providerActivityID), ["visible"])
    }

    // MARK: helpers

    private actor SendCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }


    private func freshDefaults() -> UserDefaults {
        let name = "run-workout-link-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func enqueue(_ outbox: RunWorkoutLinkOutbox, _ activity: RecordedRun, userID: UUID = UUID()) -> PendingRunLink {
        outbox.enqueue(authUserID: userID, key: activity.runSourceKey, workoutID: UUID(), payload: DBWorkoutCompletionUpdate(run: activity))
    }

    private func freshOutbox() -> RunWorkoutLinkOutbox {
        RunWorkoutLinkOutbox(defaults: freshDefaults(), key: "links")
    }
}
