import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

final class RunSmartReadinessTests: XCTestCase {
    private func encodedProfileID(_ reference: DBProfileReference) throws -> Any? {
        let data = try JSONEncoder().encode(["profile_id": reference])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["profile_id"]
    }

    func testDBProfileReferenceEncodesNumericUUIDAndStringValues() throws {
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        XCTAssertEqual(try encodedProfileID(.numeric(42)) as? Int, 42)
        XCTAssertEqual(try encodedProfileID(.uuid(uuid)) as? String, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(try encodedProfileID(.string("abc")) as? String, "abc")
    }

    func testDBProfileReferenceDebugValuesDescribeReferenceType() {
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        XCTAssertEqual(DBProfileReference.numeric(42).debugValue, "numeric:42")
        XCTAssertEqual(DBProfileReference.uuid(uuid).debugValue, "uuid:00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(DBProfileReference.string("abc").debugValue, "string:abc")
    }

    private func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter.shortDate.date(from: value)!
    }

    private func makeWorkout(
        id: UUID = UUID(),
        date: String,
        kind: WorkoutKind = .easy,
        title: String = "Easy Run",
        distance: String = "5.0 km",
        durationMinutes: Int? = nil,
        pace: Int? = nil,
        intensity: String? = nil
    ) -> WorkoutSummary {
        let scheduledDate = makeDate(date)
        return WorkoutSummary(
            id: id,
            scheduledDate: scheduledDate,
            planID: nil,
            weekday: "",
            date: "",
            kind: kind,
            title: title,
            distance: distance,
            detail: "",
            isToday: false,
            isComplete: false,
            durationMinutes: durationMinutes,
            targetPaceSecondsPerKm: pace,
            intensity: intensity,
            trainingPhase: nil,
            workoutStructure: nil
        )
    }

    private func makeRun(
        id: UUID = UUID(),
        providerActivityID: String? = nil,
        source: RunSmartDataSource,
        startedAt: Date,
        distanceMeters: Double,
        movingTimeSeconds: TimeInterval,
        heartRate: Int? = nil,
        routePoints: [RunRoutePoint] = []
    ) -> RecordedRun {
        RecordedRun(
            id: id,
            providerActivityID: providerActivityID,
            source: source,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(movingTimeSeconds),
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingTimeSeconds,
            averagePaceSecondsPerKm: movingTimeSeconds / max(distanceMeters / 1_000, 0.1),
            averageHeartRateBPM: heartRate,
            routePoints: routePoints,
            syncedAt: Date(timeIntervalSince1970: 30_000)
        )
    }

    private func makeLocation(latitude: Double, longitude: Double, accuracy: CLLocationAccuracy, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    func testPlanWeeksGroupByCalendarWeekAndTotalDistance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let workouts = [
            makeWorkout(date: "2026-04-27", distance: "5.5 km"),
            makeWorkout(date: "2026-05-02", kind: .long, title: "Long Run", distance: "10km"),
            makeWorkout(date: "2026-05-04", distance: "8km"),
            makeWorkout(date: "2026-05-06", kind: .tempo, title: "Tempo", distance: "6.6 km"),
            makeWorkout(date: "2026-05-07", kind: .recovery, title: "Recovery", distance: "Rest")
        ]

        let weeks = PlanPresentationModels.makeWeeks(
            displayedMonth: makeDate("2026-05-05"),
            workouts: workouts,
            now: makeDate("2026-05-05"),
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].dateRangeLabel, "APR 26 - MAY 2")
        XCTAssertEqual(weeks[0].totalWorkouts, 2)
        XCTAssertEqual(weeks[0].totalDistanceLabel, "15.50km")
        XCTAssertTrue(weeks[1].isCurrentWeek)
        XCTAssertEqual(weeks[1].totalWorkouts, 2)
        XCTAssertEqual(weeks[1].totalDistanceLabel, "14.60km")
    }

    func testTodayWorkoutDisplayFallsBackToLaunchFriendlyLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let recommendation = TodayRecommendation(
            readiness: 82,
            readinessLabel: "Ready",
            workoutTitle: "Tempo Builder",
            distance: "8.0 km",
            pace: "GPS guided",
            elevation: "Route based",
            coachMessage: "Go steady."
        )
        let workout = makeWorkout(
            date: "2026-05-05",
            kind: .tempo,
            title: "Tempo Builder",
            distance: "8.696 km",
            durationMinutes: 50
        )

        let display = TodayWorkoutDisplayModel.make(
            recommendation: recommendation,
            workout: workout,
            calendar: calendar
        )

        XCTAssertEqual(display.workoutType, "TEMPO RUN · OUTDOOR")
        XCTAssertEqual(display.targetPace, "5:44 /km")
        XCTAssertEqual(display.duration, "~50 min")
        XCTAssertEqual(display.intensity, "Zone 3")
        XCTAssertEqual(display.weekLabel, "Week 2")
        XCTAssertFalse(display.steps.isEmpty)
    }

    func testRunReportPayloadDecodesRichWebShape() throws {
        let json = """
        {
          "summary": "Controlled aerobic run with a strong finish.",
          "effort": "Comfortable",
          "recovery": { "priority": ["Hydrate", "Easy mobility"], "optional": ["Light walk"] },
          "coachScore": { "overall": 87 },
          "insights": ["Pace held steady", "Cadence improved late"],
          "pacingAnalysis": "Even pacing after the first kilometer.",
          "biomechanicalAnalysis": "Stable form under fatigue.",
          "structuredNextWorkout": {
            "sessionType": "Easy 7 km",
            "dateLabel": "2026-05-09",
            "distance": "7.0 km",
            "targetEffort": "5:45 /km",
            "coachingCue": "Keep it conversational."
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(RunSmartDTO.RunReportPayload.self, from: json)

        XCTAssertEqual(payload.coachScore, 87)
        XCTAssertEqual(payload.keyInsights?.count, 2)
        XCTAssertEqual(payload.pacing, "Even pacing after the first kilometer.")
        XCTAssertEqual(payload.biomechanics, "Stable form under fatigue.")
        XCTAssertEqual(payload.recoveryTimeline, ["Hydrate", "Easy mobility", "Light walk"])
        XCTAssertEqual(payload.structuredNextWorkout?.title, "Easy 7 km")
    }

    func testSkeletonReportIsNotTreatedAsGeneratedCoachAnalysis() {
        let run = RecordedRun(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            providerActivityID: nil,
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 1_777_777_777),
            endedAt: Date(timeIntervalSince1970: 1_777_778_377),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: 150,
            routePoints: [],
            syncedAt: nil
        )

        let report = SupabaseRunSmartServices.reportSkeleton(for: run)

        XCTAssertFalse(report.hasGeneratedReport)
        XCTAssertFalse(report.summary.hasGeneratedReport)
        XCTAssertEqual(report.notes.summary, "No coach report yet.")
    }

    func testSuggestedWorkoutParsingDefaultsToPlanFriendlyValues() {
        XCTAssertEqual(TrainingPlanRepository.suggestedWorkoutType(title: "Long Run 12 km"), "long")
        XCTAssertEqual(TrainingPlanRepository.suggestedWorkoutType(title: "Threshold intervals"), "intervals")
        XCTAssertEqual(TrainingPlanRepository.distanceKm(from: "Easy 7.5 km"), 7.5)
        XCTAssertEqual(TrainingPlanRepository.paceSecondsPerKm(from: "Keep around 5:45 /km"), 345)
        XCTAssertEqual(TrainingPlanRepository.durationMinutes(from: StructuredNextWorkout(
            title: "Recovery Run",
            dateLabel: nil,
            distance: nil,
            target: "30 min easy",
            notes: nil
        )), 30)
    }

    func testRecommendationPlanProfileReferenceFallbacksAreDeduped() {
        let authID = UUID(uuidString: "068053FD-0000-4000-8000-000000000000")!
        let references = TrainingPlanRepository.uniqueProfileReferences([
            .uuid(authID),
            .numeric(2),
            .uuid(authID),
            .numeric(2)
        ])

        XCTAssertEqual(references, [.uuid(authID), .numeric(2)])
    }

    func testRunRecorderMovingDurationExcludesActivePauseWhenFinishingPaused() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let pausedAt = startedAt.addingTimeInterval(120)
        let endedAt = startedAt.addingTimeInterval(300)

        let moving = RunRecorder.movingDuration(
            startedAt: startedAt,
            endedAt: endedAt,
            accumulatedPausedSeconds: 30,
            activePauseStartedAt: pausedAt
        )

        XCTAssertEqual(moving, 90)
    }

    @MainActor
    func testRunRecorderWaitsForUsableGPSLockBeforeStartingTimer() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 2_000)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.08, longitude: 34.78, accuracy: 50, timestamp: now)
        ], now: now)

        XCTAssertEqual(recorder.phase, .acquiringLocation)
        XCTAssertEqual(recorder.routePoints.count, 0)
        XCTAssertEqual(recorder.displayRoutePoints.count, 0)
        XCTAssertEqual(recorder.movingSeconds, 0)
        XCTAssertEqual(recorder.horizontalAccuracy, 50)
        recorder.discard()
    }

    @MainActor
    func testRunRecorderStartsWhenGPSLockMeetsThresholdAndIgnoresDuplicatePoint() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 2_100)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 12, timestamp: now)
        ], now: now)

        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(recorder.routePoints.count, 1)
        XCTAssertEqual(recorder.displayRoutePoints.count, 1)

        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800005, longitude: 34.7800005, accuracy: 10, timestamp: now.addingTimeInterval(1))
        ], now: now)

        XCTAssertEqual(recorder.routePoints.count, 1)
        recorder.discard()
    }

    @MainActor
    func testRunRecorderRejectsInvalidAndStaleLocationsAndWaitsOnWeakGPS() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 2_200)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.08, longitude: 34.78, accuracy: -1, timestamp: now),
            makeLocation(latitude: 32.08, longitude: 34.78, accuracy: 20, timestamp: now.addingTimeInterval(-30)),
            makeLocation(latitude: 32.08, longitude: 34.78, accuracy: 80, timestamp: now)
        ], now: now)

        XCTAssertEqual(recorder.phase, .acquiringLocation)
        XCTAssertEqual(recorder.horizontalAccuracy, 80)
        XCTAssertTrue(recorder.routePoints.isEmpty)
        recorder.discard()
    }

    @MainActor
    func testRunRecorderDiscardResetsCurrentWorkoutWithoutSaving() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 2_300)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 10, timestamp: now),
            makeLocation(latitude: 32.0810, longitude: 34.7810, accuracy: 10, timestamp: now.addingTimeInterval(3))
        ], now: now)

        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertGreaterThan(recorder.distanceMeters, 0)
        XCTAssertFalse(recorder.routePoints.isEmpty)

        recorder.discard()

        XCTAssertTrue(recorder.routePoints.isEmpty)
        XCTAssertTrue(recorder.displayRoutePoints.isEmpty)
        XCTAssertEqual(recorder.distanceMeters, 0)
        XCTAssertEqual(recorder.elapsedSeconds, 0)
        XCTAssertEqual(recorder.movingSeconds, 0)
        XCTAssertNil(recorder.horizontalAccuracy)
        XCTAssertNil(recorder.lastSavedRun)
        XCTAssertNotEqual(recorder.phase, .recording)
    }

    @MainActor
    func testRunRecorderDisplayRouteSimplificationPreservesRawRouteData() {
        let now = Date(timeIntervalSince1970: 2_400)
        let rawPoints = (0..<500).map { index in
            RunRoutePoint(
                latitude: 32.08 + Double(index) * 0.0001,
                longitude: 34.78 + Double(index) * 0.0001,
                timestamp: now.addingTimeInterval(Double(index)),
                horizontalAccuracy: 12,
                altitude: nil
            )
        }

        let displayPoints = RunRecorder.simplifiedDisplayRoute(from: rawPoints, maxPoints: 50)

        XCTAssertEqual(rawPoints.count, 500)
        XCTAssertLessThanOrEqual(displayPoints.count, 51)
        XCTAssertEqual(displayPoints.first?.id, rawPoints.first?.id)
        XCTAssertEqual(displayPoints.last?.id, rawPoints.last?.id)
    }

    @MainActor
    func testRunRecorderAccumulatesAllPointsAcrossConsecutiveLocationUpdates() {
        let recorder = RunRecorder()
        let origin = Date(timeIntervalSince1970: 5_000)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 12, timestamp: origin)
        ], now: origin)
        XCTAssertEqual(recorder.phase, .recording, "should enter recording after good lock")

        for i in 1...29 {
            let t = origin.addingTimeInterval(Double(i) * 4)
            let lat = 32.0800 + Double(i) * 0.0001
            recorder.handleLocationUpdates([
                makeLocation(latitude: lat, longitude: 34.7800, accuracy: 12, timestamp: t)
            ], now: t)
        }

        XCTAssertEqual(recorder.routePoints.count, 30)
        XCTAssertGreaterThan(recorder.distanceMeters, 200)
        recorder.discard()
    }

    func testTrainingDataAverageWeeklyDistanceUsesRecentFourWeekWindow() {
        let now = makeDate("2026-05-06").addingTimeInterval(12 * 3600)
        let runs = [
            makeRun(source: .garmin, startedAt: makeDate("2026-05-01"), distanceMeters: 12_000, movingTimeSeconds: 3_600),
            makeRun(source: .runSmart, startedAt: makeDate("2026-04-24"), distanceMeters: 8_000, movingTimeSeconds: 2_400),
            makeRun(source: .garmin, startedAt: makeDate("2026-03-20"), distanceMeters: 20_000, movingTimeSeconds: 6_000)
        ]

        let average = TrainingDataBaseline.averageWeeklyDistanceKm(from: runs, now: now)

        XCTAssertEqual(average, 5.0)
    }

    func testTrainingDataBaselinePrefersSavedWeeklyDistance() {
        let now = makeDate("2026-05-06").addingTimeInterval(12 * 3600)
        let runs = [
            makeRun(source: .garmin, startedAt: makeDate("2026-05-01"), distanceMeters: 12_000, movingTimeSeconds: 3_600)
        ]

        let average = TrainingDataBaseline.planAverageWeeklyKm(saved: 42, runs: runs, now: now)

        XCTAssertEqual(average, 42)
    }

    func testGeneratedPlanPayloadIncludesTrainingProfileBaseline() throws {
        let request = RunSmartDTO.GeneratePlanRequest(
            userContext: .init(
                userId: 7,
                goal: "Half Marathon",
                experience: "Advanced",
                age: 38,
                daysPerWeek: 5,
                preferredTimes: ["Mon", "Wed", "Fri"],
                coachingStyle: "Supportive",
                averageWeeklyKm: 42,
                trainingDataSource: "manual"
            ),
            trainingHistory: nil,
            goals: nil,
            challenge: nil,
            targetDistance: "Half Marathon",
            totalWeeks: 16,
            planPreferences: .init(
                trainingDays: ["Mon", "Wed", "Fri"],
                availableDays: ["Mon", "Wed", "Fri"],
                longRunDay: "Sun",
                trainingVolume: "moderate",
                difficulty: "adaptive"
            )
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let userContext = try XCTUnwrap(json["userContext"] as? [String: Any])

        XCTAssertEqual(userContext["experience"] as? String, "Advanced")
        XCTAssertEqual(userContext["age"] as? Int, 38)
        XCTAssertEqual(userContext["daysPerWeek"] as? Int, 5)
        XCTAssertEqual(userContext["averageWeeklyKm"] as? Double, 42)
        XCTAssertEqual(userContext["trainingDataSource"] as? String, "manual")
    }

    func testGeneratedPlanPersistenceUsesUUIDOwnerWhenProfileHasNumericID() {
        let authID = UUID(uuidString: "068053FD-204E-4053-B1AF-C70CF74A0440")!
        let identity = RunSmartIdentity(authUserID: authID, profileUUID: authID, numericUserID: 2)

        let reference = identity.planWriteProfileReference(fallback: authID)

        XCTAssertEqual(reference.debugValue, "uuid:\(authID.uuidString)")
    }

    func testGoalMappingUsesProfileConstraintSafeValues() {
        let request = TrainingGoalRequest(
            displayName: "Runner",
            goal: "Get Faster",
            experience: "Advanced",
            weeklyRunDays: 4,
            preferredDays: ["Mon", "Wed", "Fri", "Sun"],
            coachingTone: "Supportive",
            targetDate: makeDate("2026-08-01")
        )
        var profile = OnboardingProfile.empty
        profile.goal = "Build Habit"

        XCTAssertEqual(request.supabaseGoal, "fitness")
        XCTAssertEqual(request.webPlanGoal, "speed")
        XCTAssertEqual(profile.supabaseGoal, "habit")

        XCTAssertEqual(GoalWizardOption.option(matching: "race")?.title, "Get Faster")
        XCTAssertEqual(GoalWizardOption.option(matching: "Half Marathon")?.planGoal, "Half Marathon")
        XCTAssertEqual(GoalWizardOption.option(matching: "fitness")?.title, "Stay Fit")
    }

    func testRunSmartAPIClientDecodesFallbackPlanFromNonSuccessStatus() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RunSmartAPIStubProtocol.self]
        let session = URLSession(configuration: config)
        let client = URLSessionRunSmartAPIClient(baseURL: URL(string: "https://example.test")!, session: session)

        RunSmartAPIStubProtocol.responseStatusCode = 503
        RunSmartAPIStubProtocol.responseData = """
        {
          "plan": {
            "title": "Fallback Plan",
            "description": "Generated without AI",
            "totalWeeks": 2,
            "workouts": [
              { "week": 1, "day": "Mon", "type": "easy", "distance": 4.0, "duration": 24, "notes": "Easy effort" }
            ]
          },
          "source": "fallback",
          "error": "AI service unavailable"
        }
        """.data(using: .utf8)!

        let response = try await client.send(
            RunSmartAPI.Endpoint(path: "api/generate-plan", method: .post, body: Data("{}".utf8)),
            as: RunSmartDTO.GeneratePlanResponse.self
        )

        XCTAssertEqual(response.source, "fallback")
        XCTAssertEqual(response.plan?.title, "Fallback Plan")
        XCTAssertEqual(response.plan?.workouts.first?.day, "Mon")
    }

    func testHealthKitWorkoutMapperUsesStableProviderIDAndPace() {
        let providerID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let snapshot = HealthKitWorkoutSnapshot(
            uuid: providerID,
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 3_800),
            duration: 1_800,
            distanceMeters: 6_000,
            averageHeartRateBPM: 148,
            routePoints: []
        )

        let run = HealthKitRecordedRunMapper.recordedRun(from: snapshot, syncedAt: Date(timeIntervalSince1970: 4_000))
        let second = HealthKitRecordedRunMapper.recordedRun(from: snapshot, syncedAt: Date(timeIntervalSince1970: 5_000))

        XCTAssertEqual(run.id, second.id)
        XCTAssertEqual(run.providerActivityID, providerID.uuidString)
        XCTAssertEqual(run.source, .healthKit)
        XCTAssertEqual(run.averagePaceSecondsPerKm, 300)
        XCTAssertEqual(run.averageHeartRateBPM, 148)
    }

    func testHealthKitWorkoutMapperHandlesMissingDistanceAndHeartRate() {
        let snapshot = HealthKitWorkoutSnapshot(
            uuid: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_900),
            duration: 900,
            distanceMeters: nil,
            averageHeartRateBPM: nil,
            routePoints: []
        )

        let run = HealthKitRecordedRunMapper.recordedRun(from: snapshot)

        XCTAssertEqual(run.distanceMeters, 0)
        XCTAssertEqual(run.averagePaceSecondsPerKm, 0)
        XCTAssertNil(run.averageHeartRateBPM)
    }

    func testLocalStoreDedupesAndTombstonesHealthKitProviderRuns() {
        let store = RunSmartLocalStore.shared
        let providerID = UUID().uuidString
        let run = RecordedRun(
            id: HealthKitRecordedRunMapper.stableUUID(for: providerID),
            providerActivityID: providerID,
            source: .healthKit,
            startedAt: Date(timeIntervalSince1970: 10_000),
            endedAt: Date(timeIntervalSince1970: 10_600),
            distanceMeters: 2_000,
            movingTimeSeconds: 600,
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil
        )

        store.saveRun(run)
        store.saveRun(run)
        XCTAssertEqual(store.loadRuns().filter { $0.source == .healthKit && $0.providerActivityID == providerID }.count, 1)

        XCTAssertTrue(store.removeRun(run))
        store.saveRun(run)
        XCTAssertFalse(store.visibleRuns(store.loadRuns()).contains { $0.source == .healthKit && $0.providerActivityID == providerID })
    }

    func testDBRunInsertUsesHealthKitProviderForHealthImports() throws {
        let providerID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!.uuidString
        let run = RecordedRun(
            id: HealthKitRecordedRunMapper.stableUUID(for: providerID),
            providerActivityID: providerID,
            source: .healthKit,
            startedAt: Date(timeIntervalSince1970: 20_000),
            endedAt: Date(timeIntervalSince1970: 20_900),
            distanceMeters: 3_000,
            movingTimeSeconds: 900,
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: 140,
            routePoints: [],
            syncedAt: nil
        )

        let data = try JSONEncoder().encode(DBRunInsert(run: run, profileID: 7, kind: .easy, notes: "Imported from Apple Health"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["source_provider"] as? String, "healthkit")
        XCTAssertEqual(json["source_activity_id"] as? String, providerID)
        XCTAssertEqual(json["heart_rate"] as? Int, 140)
    }

    func testActivityConsolidationMergesSameRunAndKeepsRichestCanonical() {
        let start = makeDate("2026-05-05").addingTimeInterval(7 * 3600)
        let points = [
            RunRoutePoint(latitude: 32.0, longitude: 34.0, timestamp: start, horizontalAccuracy: 8, altitude: nil),
            RunRoutePoint(latitude: 32.001, longitude: 34.001, timestamp: start.addingTimeInterval(60), horizontalAccuracy: 8, altitude: nil)
        ]
        let runSmart = makeRun(source: .runSmart, startedAt: start, distanceMeters: 5_020, movingTimeSeconds: 1_510, routePoints: points)
        let health = makeRun(providerActivityID: "hk-1", source: .healthKit, startedAt: start.addingTimeInterval(40), distanceMeters: 5_000, movingTimeSeconds: 1_500, heartRate: 148)
        let garmin = makeRun(providerActivityID: "garmin-1", source: .garmin, startedAt: start.addingTimeInterval(30), distanceMeters: 5_010, movingTimeSeconds: 1_505, heartRate: 150)

        let consolidated = ActivityConsolidationService.consolidatedRuns([health, runSmart, garmin])

        XCTAssertEqual(consolidated.count, 1)
        XCTAssertEqual(consolidated[0].source, .garmin)
        XCTAssertEqual(consolidated[0].providerActivityID, "garmin-1")
        XCTAssertEqual(consolidated[0].averageHeartRateBPM, 150)
        XCTAssertEqual(consolidated[0].routePoints.count, 2)
        XCTAssertNotNil(consolidated[0].consolidatedActivityID)
    }

    func testActivityConsolidationLeavesSeparateSameDayRunsAlone() {
        let start = makeDate("2026-05-05").addingTimeInterval(7 * 3600)
        let morning = makeRun(providerActivityID: "garmin-morning", source: .garmin, startedAt: start, distanceMeters: 5_000, movingTimeSeconds: 1_500)
        let afternoon = makeRun(providerActivityID: "garmin-afternoon", source: .garmin, startedAt: start.addingTimeInterval(5 * 3600), distanceMeters: 6_000, movingTimeSeconds: 1_900)

        let consolidated = ActivityConsolidationService.consolidatedRuns([morning, afternoon])

        XCTAssertEqual(consolidated.count, 2)
    }

    func testActivityConsolidationDedupesSameSourceProviderRows() {
        let start = makeDate("2026-05-05").addingTimeInterval(7 * 3600)
        let first = makeRun(providerActivityID: "garmin-dup", source: .garmin, startedAt: start, distanceMeters: 5_000, movingTimeSeconds: 1_500)
        let richer = makeRun(providerActivityID: "garmin-dup", source: .garmin, startedAt: start, distanceMeters: 5_000, movingTimeSeconds: 1_500, heartRate: 150)

        let consolidated = ActivityConsolidationService.consolidatedRuns([first, richer])

        XCTAssertEqual(consolidated.count, 1)
        XCTAssertEqual(consolidated[0].averageHeartRateBPM, 150)
    }

    func testUserVisibleRecentRunsKeepsOnlyPlausibleLast14DayActivities() {
        let now = makeDate("2026-05-06").addingTimeInterval(12 * 3600)
        let realToday = makeRun(providerActivityID: "real-today", source: .healthKit, startedAt: makeDate("2026-05-06").addingTimeInterval(7 * 3600), distanceMeters: 7_600, movingTimeSeconds: 2_700)
        let realTwoDaysAgo = makeRun(providerActivityID: "real-two-days", source: .garmin, startedAt: makeDate("2026-05-04").addingTimeInterval(8 * 3600), distanceMeters: 7_100, movingTimeSeconds: 2_550)
        let nearZero = makeRun(providerActivityID: "noise-zero", source: .garmin, startedAt: makeDate("2026-05-06").addingTimeInterval(9 * 3600), distanceMeters: 10, movingTimeSeconds: 2_243)
        let tooShort = makeRun(providerActivityID: "noise-short", source: .garmin, startedAt: makeDate("2026-05-06").addingTimeInterval(8 * 3600), distanceMeters: 1_920, movingTimeSeconds: 468)
        let tooOld = makeRun(providerActivityID: "old-real", source: .garmin, startedAt: makeDate("2026-04-19").addingTimeInterval(8 * 3600), distanceMeters: 3_700, movingTimeSeconds: 1_400)

        let visible = ActivityConsolidationService.userVisibleRecentRuns(
            [nearZero, realTwoDaysAgo, tooOld, tooShort, realToday],
            now: now
        )

        XCTAssertEqual(visible.map(\.providerActivityID), ["real-today", "real-two-days"])
    }

    func testConsolidatedReportIDIsStableWhenGarminArrivesAfterHealthKit() {
        let start = makeDate("2026-05-05").addingTimeInterval(7 * 3600)
        let health = makeRun(providerActivityID: "hk-stable", source: .healthKit, startedAt: start, distanceMeters: 5_000, movingTimeSeconds: 1_500)
        let garmin = makeRun(providerActivityID: "garmin-stable", source: .garmin, startedAt: start.addingTimeInterval(30), distanceMeters: 5_010, movingTimeSeconds: 1_505, heartRate: 150)

        let healthOnly = ActivityConsolidationService.consolidatedRuns([health])[0]
        let afterGarmin = ActivityConsolidationService.consolidatedRuns([health, garmin])[0]

        XCTAssertEqual(SupabaseRunSmartServices.reportRunID(for: healthOnly), SupabaseRunSmartServices.reportRunID(for: afterGarmin))
        XCTAssertEqual(afterGarmin.source, .garmin)
    }

    func testWorkoutMatchSelectsSameDayIncompleteWorkout() {
        let run = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-05").addingTimeInterval(7 * 3600),
            distanceMeters: 8_100,
            movingTimeSeconds: 2_700
        )
        let matchingWorkout = makeWorkout(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, date: "2026-05-05", kind: .tempo, distance: "8.0 km", durationMinutes: 45)
        let wrongDay = makeWorkout(date: "2026-05-06", distance: "8.0 km", durationMinutes: 45)

        let match = TrainingPlanRepository.bestWorkoutMatch(for: run, in: [wrongDay, matchingWorkout])

        XCTAssertEqual(match?.id, matchingWorkout.id)
    }
}

final class RunSmartAPIStubProtocol: URLProtocol {
    static var responseStatusCode = 200
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
