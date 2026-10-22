import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class WorkoutGuideTests: XCTestCase {
    private func workout(
        kind: WorkoutKind,
        distance: String,
        detail: String = "",
        minutes: Int? = nil,
        pace: Int? = nil,
        structure: String? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(), scheduledDate: Date(), planID: nil, weekday: "Thu", date: "22", kind: kind,
            title: "Test", distance: distance, detail: detail, isToday: true, isComplete: false,
            durationMinutes: minutes, targetPaceSecondsPerKm: pace, intensity: nil, trainingPhase: nil,
            workoutStructure: structure
        )
    }

    private func intervalSteps() throws -> [GuideStep] {
        try XCTUnwrap(StructuredWorkoutFactory.makeGuideSteps(for: workout(
            kind: .intervals, distance: "6 x 400m", detail: "400 m reps with 90 s recovery", pace: 270
        )))
    }

    // MARK: Factory

    func testIntervalWorkoutBuildsRepsWithRecoveries() throws {
        let steps = try intervalSteps()
        XCTAssertEqual(steps.count, 13) // warm up, 6 reps, 5 recoveries, cool down
        XCTAssertEqual(steps.first?.kind, .warmup)
        XCTAssertEqual(steps.last?.kind, .cooldown)
        XCTAssertEqual(steps.filter { $0.kind == .work }.count, 6)
        XCTAssertEqual(steps.filter { $0.kind == .recovery }.count, 5)
        let firstRep = steps[1]
        XCTAssertEqual(firstRep.target, .distance(meters: 400))
        XCTAssertEqual(firstRep.repIndex, 1)
        XCTAssertEqual(firstRep.repTotal, 6)
        XCTAssertEqual(firstRep.paceBand, GuidePaceBand(center: 270))
        XCTAssertEqual(steps[2].kind, .recovery)
        XCTAssertEqual(steps[2].target, .duration(seconds: 90))
        XCTAssertEqual(firstRep.spokenStart, "Rep 1 of 6. 400 metres at 4:25 to 4:35 per kilometre.")
        XCTAssertEqual(steps[2].previewLabel, "90 s recovery")
    }

    func testTempoWorkoutUsesDurationMinusWarmupAndCooldown() throws {
        let steps = try XCTUnwrap(StructuredWorkoutFactory.makeGuideSteps(for: workout(
            kind: .tempo, distance: "8 km", minutes: 40, pace: 300
        )))
        XCTAssertEqual(steps.map(\.kind), [.warmup, .work, .cooldown])
        XCTAssertEqual(steps[0].target, .duration(seconds: 720))
        XCTAssertEqual(steps[1].target, .duration(seconds: 1_200))
        XCTAssertEqual(steps[1].paceBand, GuidePaceBand(center: 300))
        XCTAssertNil(steps[0].paceBand)
        XCTAssertEqual(steps[2].target, .duration(seconds: 480))
    }

    func testEasyRunFallsBackToPlanDistanceWhenNoDuration() throws {
        let steps = try XCTUnwrap(StructuredWorkoutFactory.makeGuideSteps(for: workout(kind: .easy, distance: "5 km")))
        XCTAssertEqual(steps[1].kind, .steady)
        XCTAssertEqual(steps[1].target, .distance(meters: 5_000))
        XCTAssertNil(steps[1].paceBand, "No explicit target pace in the plan, so no band")
    }

    func testPreRunRowsAndGuideComeFromTheSameSteps() throws {
        let plan = workout(kind: .intervals, distance: "6 x 400m", detail: "with 90 s recovery", pace: 270)
        let rows = try XCTUnwrap(StructuredWorkoutFactory.makeSteps(for: plan))
        XCTAssertEqual(rows[1].duration, "6 × 400 m")
        XCTAssertEqual(rows.flatMap(\.guideSteps), try XCTUnwrap(StructuredWorkoutFactory.makeGuideSteps(for: plan)))
    }

    func testJSONStructureBuildsTimedSteps() throws {
        let json = #"{"steps":[{"type":"warmup","duration_seconds":600},{"type":"tempo","duration_seconds":1200,"pace_seconds_per_km":295},{"type":"cooldown","duration_seconds":300}]}"#
        let steps = try XCTUnwrap(StructuredWorkoutFactory.makeGuideSteps(for: workout(kind: .tempo, distance: "8 km", structure: json)))
        XCTAssertEqual(steps.map(\.kind), [.warmup, .work, .cooldown])
        XCTAssertEqual(steps[1].paceBand, GuidePaceBand(center: 295))
    }

    func testNoGuideWhenTheDataHasNoUsableTarget() {
        // Reps with no stated recovery: the plan does not say what to do between them.
        XCTAssertNil(StructuredWorkoutFactory.makeGuideSteps(for: workout(kind: .intervals, distance: "6 x 400m")))
        // Not rep notation.
        XCTAssertNil(StructuredWorkoutFactory.makeGuideSteps(for: workout(kind: .intervals, distance: "6.4 km", detail: "90 s recovery")))
        // Unparseable distance and no duration.
        XCTAssertNil(StructuredWorkoutFactory.makeGuideSteps(for: workout(kind: .easy, distance: "Easy")))
        // Templates with no targets in the data.
        for kind in [WorkoutKind.hills, .race, .recovery, .strength] {
            XCTAssertNil(StructuredWorkoutFactory.makeGuideSteps(for: workout(kind: kind, distance: "5 km", minutes: 40)), "\(kind)")
        }
    }

    func testRecoveryParsing() {
        XCTAssertEqual(StructuredWorkoutFactory.parseRecovery(from: "Jog 200 m between reps"), .distance(meters: 200))
        XCTAssertEqual(StructuredWorkoutFactory.parseRecovery(from: "6 x 400m with 90 s recovery"), .duration(seconds: 90))
        XCTAssertEqual(StructuredWorkoutFactory.parseRecovery(from: "Rest 2 min between reps."), .duration(seconds: 120))
        XCTAssertNil(StructuredWorkoutFactory.parseRecovery(from: "6 x 400m at 5k pace"))
        XCTAssertNil(StructuredWorkoutFactory.parseRecovery(from: "Recover between reps"))
    }

    // MARK: Engine

    func testAdvancesOnDistanceAndOnTime() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: try intervalSteps()))
        _ = guide.update(distance: 0, movingTime: 0)
        XCTAssertEqual(guide.progress?.index, 0)
        XCTAssertEqual(guide.progress?.remainingSeconds, 600)

        _ = guide.update(distance: 1_800, movingTime: 599)
        XCTAssertEqual(guide.progress?.index, 0)
        _ = guide.update(distance: 1_810, movingTime: 600)
        XCTAssertEqual(guide.progress?.index, 1, "Warm up ends on time")
        XCTAssertEqual(guide.progress?.remainingMeters, 400)

        _ = guide.update(distance: 1_810 + 399, movingTime: 690)
        XCTAssertEqual(guide.progress?.index, 1)
        XCTAssertEqual(guide.progress?.remainingMeters, 1)
        _ = guide.update(distance: 1_810 + 401, movingTime: 692)
        XCTAssertEqual(guide.progress?.index, 2, "Rep 1 ends on distance")
        XCTAssertEqual(guide.progress?.step.kind, .recovery)
        XCTAssertEqual(guide.progress?.next?.repIndex, 2)
    }

    func testPausedTimeAndDistanceDoNotAdvanceTheGuide() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: try intervalSteps()))
        _ = guide.update(distance: 1_000, movingTime: 300)
        // The recorder keeps reporting the same moving values while paused or auto-paused.
        for _ in 0..<120 { _ = guide.update(distance: 1_000, movingTime: 300) }
        XCTAssertEqual(guide.progress?.index, 0)
        XCTAssertEqual(guide.progress?.remainingSeconds, 300)
    }

    func testCompletionAndAnnouncements() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [
            GuideStep(kind: .warmup, target: .duration(seconds: 60)),
            GuideStep(kind: .work, target: .distance(meters: 200), paceBand: GuidePaceBand(center: 270), repIndex: 1, repTotal: 1)
        ]))
        XCTAssertEqual(guide.update(distance: 0, movingTime: 1).map(\.text), ["Warm up. 1 minute."])
        XCTAssertEqual(guide.update(distance: 5, movingTime: 2).map(\.text), [], "A step start is announced once")
        XCTAssertEqual(guide.update(distance: 100, movingTime: 61).map(\.text), ["Rep 1 of 1. 200 metres at 4:25 to 4:35 per kilometre."])
        XCTAssertFalse(guide.isFinished)
        XCTAssertEqual(guide.update(distance: 310, movingTime: 100).map(\.text), ["Workout complete."])
        XCTAssertTrue(guide.isFinished)
        XCTAssertNil(guide.progress)
        XCTAssertEqual(guide.update(distance: 500, movingTime: 150).map(\.text), [], "Completion is announced once")
        XCTAssertTrue(guide.isFinished, "Keeps running after completion without restarting")
    }

    func testPaceStatusWithFiveSecondTolerance() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [
            GuideStep(kind: .work, target: .distance(meters: 1_000), paceBand: GuidePaceBand(center: 270))
        ]))
        _ = guide.update(distance: 10, movingTime: 3)
        // Band is 4:25 to 4:35 (265 to 275 s/km); tolerance 5 s/km each side.
        XCTAssertEqual(guide.paceStatus(currentPace: 270), .inRange)
        XCTAssertEqual(guide.paceStatus(currentPace: 280), .inRange)
        XCTAssertEqual(guide.paceStatus(currentPace: 260), .inRange)
        XCTAssertEqual(guide.paceStatus(currentPace: 259), .tooFast)
        XCTAssertEqual(guide.paceStatus(currentPace: 281), .tooSlow)
        XCTAssertNil(guide.paceStatus(currentPace: nil))
        XCTAssertNil(guide.paceStatus(currentPace: 0))
    }

    func testNoPaceStatusWithoutABandOrAfterCompletion() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [GuideStep(kind: .warmup, target: .duration(seconds: 10))]))
        _ = guide.update(distance: 1, movingTime: 1)
        XCTAssertNil(guide.paceStatus(currentPace: 300))
        _ = guide.update(distance: 50, movingTime: 20)
        XCTAssertNil(guide.paceStatus(currentPace: 300))
    }

    func testPaceReminderWaitsForGraceAndSpeaksOncePerMinute() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [
            GuideStep(kind: .work, target: .duration(seconds: 600), paceBand: GuidePaceBand(center: 270))
        ]))
        _ = guide.update(distance: 0, movingTime: 0, currentPace: 400) // step start cue
        XCTAssertTrue(guide.update(distance: 50, movingTime: 10, currentPace: 400).isEmpty, "Inside the grace period")
        XCTAssertEqual(guide.update(distance: 100, movingTime: 20, currentPace: 400).map(\.text), ["Pick it up."])
        XCTAssertTrue(guide.update(distance: 120, movingTime: 50, currentPace: 400).isEmpty)
        XCTAssertTrue(guide.update(distance: 180, movingTime: 79, currentPace: 200).isEmpty, "Under 60 s since the last one")
        XCTAssertEqual(guide.update(distance: 200, movingTime: 80, currentPace: 200).map(\.text), ["Ease off."])
        XCTAssertTrue(guide.update(distance: 300, movingTime: 140, currentPace: 270).isEmpty, "In range stays quiet")
        XCTAssertTrue(guide.update(distance: 300, movingTime: 141, currentPace: nil).isEmpty, "Unknown pace stays quiet")
    }

    func testPaceRemindersOnlyDuringWorkSteps() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [
            GuideStep(kind: .steady, target: .duration(seconds: 600), paceBand: GuidePaceBand(center: 360))
        ]))
        _ = guide.update(distance: 0, movingTime: 0)
        XCTAssertTrue(guide.update(distance: 100, movingTime: 60, currentPace: 200).isEmpty)
    }

    func testGuideSurvivesCodableRoundTripAndCatchesUp() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: try intervalSteps()))
        _ = guide.update(distance: 1_800, movingTime: 600)
        _ = guide.update(distance: 1_900, movingTime: 640)
        let restored = try JSONDecoder().decode(WorkoutGuide.self, from: JSONEncoder().encode(guide))
        XCTAssertEqual(restored, guide)

        var resumed = restored
        let cues = resumed.update(distance: 1_800 + 400 + 20, movingTime: 700)
        XCTAssertEqual(resumed.progress?.step.kind, .recovery, "Catches up from the recovered totals")
        XCTAssertEqual(cues.map(\.text), ["Recovery. 90 seconds."])
    }

    func testCheckpointWithAndWithoutGuideDecodes() throws {
        let guide = try XCTUnwrap(WorkoutGuide(steps: try intervalSteps()))
        let now = Date()
        var checkpoint = RunSessionCheckpoint(
            startedAt: now.addingTimeInterval(-100), accumulatedPausedSeconds: 0, pausedAt: nil, wasPaused: false,
            routePoints: [], distanceMeters: 100, workoutTitle: "Intervals", savedAt: now
        )
        checkpoint.workoutGuide = guide
        let decoded = try JSONDecoder().decode(RunSessionCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(decoded.workoutGuide, guide)

        checkpoint.workoutGuide = nil
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any])
        object.removeValue(forKey: "workoutGuide")
        let old = try JSONDecoder().decode(RunSessionCheckpoint.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.workoutGuide)
    }

    // MARK: Cue text and live display

    func testStepCueIsCombinedWithSplitCueInOneUtterance() {
        let step = WorkoutGuide.Announcement(text: "Rep 3 of 6. 400 metres.", isReminder: false)
        let reminder = WorkoutGuide.Announcement(text: "Ease off.", isReminder: true)
        XCTAssertEqual(
            LocalRunCueService.combinedText(split: "1 kilometer.", guide: [step]),
            "1 kilometer. Rep 3 of 6. 400 metres."
        )
        XCTAssertEqual(LocalRunCueService.combinedText(split: nil, guide: [step]), "Rep 3 of 6. 400 metres.")
        XCTAssertEqual(LocalRunCueService.combinedText(split: "1 kilometer.", guide: [reminder]), "1 kilometer.")
        XCTAssertEqual(LocalRunCueService.combinedText(split: nil, guide: [reminder]), "Ease off.")
        XCTAssertNil(LocalRunCueService.combinedText(split: nil, guide: []))
    }

    func testRemainingAndSpokenFormats() {
        XCTAssertEqual(WorkoutGuideFormat.remaining(meters: 400, seconds: nil), "400 m left")
        XCTAssertEqual(WorkoutGuideFormat.remaining(meters: 399.2, seconds: nil), "400 m left")
        XCTAssertEqual(WorkoutGuideFormat.remaining(meters: nil, seconds: 90), "1:30 left")
        XCTAssertEqual(WorkoutGuideFormat.remaining(meters: 1_250, seconds: nil), "1.2 km left")
        XCTAssertEqual(WorkoutGuideFormat.spokenTarget(.duration(seconds: 90)), "90 seconds")
        XCTAssertEqual(WorkoutGuideFormat.spokenTarget(.duration(seconds: 600)), "10 minutes")
        XCTAssertEqual(WorkoutGuideFormat.spokenTarget(.duration(seconds: 150)), "2 minutes 30 seconds")
        XCTAssertEqual(WorkoutGuideFormat.spokenTarget(.distance(meters: 1_500)), "1.5 kilometres")
        XCTAssertEqual(WorkoutGuideFormat.shortTarget(.duration(seconds: 600)), "10 min")
    }

    func testEmptyOrOversizedStepListsMakeNoGuide() {
        XCTAssertNil(WorkoutGuide(steps: []))
    }
}
