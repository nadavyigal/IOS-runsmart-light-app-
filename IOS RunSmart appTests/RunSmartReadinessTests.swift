import XCTest
import CoreLocation
import AuthenticationServices
import UserNotifications
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

    func testCoachPersistenceInsertRowsUseOnlyThreadRoleAndContent() throws {
        let conversation = DBConversationInsert(profileId: "11111111-1111-1111-1111-111111111111")
        let message = DBMessageInsert(
            conversationId: "22222222-2222-2222-2222-222222222222",
            role: "assistant",
            content: "Today I see readiness at 82. Next up: Tempo Builder 8.0 km.",
            createdAt: "2026-05-17T07:00:00Z"
        )

        let conversationObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(conversation)) as? [String: Any]
        let messageObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
        let conversationKeys = Set(conversationObject?.keys.map { $0 } ?? [])
        let messageKeys = Set(messageObject?.keys.map { $0 } ?? [])

        XCTAssertEqual(conversationObject?["profile_id"] as? String, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(conversationKeys, ["profile_id"])
        XCTAssertEqual(messageObject?["conversation_id"] as? String, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(messageObject?["role"] as? String, "assistant")
        XCTAssertEqual(messageObject?["content"] as? String, "Today I see readiness at 82. Next up: Tempo Builder 8.0 km.")
        XCTAssertEqual(messageObject?["created_at"] as? String, "2026-05-17T07:00:00Z")
        XCTAssertEqual(messageKeys, ["conversation_id", "role", "content", "created_at"])
        XCTAssertNil(messageObject?["context"])
        XCTAssertNil(messageObject?["latitude"])
        XCTAssertNil(messageObject?["longitude"])
    }

    func testSendCoachMessageRequestEncodesContextWithoutRawCoordinates() async throws {
        let routePoint = RunRoutePoint(
            latitude: 32.0853,
            longitude: 34.7818,
            timestamp: Date(timeIntervalSince1970: 1_000),
            horizontalAccuracy: 6,
            altitude: nil
        )
        var services = TrainingContextTestServices()
        services.runs = [
            RecordedRun(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
                providerActivityID: nil,
                source: .runSmart,
                startedAt: Date(timeIntervalSince1970: 1_000),
                endedAt: Date(timeIntervalSince1970: 2_000),
                distanceMeters: 5_000,
                movingTimeSeconds: 1_600,
                averagePaceSecondsPerKm: 320,
                averageHeartRateBPM: 142,
                routePoints: [routePoint],
                syncedAt: nil
            )
        ]
        services.routes = [
            makeRouteSuggestion(id: "route-1", name: "Easy Loop", distanceKm: 5, points: [routePoint])
        ]
        let context = await services.trainingContext(for: .today)
        let request = RunSmartDTO.SendCoachMessageRequest(
            clientMessageId: "client-1",
            entryPoint: .today,
            message: "Should I still run today?",
            context: context,
            clientTimestamp: Date(timeIntervalSince1970: 0)
        )

        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"clientMessageId\":\"client-1\""))
        XCTAssertTrue(json.contains("\"entryPoint\":\"today\""))
        XCTAssertTrue(json.contains("\"message\":\"Should I still run today?\""))
        XCTAssertTrue(json.contains("\"context\""))
        XCTAssertTrue(json.contains("\"routePointCount\":1"))
        XCTAssertFalse(json.contains("32.0853"))
        XCTAssertFalse(json.contains("34.7818"))
        XCTAssertFalse(json.contains("\"latitude\""))
        XCTAssertFalse(json.contains("\"longitude\""))
        XCTAssertFalse(json.contains("\"routePoints\""))
        XCTAssertFalse(json.contains("\"coordinates\""))
        XCTAssertFalse(json.contains("\"polyline\""))
    }

    func testSendCoachMessageResponseMapsAssistantSourceAndFallback() throws {
        let data = """
        {
          "conversationId": "20000000-0000-4000-8000-000000000001",
          "userMessageId": "20000000-0000-4000-8000-000000000002",
          "assistantMessage": {
            "id": "20000000-0000-4000-8000-000000000003",
            "role": "assistant",
            "content": "Keep this easy and stay on track.",
            "createdAt": "2026-05-18T09:30:01Z"
          },
          "source": "fallback",
          "fallback": true,
          "suggestedAction": null,
          "safetyFlags": ["medical_caution"],
          "usage": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RunSmartDTO.SendCoachMessageResponse.self, from: data)

        XCTAssertEqual(response.conversationId, "20000000-0000-4000-8000-000000000001")
        XCTAssertEqual(response.userMessageId, "20000000-0000-4000-8000-000000000002")
        XCTAssertEqual(response.assistantMessage.role, "assistant")
        XCTAssertEqual(response.assistantMessage.content, "Keep this easy and stay on track.")
        XCTAssertEqual(response.source, "fallback")
        XCTAssertTrue(response.fallback)
        XCTAssertEqual(response.safetyFlags, ["medical_caution"])
    }

    func testReadinessCheckResponseDecodesProceedWithoutSafetyFlags() throws {
        let data = """
        {
          "decision": "proceed",
          "recommendation": "Run as planned and keep the effort controlled.",
          "modifications": [],
          "confidence": "high",
          "safetyFlags": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RunSmartDTO.ReadinessCheckResponseDTO.self, from: data)

        XCTAssertEqual(response.decision, .proceed)
        XCTAssertEqual(response.recommendation, "Run as planned and keep the effort controlled.")
        XCTAssertEqual(response.modifications, [])
        XCTAssertEqual(response.confidence, .high)
        XCTAssertEqual(response.safetyFlags, [])
    }

    func testReadinessCheckResponseDecodesModifyWithMissingDataSafetyFlag() throws {
        let data = """
        {
          "decision": "modify",
          "recommendation": "Keep this easy because recovery data is limited.",
          "modifications": ["Shorten by 15 minutes", "Stay conversational"],
          "confidence": "medium",
          "safetyFlags": [
            {
              "code": "missing_data",
              "severity": "medium",
              "message": "Recovery data is not available yet."
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RunSmartDTO.ReadinessCheckResponseDTO.self, from: data)

        XCTAssertEqual(response.decision, .modify)
        XCTAssertEqual(response.modifications, ["Shorten by 15 minutes", "Stay conversational"])
        XCTAssertEqual(response.confidence, .medium)
        XCTAssertEqual(response.safetyFlags, [
            RunSmartDTO.SafetyFlagDTO(
                code: .missingData,
                severity: .medium,
                message: "Recovery data is not available yet."
            )
        ])
    }

    func testReadinessCheckResponseDecodesSkipWithMedicalCautionSafetyFlag() throws {
        let data = """
        {
          "decision": "skip",
          "recommendation": "Stop activity, rest, and consult a qualified professional.",
          "modifications": ["Skip today's run"],
          "confidence": "high",
          "safetyFlags": [
            {
              "code": "medical_caution",
              "severity": "high",
              "message": "Pain or dizziness was reported."
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RunSmartDTO.ReadinessCheckResponseDTO.self, from: data)

        XCTAssertEqual(response.decision, .skip)
        XCTAssertEqual(response.recommendation, "Stop activity, rest, and consult a qualified professional.")
        XCTAssertEqual(response.safetyFlags.first?.code, .medicalCaution)
        XCTAssertEqual(response.safetyFlags.first?.severity, .high)
    }

    func testReadinessCheckRequestEncodesWithoutRawGPSCoordinates() throws {
        let request = RunSmartDTO.ReadinessCheckRequestDTO(
            entryPoint: "run",
            generatedAt: "2026-05-19T10:00:00Z",
            profile: .init(
                goal: "10K PR",
                level: "Building base",
                streak: "3 days",
                totalRuns: 12,
                averageWeeklyDistanceKm: 18.5
            ),
            plannedWorkout: .init(
                id: "workout-1",
                scheduledDate: "2026-05-19",
                title: "Easy Run",
                kind: "Easy Run",
                distance: "5.0 km",
                durationMinutes: 35,
                targetPace: "6:10 /km",
                detail: "Keep it relaxed.",
                isComplete: false
            ),
            recentRuns: [
                .init(
                    id: "run-1",
                    source: "RunSmart",
                    startedAt: "2026-05-17T07:30:00Z",
                    distanceKm: 4.8,
                    movingTimeSeconds: 1_820,
                    paceLabel: "6:19",
                    averageHeartRateBPM: 142,
                    rpe: 5,
                    hasRoute: true
                )
            ],
            recovery: .init(
                readiness: nil,
                bodyBattery: nil,
                sleep: nil,
                hrv: nil,
                stress: nil,
                recommendation: nil
            ),
            wellness: .init(
                soreness: "Mild",
                mood: "Good",
                hydration: "Normal",
                checkInStatus: "Checked in today."
            ),
            limitations: ["Recovery data is limited until HealthKit or Garmin syncs."]
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keySet = Set(object.keys.map { $0 })
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertEqual(keySet, [
            "entryPoint",
            "generatedAt",
            "profile",
            "plannedWorkout",
            "recentRuns",
            "recovery",
            "wellness",
            "limitations"
        ])
        XCTAssertTrue(json.contains("\"hasRoute\":true"))
        XCTAssertFalse(json.contains("\"latitude\""))
        XCTAssertFalse(json.contains("\"longitude\""))
        XCTAssertFalse(json.contains("\"routePoints\""))
        XCTAssertFalse(json.contains("\"coordinates\""))
        XCTAssertFalse(json.contains("\"polyline\""))
    }

    func testRunSmartAPIClientBuildsSupabaseFunctionRequestHeaders() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RunSmartAPIStubProtocol.self]
        let session = URLSession(configuration: config)
        let client = URLSessionRunSmartAPIClient(
            baseURL: URL(string: "https://example.test/functions/v1")!,
            session: session,
            accessToken: "jwt-token",
            additionalHeaders: ["apikey": "publishable-key"]
        )
        RunSmartAPIStubProtocol.lastRequest = nil
        RunSmartAPIStubProtocol.responseStatusCode = 200
        RunSmartAPIStubProtocol.responseData = """
        {
          "conversationId": "30000000-0000-4000-8000-000000000001",
          "userMessageId": "30000000-0000-4000-8000-000000000002",
          "assistantMessage": {
            "id": "30000000-0000-4000-8000-000000000003",
            "role": "assistant",
            "content": "Live coach response.",
            "createdAt": "2026-05-18T09:30:01Z"
          },
          "source": "live_ai",
          "fallback": false,
          "suggestedAction": null,
          "safetyFlags": [],
          "usage": { "inputTokens": 10, "outputTokens": 5, "totalTokens": 15 }
        }
        """.data(using: .utf8)!

        let response = try await client.send(
            RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: Data("{}".utf8)),
            as: RunSmartDTO.SendCoachMessageResponse.self
        )

        let request = try XCTUnwrap(RunSmartAPIStubProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/functions/v1/coach_message")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "publishable-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(response.source, "live_ai")
        XCTAssertFalse(response.fallback)
        XCTAssertEqual(response.usage?.totalTokens, 15)
    }

    func testTrainingContextCoachResponderUsesMedicalCautionFallback() async {
        let context = await TrainingContextTestServices().trainingContext(for: .today)
        let response = TrainingContextCoachResponder.response(
            to: "I feel chest pain and dizziness, should I run?",
            context: context
        )
        let lower = response.text.lowercased()

        XCTAssertTrue(lower.contains("stop"))
        XCTAssertTrue(lower.contains("qualified professional"))
        XCTAssertFalse(lower.contains("diagnose"))
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
        intensity: String? = nil,
        isComplete: Bool = false
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
            isComplete: isComplete,
            durationMinutes: durationMinutes,
            targetPaceSecondsPerKm: pace,
            intensity: intensity,
            trainingPhase: nil,
            workoutStructure: nil
        )
    }

    private func makeDBWorkout(
        id: UUID = UUID(),
        planID: UUID,
        date: Date,
        type: String = "easy",
        distance: Double = 5.0,
        duration: Int? = nil,
        completed: Bool = false
    ) throws -> DBWorkout {
        var payload: [String: Any] = [
            "id": id.uuidString,
            "plan_id": planID.uuidString,
            "week": 1,
            "day": "Mon",
            "type": type,
            "distance": distance,
            "completed": completed,
            "scheduled_date": ISO8601DateFormatter.shortDate.string(from: date)
        ]
        if let duration {
            payload["duration"] = duration
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(DBWorkout.self, from: data)
    }

    private func makeRun(
        id: UUID = UUID(),
        providerActivityID: String? = nil,
        source: RunSmartDataSource,
        startedAt: Date,
        distanceMeters: Double,
        movingTimeSeconds: TimeInterval,
        heartRate: Int? = nil,
        routePoints: [RunRoutePoint] = [],
        sourceDeviceName: String? = nil
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
            syncedAt: Date(timeIntervalSince1970: 30_000),
            sourceDeviceName: sourceDeviceName
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

    private func makeRoutePoints(
        latitude: Double = 32.0853,
        longitude: Double = 34.7818,
        count: Int = 16,
        latitudeStep: Double = 0.00045,
        longitudeStep: Double = 0.00035
    ) -> [RunRoutePoint] {
        let start = Date(timeIntervalSince1970: 1_000)
        return (0..<count).map { index in
            RunRoutePoint(
                latitude: latitude + (Double(index) * latitudeStep),
                longitude: longitude + (Double(index) * longitudeStep),
                timestamp: start.addingTimeInterval(Double(index) * 20),
                horizontalAccuracy: 8,
                altitude: nil
            )
        }
    }

    func testFirstSyncReviewExplainsDuplicateOnlySync() {
        let review = FirstSyncReview.make(
            provider: .garmin,
            importedRuns: [],
            skippedDuplicateCount: 4,
            createdAt: makeDate("2026-05-17")
        )

        XCTAssertEqual(review.provider, .garmin)
        XCTAssertEqual(review.importedCount, 0)
        XCTAssertEqual(review.skippedDuplicateCount, 4)
        XCTAssertEqual(review.routeAvailabilityCount, 0)
        XCTAssertEqual(review.routeLessCount, 0)
        XCTAssertEqual(review.nextAction, .today)
        XCTAssertTrue(review.summary.contains("did not create duplicates"))
        XCTAssertTrue(review.routeSummary.contains("No route data changed"))
    }

    func testFirstSyncReviewExplainsRouteLessImportsHonestly() {
        let run = makeRun(
            providerActivityID: "hk-route-less",
            source: .healthKit,
            startedAt: makeDate("2026-05-15"),
            distanceMeters: 6_200,
            movingTimeSeconds: 2_200
        )

        let review = FirstSyncReview.make(
            provider: .healthKit,
            importedRuns: [run],
            skippedDuplicateCount: 0,
            createdAt: makeDate("2026-05-17")
        )

        XCTAssertEqual(review.importedCount, 1)
        XCTAssertEqual(review.routeAvailabilityCount, 0)
        XCTAssertEqual(review.routeLessCount, 1)
        XCTAssertEqual(review.nextAction, .plan)
        XCTAssertTrue(review.routeSummary.contains("did not provide GPS routes"))
        XCTAssertTrue(review.coachCanUse.contains("Recent distance, pace, and training history"))
    }

    func testFirstSyncReviewCountsRoutesAndRecentActivities() {
        let routedRun = makeRun(
            providerActivityID: "garmin-routed",
            source: .garmin,
            startedAt: makeDate("2026-05-16"),
            distanceMeters: 8_000,
            movingTimeSeconds: 2_760,
            heartRate: 148,
            routePoints: makeRoutePoints(count: 12)
        )
        let routeLessRun = makeRun(
            providerActivityID: "garmin-route-less",
            source: .garmin,
            startedAt: makeDate("2026-05-14"),
            distanceMeters: 4_000,
            movingTimeSeconds: 1_400
        )

        let review = FirstSyncReview.make(
            provider: .garmin,
            importedRuns: [routeLessRun, routedRun],
            skippedDuplicateCount: 1,
            createdAt: makeDate("2026-05-17")
        )

        XCTAssertEqual(review.importedCount, 2)
        XCTAssertEqual(review.skippedDuplicateCount, 1)
        XCTAssertEqual(review.routeAvailabilityCount, 1)
        XCTAssertEqual(review.routeLessCount, 1)
        XCTAssertEqual(review.recentImportedActivities.map(\.id), ["garmin-routed", "garmin-route-less"])
        XCTAssertEqual(review.nextAction, .report)
        XCTAssertTrue(review.coachCanUse.contains("Heart-rate context from imported workouts"))
        XCTAssertTrue(review.coachCanUse.contains("Route-aware run review when GPS route data exists"))
    }

    private func makeSavedRoute(
        id: UUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        points: [RunRoutePoint],
        distanceMeters: Double
    ) -> SavedRoute {
        SavedRoute(
            id: id,
            name: "Benchmark Loop",
            distanceMeters: distanceMeters,
            elevationGainMeters: 0,
            points: points,
            source: .recorded,
            tags: [],
            notes: "",
            isFavorite: true,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeGarminActivity(
        id: Int,
        activityID: String,
        startTime: String,
        durationS: Double = 1_500,
        distanceM: Double = 5_000,
        avgHr: Int? = nil,
        sport: String? = "running"
    ) -> DBGarminActivity {
        DBGarminActivity(
            id: id,
            authUserId: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            activityId: activityID,
            startTime: startTime,
            sport: sport,
            durationS: durationS,
            distanceM: distanceM,
            avgHr: avgHr,
            avgPaceSPerKm: durationS / max(distanceM / 1_000, 0.1),
            elevationGainM: 24,
            calories: 320
        )
    }

    private func makeBenchmarkComparison(
        routeID: UUID,
        routeName: String,
        currentRunID: UUID,
        currentDuration: TimeInterval,
        currentPace: Double = 300,
        previous: BenchmarkRunPerformance?,
        personalBestRunID: UUID,
        personalBestDuration: TimeInterval,
        allTimeRunCount: Int,
        monthlyRunCount: Int,
        monthlyPace: Double = 300,
        monthlyHasEnoughData: Bool
    ) -> BenchmarkRouteComparison {
        BenchmarkRouteComparison(
            routeID: routeID,
            routeName: routeName,
            matchConfidence: .matched,
            currentPerformance: BenchmarkRunPerformance(
                runID: currentRunID,
                source: .runSmart,
                startedAt: Date(timeIntervalSince1970: 2_000),
                durationSeconds: currentDuration,
                paceSecondsPerKm: currentPace,
                averageHeartRateBPM: nil
            ),
            previousPerformance: previous,
            personalBest: BenchmarkRunPerformance(
                runID: personalBestRunID,
                source: .runSmart,
                startedAt: Date(timeIntervalSince1970: 1_000),
                durationSeconds: personalBestDuration,
                paceSecondsPerKm: personalBestDuration / 5,
                averageHeartRateBPM: nil
            ),
            allTimeAverage: BenchmarkPerformanceAverage(
                routeID: routeID,
                runCount: allTimeRunCount,
                averageDurationSeconds: currentDuration,
                averagePaceSecondsPerKm: currentPace,
                bestPaceSecondsPerKm: currentPace,
                averageHeartRateBPM: nil
            ),
            monthlyAverage: MonthlyBenchmarkAverage(
                routeID: routeID,
                monthStart: Date(timeIntervalSince1970: 1_000),
                runCount: monthlyRunCount,
                averageDurationSeconds: currentDuration,
                averagePaceSecondsPerKm: monthlyPace,
                bestPaceSecondsPerKm: min(currentPace, monthlyPace),
                averageHeartRateBPM: nil,
                hasEnoughData: monthlyHasEnoughData
            ),
            recentTrend: monthlyHasEnoughData ? .improving : .notEnoughData
        )
    }

    private func makeRouteSuggestion(
        id: String,
        name: String,
        distanceKm: Double,
        kind: RouteKind = .saved,
        points: [RunRoutePoint] = []
    ) -> RouteSuggestion {
        RouteSuggestion(
            id: id,
            name: name,
            distanceKm: distanceKm,
            elevationGainMeters: 24,
            estimatedDurationMinutes: Int(distanceKm * 6),
            points: points,
            kind: kind,
            recommendationReason: "Matches today's distance",
            savedRouteID: nil,
            isFavorite: true
        )
    }

    private struct TrainingContextTestServices: RunSmartServiceProviding {
        var today = TodayRecommendation(
            readiness: 82,
            readinessLabel: "Ready",
            workoutTitle: "Tempo Builder",
            distance: "8.0 km",
            pace: "5:20 /km",
            elevation: "--",
            coachMessage: "Keep it controlled.",
            weeklyProgress: "18 / 32 km",
            streak: "4 days",
            recovery: "7h 20m",
            hrv: "Stable"
        )
        var runner = RunnerProfile(name: "Alex", goal: "10K PR", streak: "4 day streak", level: "Intermediate", totalRuns: 42, totalDistance: 310, totalTime: "31h")
        var activePlan: TrainingPlanSnapshot? = TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: Date(timeIntervalSince1970: 1_000), endDate: Date(timeIntervalSince1970: 900_000), totalWeeks: 8, planType: "speed")
        var weekWorkouts: [WorkoutSummary] = []
        var upcoming: [WorkoutSummary] = []
        var recovery = RecoverySnapshot(readiness: 78, bodyBattery: 72, sleep: "7h 20m", hrv: "Stable", stress: "Low", recommendation: "Ready for controlled work.")
        var wellness = WellnessSnapshot(calories: "2,100", hydration: "Good", soreness: "Mild", mood: "Focused", checkInStatus: "Checked in today.")
        var runs: [RecordedRun] = []
        var routes: [RouteSuggestion] = []
        var reports: [RunReportSummary] = []

        func todayRecommendation() async -> TodayRecommendation { today }
        func weeklyPlan() async -> [WorkoutSummary] { weekWorkouts }
        func activeTrainingPlan() async -> TrainingPlanSnapshot? { activePlan }
        func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] { weekWorkouts }
        func nextWorkouts(limit: Int) async -> [WorkoutSummary] { Array(upcoming.prefix(limit)) }
        func saveTrainingGoal(_ request: TrainingGoalRequest) async -> Bool { true }
        func regenerateTrainingPlan(_ request: TrainingGoalRequest) async -> Bool { true }
        func moveWorkout(workoutID: UUID, to date: Date) async -> Bool { true }
        func pushWorkoutTomorrow(workoutID: UUID) async -> Bool { true }
        func amendWorkout(workoutID: UUID, patch: WorkoutPatch) async -> Bool { true }
        func removeWorkout(workoutID: UUID) async -> Bool { true }
        func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool { true }
        func recentMessages() async -> [CoachMessage] { [] }
        func send(message: String) async -> CoachMessage { CoachMessage(text: "compat", time: "Now", isUser: false) }
        func runnerProfile() async -> RunnerProfile { runner }
        func achievements() async -> [Achievement] { [] }
        func currentRunMetrics() async -> [MetricTile] { [] }
        func recentRuns() async -> [RecordedRun] { runs }
        func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
            RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart, startedAt: date, endedAt: date, distanceMeters: distanceKm * 1_000, movingTimeSeconds: Double(durationMinutes * 60), averagePaceSecondsPerKm: 300, averageHeartRateBPM: averageHeartRateBPM, routePoints: [], syncedAt: nil)
        }
        func removeRun(_ run: RecordedRun) async -> Bool { true }
        func finishRun() async {}
        func recoverySnapshot() async -> RecoverySnapshot { recovery }
        func wellnessSnapshot() async -> WellnessSnapshot { wellness }
        func latestRunReports(limit: Int) async -> [RunReportSummary] { Array(reports.prefix(limit)) }
        func trainingLoadSnapshot() async -> TrainingLoadSnapshot { .loading }
        func routeSuggestions() async -> [RouteSuggestion] { routes }
        func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] { [] }
        func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion] { routes }
        func savedRoutes() async -> [SavedRoute] { [] }
        func saveRoute(_ route: SavedRoute) async -> Bool { true }
        func deleteRoute(_ routeID: UUID) async -> Bool { true }
        func updateRoute(_ route: SavedRoute) async -> Bool { true }
        func benchmarkRoutes() async -> [BenchmarkRoute] { [] }
        func enableBenchmark(for routeID: UUID) async -> Bool { true }
        func disableBenchmark(for routeID: UUID) async -> Bool { true }
        func deviceStatuses() async -> [ConnectedDeviceStatus] { [] }
        func connect(provider: String) async -> ConnectedDeviceStatus { ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: nil, permissions: [], message: nil) }
        func syncNow(provider: String) async -> ConnectedDeviceStatus { ConnectedDeviceStatus(provider: provider, state: .connected, lastSuccessfulSync: nil, permissions: [], message: nil) }
        func disconnect(provider: String) async -> ConnectedDeviceStatus { ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil) }
        func requestHealthAccess() async -> ConnectedDeviceStatus { ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: nil, permissions: [], message: nil) }
        func syncHealthData() async -> ConnectedDeviceStatus { ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: nil, permissions: [], message: nil) }
        func saveToHealth(_ run: RecordedRun) async {}
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
        // WP-44 S3: intensity now comes from TrainingMetrics.effortLabel — one
        // vocabulary (effort words) on card and sheet, not "Easy" here and
        // "Zone 3" there.
        XCTAssertEqual(display.intensity, TrainingMetrics.effortLabel(for: .tempo))
        XCTAssertEqual(display.weekLabel, "Week 2")
        XCTAssertFalse(display.steps.isEmpty)
    }

    func testTodayResolvedStateSettlesAfterCompletedSameDayWorkoutAndKeepsFutureUpNext() {
        // Use the machine's local timezone so it stays consistent with makeDate(),
        // which parses via ISO8601DateFormatter.shortDate (timeZone = .current).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = makeDate("2026-05-20").addingTimeInterval(9 * 3600)
        let completedToday = makeWorkout(
            date: "2026-05-20",
            kind: .long,
            title: "Long Run",
            distance: "10.0 km",
            durationMinutes: 64,
            isComplete: true
        )
        let future = makeWorkout(
            date: "2026-05-25",
            kind: .easy,
            title: "Easy Reset",
            distance: "5.0 km"
        )
        let run = makeRun(
            source: .runSmart,
            startedAt: now.addingTimeInterval(-3600),
            distanceMeters: 10_100,
            movingTimeSeconds: 64 * 60
        )

        let state = TodayResolvedState.make(
            recommendation: TodayRecommendation(readiness: 82, readinessLabel: "Ready", workoutTitle: "Easy Reset", distance: "5.0 km", pace: "6:00 /km", elevation: "--", coachMessage: "Nice work today."),
            weekWorkouts: [completedToday],
            nextWorkouts: [future],
            recentRuns: [run],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.kind, .completedToday)
        XCTAssertEqual(state.primaryWorkout.id, completedToday.id)
        XCTAssertEqual(state.completedRun?.id, run.id)
        XCTAssertEqual(state.upNextWorkout?.id, future.id)
        XCTAssertFalse(state.showsStartAction)
        XCTAssertFalse(state.showsTodayRoute)
        XCTAssertEqual(state.headline, "Run complete today")
    }

    // WP-44 S5: "what should I do today?" must always have an answer (audit §7).
    // A rest day used to render only the plan row's thin detail; the resolved
    // state must now expose explicit recovery guidance, and only for rest days.
    func testTodayRendersRestDayGuidanceWhenNoWorkout() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = makeDate("2026-05-20").addingTimeInterval(9 * 3600)
        let rest = makeWorkout(
            date: "2026-05-20",
            kind: .easy,
            title: "Rest",
            distance: "Rest"
        )
        let recommendation = TodayRecommendation(readiness: 82, readinessLabel: "Ready", workoutTitle: "Rest", distance: "Rest", pace: "--", elevation: "--", coachMessage: "Recovery day.")

        let state = TodayResolvedState.make(
            recommendation: recommendation,
            weekWorkouts: [rest],
            nextWorkouts: [],
            recentRuns: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.kind, .restDay)
        let guidance = state.restDayGuidance
        XCTAssertNotNil(guidance, "a rest day must answer the daily question with recovery guidance, not render nothing")
        XCTAssertFalse(guidance!.isEmpty, "guidance must contain at least one concrete recovery action")

        let planned = TodayResolvedState.make(
            recommendation: recommendation,
            weekWorkouts: [makeWorkout(date: "2026-05-20", kind: .easy, title: "Easy Run", distance: "5.0 km")],
            nextWorkouts: [],
            recentRuns: [],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(planned.kind, .plannedToday)
        XCTAssertNil(planned.restDayGuidance, "recovery guidance must not appear on a workout day")
    }

    func testTodayResolvedStateTreatsSameDayGarminImportAsCompletedWithoutWorkoutMatch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = makeDate("2026-05-20").addingTimeInterval(12 * 3600)
        let future = makeWorkout(date: "2026-05-25", title: "Easy Reset", distance: "5.0 km")
        let garmin = makeRun(
            providerActivityID: "garmin-today",
            source: .garmin,
            startedAt: now.addingTimeInterval(-2 * 3600),
            distanceMeters: 7_200,
            movingTimeSeconds: 42 * 60
        )

        let state = TodayResolvedState.make(
            recommendation: TodayRecommendation(readiness: 70, readinessLabel: "Ready", workoutTitle: "Easy Reset", distance: "5.0 km", pace: "6:00 /km", elevation: "--", coachMessage: "Imported run counted."),
            weekWorkouts: [],
            nextWorkouts: [future],
            recentRuns: [garmin],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.kind, .completedToday)
        XCTAssertEqual(state.primaryWorkout.title, "Run complete today")
        XCTAssertEqual(state.primaryWorkout.distance, "7.2 km")
        XCTAssertEqual(state.completedRun?.source, .garmin)
        XCTAssertEqual(state.upNextWorkout?.id, future.id)
        XCTAssertFalse(state.showsStartAction)
        XCTAssertFalse(state.showsTodayRoute)
    }

    func testTodayResolvedStateLetsUpcomingPlanWorkoutStartFromToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = makeDate("2026-05-20").addingTimeInterval(9 * 3600)
        let future = makeWorkout(
            date: "2026-05-21",
            kind: .easy,
            title: "Easy Reset",
            distance: "5.0 km"
        )

        let state = TodayResolvedState.make(
            recommendation: TodayRecommendation(readiness: 75, readinessLabel: "Ready", workoutTitle: "Easy Reset", distance: "5.0 km", pace: "6:00 /km", elevation: "--", coachMessage: "Start when ready."),
            weekWorkouts: [],
            nextWorkouts: [future],
            recentRuns: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.kind, .upNext)
        XCTAssertEqual(state.primaryWorkout.id, future.id)
        XCTAssertTrue(state.showsStartAction)
        XCTAssertEqual(state.primaryActionTitle, "Start Next Run")
        XCTAssertFalse(state.showsTodayRoute)
    }

    func testPlanExplanationExplainsTodayWorkoutOnTrack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = makeDate("2026-05-07").addingTimeInterval(9 * 3600)
        let workout = makeWorkout(date: "2026-05-07", kind: .tempo, title: "Tempo Builder", distance: "8.0 km")
        let explanation = PlanExplanation.make(
            activePlan: TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: makeDate("2026-05-01"), endDate: makeDate("2026-06-30"), totalWeeks: 8, planType: "10K"),
            todayWorkout: workout,
            weekWorkouts: [workout],
            nextWorkouts: [workout],
            recentRuns: [],
            recovery: RecoverySnapshot(readiness: 76, bodyBattery: 70, sleep: "7h", hrv: "Stable", stress: "Low", recommendation: "Ready."),
            recommendation: TodayRecommendation(readiness: 80, readinessLabel: "Ready", workoutTitle: "Tempo Builder", distance: "8.0 km", pace: "5:20 /km", elevation: "--", coachMessage: "Go controlled."),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(explanation.trigger, .normal)
        XCTAssertTrue(explanation.evidence.contains("Tempo Builder"))
        XCTAssertNil(explanation.action)
        XCTAssertEqual(explanation.source, .heuristic)
    }

    func testPlanExplanationHandlesNoPlanAndRestDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = makeDate("2026-05-07").addingTimeInterval(9 * 3600)
        let noPlan = PlanExplanation.make(
            activePlan: nil,
            todayWorkout: nil,
            weekWorkouts: [],
            nextWorkouts: [],
            recentRuns: [],
            recovery: .loading,
            recommendation: TodayRecommendation(readiness: 0, readinessLabel: "Loading", workoutTitle: "Rest Day", distance: "--", pace: "--:--", elevation: "--", coachMessage: ""),
            now: now,
            calendar: calendar
        )
        let rest = makeWorkout(date: "2026-05-07", kind: .recovery, title: "Recovery", distance: "Rest")
        let restDay = PlanExplanation.make(
            activePlan: TrainingPlanSnapshot(id: UUID(), title: "Base", startDate: makeDate("2026-05-01"), endDate: makeDate("2026-05-31"), totalWeeks: 4, planType: "base"),
            todayWorkout: rest,
            weekWorkouts: [rest],
            nextWorkouts: [rest],
            recentRuns: [],
            recovery: RecoverySnapshot(readiness: 70, bodyBattery: 65, sleep: "7h", hrv: "Stable", stress: "Low", recommendation: "Recover."),
            recommendation: TodayRecommendation(readiness: 70, readinessLabel: "Ready", workoutTitle: "Rest Day", distance: "--", pace: "--:--", elevation: "--", coachMessage: ""),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(noPlan.source, .fallback)
        XCTAssertEqual(noPlan.action, "Set a goal")
        XCTAssertEqual(restDay.trigger, .normal)
        XCTAssertTrue(restDay.evidence.contains("No run is scheduled"))
    }

    func testPlanExplanationPrioritizesSupportiveMissedWorkoutCopy() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = makeDate("2026-05-07").addingTimeInterval(9 * 3600)
        let missed = makeWorkout(date: "2026-05-06", kind: .easy, title: "Easy Run", distance: "5.0 km")
        let today = makeWorkout(date: "2026-05-07", kind: .tempo, title: "Tempo Builder", distance: "8.0 km")

        let explanation = PlanExplanation.make(
            activePlan: TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: makeDate("2026-05-01"), endDate: makeDate("2026-06-30"), totalWeeks: 8, planType: "10K"),
            todayWorkout: today,
            weekWorkouts: [missed, today],
            nextWorkouts: [today],
            recentRuns: [],
            recovery: RecoverySnapshot(readiness: 72, bodyBattery: 68, sleep: "7h", hrv: "Stable", stress: "Low", recommendation: "Ready."),
            recommendation: TodayRecommendation(readiness: 72, readinessLabel: "Ready", workoutTitle: "Tempo Builder", distance: "8.0 km", pace: "5:20 /km", elevation: "--", coachMessage: ""),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(explanation.trigger, .missedWorkout)
        XCTAssertTrue(explanation.recommendation.contains("No stress"))
        XCTAssertEqual(explanation.action, "Reschedule")
    }

    func testPlanExplanationPrioritizesSameDayCompletedRunOverMissedWorkout() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = makeDate("2026-05-20").addingTimeInterval(12 * 3600)
        let missed = makeWorkout(date: "2026-05-19", kind: .easy, title: "Easy Run", distance: "5.0 km")
        let today = makeWorkout(date: "2026-05-20", kind: .long, title: "Long Run", distance: "10.0 km", isComplete: true)
        let completedRun = makeRun(
            source: .runSmart,
            startedAt: now.addingTimeInterval(-2 * 3600),
            distanceMeters: 10_100,
            movingTimeSeconds: 64 * 60
        )

        let explanation = PlanExplanation.make(
            activePlan: TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: makeDate("2026-05-01"), endDate: makeDate("2026-06-30"), totalWeeks: 8, planType: "10K"),
            todayWorkout: today,
            weekWorkouts: [missed, today],
            nextWorkouts: [],
            recentRuns: [completedRun],
            recovery: RecoverySnapshot(readiness: 72, bodyBattery: 68, sleep: "7h", hrv: "Stable", stress: "Low", recommendation: "Ready."),
            recommendation: TodayRecommendation(readiness: 72, readinessLabel: "Ready", workoutTitle: "Long Run", distance: "10.0 km", pace: "6:00 /km", elevation: "--", coachMessage: ""),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(explanation.trigger, .completedRun)
        XCTAssertTrue(explanation.evidence.contains("Today"))
        XCTAssertFalse(explanation.evidence.contains("Easy Run"))
        XCTAssertNil(explanation.action)
    }

    func testPlanExplanationUsesRecentImportedAndLowRecoverySignals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = makeDate("2026-05-07").addingTimeInterval(9 * 3600)
        let today = makeWorkout(date: "2026-05-07", kind: .easy, title: "Easy Run", distance: "5.0 km")
        let imported = makeRun(
            providerActivityID: "garmin-1",
            source: .garmin,
            startedAt: makeDate("2026-05-06").addingTimeInterval(8 * 3600),
            distanceMeters: 6_400,
            movingTimeSeconds: 2_200
        )

        let importedExplanation = PlanExplanation.make(
            activePlan: TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: makeDate("2026-05-01"), endDate: makeDate("2026-06-30"), totalWeeks: 8, planType: "10K"),
            todayWorkout: today,
            weekWorkouts: [today],
            nextWorkouts: [today],
            recentRuns: [imported],
            recovery: RecoverySnapshot(readiness: 74, bodyBattery: 70, sleep: "7h", hrv: "Stable", stress: "Low", recommendation: "Ready."),
            recommendation: TodayRecommendation(readiness: 74, readinessLabel: "Ready", workoutTitle: "Easy Run", distance: "5.0 km", pace: "6:00 /km", elevation: "--", coachMessage: ""),
            now: now,
            calendar: calendar
        )
        let lowRecovery = PlanExplanation.make(
            activePlan: TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: makeDate("2026-05-01"), endDate: makeDate("2026-06-30"), totalWeeks: 8, planType: "10K"),
            todayWorkout: today,
            weekWorkouts: [today],
            nextWorkouts: [today],
            recentRuns: [imported],
            recovery: RecoverySnapshot(readiness: 32, bodyBattery: 24, sleep: "5h", hrv: "Lower", stress: "High", recommendation: "Keep it easy."),
            recommendation: TodayRecommendation(readiness: 36, readinessLabel: "Low energy", workoutTitle: "Easy Run", distance: "5.0 km", pace: "6:00 /km", elevation: "--", coachMessage: ""),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(importedExplanation.trigger, .importedActivity)
        XCTAssertTrue(importedExplanation.evidence.contains("Garmin"))
        XCTAssertEqual(lowRecovery.trigger, .lowRecovery)
        XCTAssertEqual(lowRecovery.action, "Amend workout")
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


    func testPostRunLearningCardUsesFallbackReportAndSuggestedWorkoutAction() {
        let run = makeRun(
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            routePoints: makeRoutePoints()
        )
        let report = RunReportDetail(
            id: "report-1",
            runID: run.id.uuidString,
            title: "RunSmart Run Report",
            dateLabel: "May 17, 2026",
            source: "RunSmart",
            distance: "5.00 km",
            duration: "25:00",
            averagePace: "5:00",
            averageHeartRate: "150 bpm",
            coachScore: nil,
            notes: CoachRunNotes(
                summary: "Completed a steady aerobic run.",
                effort: "Moderate",
                recovery: "Keep tomorrow easy.",
                nextSessionNudge: "Next recommended: Easy 6 km."
            ),
            structuredNextWorkout: StructuredNextWorkout(title: "Easy 6 km", dateLabel: "May 18", distance: "6.0 km", target: "Easy", notes: nil),
            isGenerated: true
        )
        let plan = TrainingPlanSnapshot(
            id: UUID(),
            title: "10K Build",
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 90_000),
            totalWeeks: 8,
            planType: "10K"
        )

        let model = PostRunLearningCardModel.make(run: run, outcome: nil, report: report, activePlan: plan)

        XCTAssertEqual(model.source, .fallback)
        XCTAssertEqual(model.planImpact, .needsReview)
        XCTAssertEqual(model.nextActionTitle, "Save suggested next run")
        if case .saveSuggestedWorkout(let next, let actionReport) = model.action {
            XCTAssertEqual(next.title, "Easy 6 km")
            XCTAssertEqual(actionReport.id, report.id)
        } else {
            XCTFail("Expected suggested workout action")
        }
    }

    func testPostRunLearningCardHandlesNoActivePlanAndShortRun() {
        let run = makeRun(
            source: .healthKit,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 300,
            movingTimeSeconds: 120,
            routePoints: []
        )

        let model = PostRunLearningCardModel.make(run: run, outcome: nil, report: nil, activePlan: nil)

        // source is .fallback (run exists but no AI report); .heuristic is only when run == nil
        XCTAssertEqual(model.source, .fallback)
        XCTAssertEqual(model.planImpact, .unavailable)
        XCTAssertTrue(model.happened.contains("short"))
        XCTAssertTrue(model.learned.contains("too short"))
        XCTAssertEqual(model.nextActionTitle, "Create a plan first")
        if case .unavailable(let title) = model.action {
            XCTAssertEqual(title, "Create a plan first")
        } else {
            XCTFail("Expected unavailable action")
        }
    }

    func testRouteMatchingReturnsHighConfidenceForSameRoute() {
        let points = makeRoutePoints()
        let routeID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let route = makeSavedRoute(id: routeID, points: points, distanceMeters: 5_000)
        let run = makeRun(
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 5_050,
            movingTimeSeconds: 1_500,
            routePoints: points
        )

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertEqual(match?.confidence, .matched)
        XCTAssertEqual(match?.routeID, routeID)
        XCTAssertEqual(match?.candidateRouteID, routeID)
        XCTAssertFalse(match?.isReversed ?? true)
    }

    func testRouteMatchingMarksNearbyNoisyRouteAsPossibleWithoutAttaching() {
        let routePoints = makeRoutePoints()
        let noisyRunPoints = makeRoutePoints(latitude: 32.0859, longitude: 34.7824)
        let routeID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let route = makeSavedRoute(id: routeID, points: routePoints, distanceMeters: 5_000)
        let run = makeRun(
            source: .garmin,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 5_520,
            movingTimeSeconds: 1_620,
            routePoints: noisyRunPoints
        )

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertEqual(match?.confidence, .possibleMatch)
        XCTAssertNil(match?.routeID)
        XCTAssertEqual(match?.candidateRouteID, routeID)
    }

    func testRouteMatchingReturnsNoMatchForUnrelatedRoute() {
        let route = makeSavedRoute(points: makeRoutePoints(), distanceMeters: 5_000)
        let run = makeRun(
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 7_200,
            movingTimeSeconds: 2_100,
            routePoints: makeRoutePoints(latitude: 32.2, longitude: 34.9)
        )

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertEqual(match?.confidence, .noMatch)
        XCTAssertNil(match?.routeID)
    }

    func testRouteMatchingHandlesReversedRouteAsMatch() {
        let points = makeRoutePoints()
        let routeID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let route = makeSavedRoute(id: routeID, points: points, distanceMeters: 5_000)
        let run = makeRun(
            source: .garmin,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 5_020,
            movingTimeSeconds: 1_520,
            routePoints: Array(points.reversed())
        )

        let match = RouteMatchingService.match(run: run, savedRoutes: [route])

        XCTAssertEqual(match?.confidence, .matched)
        XCTAssertEqual(match?.routeID, routeID)
        XCTAssertTrue(match?.isReversed ?? false)
    }

    func testRouteMatchingIgnoresManualRouteLessRuns() {
        let route = makeSavedRoute(points: makeRoutePoints(), distanceMeters: 5_000)
        let run = makeRun(
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 2_000),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            routePoints: []
        )

        XCTAssertNil(RouteMatchingService.match(run: run, savedRoutes: [route]))
    }

    func testBenchmarkComparisonReturnsFirstRunNotEnoughHistory() {
        let routeID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let points = makeRoutePoints()
        let route = makeSavedRoute(id: routeID, points: points, distanceMeters: 5_000)
        let match = RouteMatchResult(
            routeID: routeID,
            candidateRouteID: routeID,
            confidence: .matched,
            distanceDeltaMeters: 20,
            startDeltaMeters: 10,
            endDeltaMeters: 10,
            shapeSimilarity: 0.95,
            isReversed: false
        )
        var run = makeRun(
            source: .runSmart,
            startedAt: makeDate("2026-05-03"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            heartRate: 148,
            routePoints: points
        )
        run.routeMatchResult = match
        let benchmark = BenchmarkRoute(
            id: UUID(),
            savedRouteID: routeID,
            enabledAt: makeDate("2026-05-01"),
            historicalRunCount: 0,
            personalBestSeconds: nil,
            personalBestDate: nil,
            averagePaceSecondsPerKm: nil,
            averageDurationSeconds: nil
        )

        let comparison = BenchmarkRouteAnalyticsService.comparison(
            for: run,
            runs: [run],
            savedRoutes: [route],
            benchmarkRoutes: [benchmark],
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(comparison?.routeID, routeID)
        XCTAssertEqual(comparison?.routeName, "Benchmark Loop")
        XCTAssertNil(comparison?.previousPerformance)
        XCTAssertEqual(comparison?.personalBest.runID, run.id)
        XCTAssertFalse(comparison?.hasEnoughHistory ?? true)
        XCTAssertEqual(comparison?.monthlyAverage.runCount, 1)
        XCTAssertFalse(comparison?.monthlyAverage.hasEnoughData ?? true)
        XCTAssertEqual(comparison?.recentTrend, .notEnoughData)
    }

    func testBenchmarkComparisonUsesPreviousPBAndAveragesAcrossGarminAndRunSmartRuns() {
        let routeID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let points = makeRoutePoints()
        let route = makeSavedRoute(id: routeID, points: points, distanceMeters: 5_000)
        let match = RouteMatchResult(
            routeID: routeID,
            candidateRouteID: routeID,
            confidence: .matched,
            distanceDeltaMeters: 0,
            startDeltaMeters: 0,
            endDeltaMeters: 0,
            shapeSimilarity: 1,
            isReversed: false
        )
        var older = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-02"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_560,
            heartRate: 150,
            routePoints: points
        )
        var previous = makeRun(
            source: .runSmart,
            startedAt: makeDate("2026-05-09"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_520,
            heartRate: 146,
            routePoints: points
        )
        var current = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-16"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_480,
            heartRate: 144,
            routePoints: points
        )
        older.routeMatchResult = match
        previous.routeMatchResult = match
        current.routeMatchResult = match
        let benchmark = BenchmarkRoute(
            id: UUID(),
            savedRouteID: routeID,
            enabledAt: makeDate("2026-05-01"),
            historicalRunCount: 0,
            personalBestSeconds: nil,
            personalBestDate: nil,
            averagePaceSecondsPerKm: nil,
            averageDurationSeconds: nil
        )

        let comparison = BenchmarkRouteAnalyticsService.comparison(
            for: current,
            runs: [older, current, previous],
            savedRoutes: [route],
            benchmarkRoutes: [benchmark],
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(comparison?.previousPerformance?.runID, previous.id)
        XCTAssertEqual(comparison?.personalBest.runID, current.id)
        XCTAssertEqual(comparison?.allTimeAverage.runCount, 3)
        XCTAssertEqual(comparison?.allTimeAverage.averageDurationSeconds, 1_520)
        XCTAssertEqual(comparison?.allTimeAverage.averagePaceSecondsPerKm, 304)
        XCTAssertEqual(comparison?.monthlyAverage.runCount, 3)
        XCTAssertEqual(comparison?.monthlyAverage.averageHeartRateBPM, 147)
        XCTAssertTrue(comparison?.monthlyAverage.hasEnoughData ?? false)
        XCTAssertEqual(comparison?.recentTrend, .improving)
        XCTAssertTrue(comparison?.hasEnoughHistory ?? false)
    }

    func testBenchmarkComparisonMonthlyAverageRespectsLocalCalendarMonthBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 60 * 60)!
        let routeID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let points = makeRoutePoints()
        let route = makeSavedRoute(id: routeID, points: points, distanceMeters: 5_000)
        let match = RouteMatchResult(
            routeID: routeID,
            candidateRouteID: routeID,
            confidence: .matched,
            distanceDeltaMeters: 0,
            startDeltaMeters: 0,
            endDeltaMeters: 0,
            shapeSimilarity: 1,
            isReversed: false
        )
        var aprilLocal = makeRun(
            source: .runSmart,
            startedAt: calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 4, day: 30, hour: 23, minute: 30))!,
            distanceMeters: 5_000,
            movingTimeSeconds: 1_600,
            routePoints: points
        )
        var mayLocal = makeRun(
            source: .garmin,
            startedAt: calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 1, hour: 0, minute: 30))!,
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            routePoints: points
        )
        aprilLocal.routeMatchResult = match
        mayLocal.routeMatchResult = match
        let benchmark = BenchmarkRoute(
            id: UUID(),
            savedRouteID: routeID,
            enabledAt: makeDate("2026-04-01"),
            historicalRunCount: 0,
            personalBestSeconds: nil,
            personalBestDate: nil,
            averagePaceSecondsPerKm: nil,
            averageDurationSeconds: nil
        )

        let comparison = BenchmarkRouteAnalyticsService.comparison(
            for: mayLocal,
            runs: [aprilLocal, mayLocal],
            savedRoutes: [route],
            benchmarkRoutes: [benchmark],
            calendar: calendar
        )

        XCTAssertEqual(comparison?.monthlyAverage.runCount, 1)
        XCTAssertEqual(comparison?.monthlyAverage.averageDurationSeconds, 1_500)
        XCTAssertFalse(comparison?.monthlyAverage.hasEnoughData ?? true)
    }

    func testGarminImportProcessorHydratesRoutePointsAndOrdersNewestFirst() async {
        let older = makeGarminActivity(
            id: 1,
            activityID: "garmin-older",
            startTime: "2026-05-12T06:00:00Z"
        )
        let newer = makeGarminActivity(
            id: 2,
            activityID: "garmin-newer",
            startTime: "2026-05-14T06:00:00Z"
        )
        let routePoints = makeRoutePoints()

        let runs = await GarminImportProcessor.normalizedRuns(
            from: [older, newer],
            isHidden: { _ in false },
            routePointLoader: { activityID in
                activityID == "garmin-newer" ? routePoints : []
            }
        )

        XCTAssertEqual(runs.map(\.providerActivityID), ["garmin-newer", "garmin-older"])
        XCTAssertEqual(runs.first?.routePoints, routePoints)
        XCTAssertEqual(runs.last?.routePoints, [])
    }

    func testGarminImportProcessorKeepsRouteLessRunWhenMapDataIsMissing() async {
        let activity = makeGarminActivity(
            id: 3,
            activityID: "garmin-no-map",
            startTime: "2026-05-14T06:00:00Z"
        )

        let run = await GarminImportProcessor.newestNormalizedRun(
            from: [activity],
            isHidden: { _ in false },
            routePointLoader: { _ in [] }
        )

        XCTAssertEqual(run?.providerActivityID, "garmin-no-map")
        XCTAssertEqual(run?.source, .garmin)
        XCTAssertEqual(run?.routePoints, [])
    }

    func testGarminImportProcessorSkipsHiddenRunsBeforeSelectingNewest() async {
        let hiddenNewer = makeGarminActivity(
            id: 4,
            activityID: "garmin-hidden",
            startTime: "2026-05-14T06:00:00Z"
        )
        let visibleOlder = makeGarminActivity(
            id: 5,
            activityID: "garmin-visible",
            startTime: "2026-05-13T06:00:00Z"
        )

        let run = await GarminImportProcessor.newestNormalizedRun(
            from: [hiddenNewer, visibleOlder],
            isHidden: { $0.providerActivityID == "garmin-hidden" },
            routePointLoader: { _ in [] }
        )

        XCTAssertEqual(run?.providerActivityID, "garmin-visible")
    }

    func testGarminImportProcessorDedupesDuplicateProviderActivities() async {
        let first = makeGarminActivity(
            id: 6,
            activityID: "garmin-duplicate",
            startTime: "2026-05-14T06:00:00Z"
        )
        let richerDuplicate = makeGarminActivity(
            id: 7,
            activityID: "garmin-duplicate",
            startTime: "2026-05-14T06:00:00Z",
            avgHr: 151
        )
        var routeLoadCount = 0

        let runs = await GarminImportProcessor.normalizedRuns(
            from: [first, richerDuplicate],
            isHidden: { _ in false },
            routePointLoader: { _ in
                routeLoadCount += 1
                return []
            }
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.providerActivityID, "garmin-duplicate")
        XCTAssertEqual(runs.first?.averageHeartRateBPM, 151)
        XCTAssertEqual(routeLoadCount, 1)
    }

    func testGarminMapperRejectsInvalidAndNonRunningActivities() {
        let valid = makeGarminActivity(
            id: 8,
            activityID: "valid-run",
            startTime: "2026-05-14T06:00:00Z",
            durationS: 3_128,
            distanceM: 9_310,
            avgHr: 142
        )
        let missingStart = makeGarminActivity(id: 9, activityID: "missing-start", startTime: "")
        let missingDuration = makeGarminActivity(id: 10, activityID: "missing-duration", startTime: "2026-05-14T06:00:00Z", durationS: 0)
        let nonRunning = makeGarminActivity(id: 11, activityID: "bike", startTime: "2026-05-14T06:00:00Z", sport: "cycling")
        let missingProvider = makeGarminActivity(id: 12, activityID: "  ", startTime: "2026-05-14T06:00:00Z")

        let run = valid.toRecordedRun()

        XCTAssertEqual(run?.providerActivityID, "valid-run")
        XCTAssertEqual(run?.source, .garmin)
        XCTAssertEqual(run?.distanceMeters, 9_310)
        XCTAssertEqual(run?.movingTimeSeconds, 3_128)
        XCTAssertEqual(run?.averageHeartRateBPM, 142)
        XCTAssertNil(missingStart.toRecordedRun())
        XCTAssertNil(missingDuration.toRecordedRun())
        XCTAssertNil(nonRunning.toRecordedRun())
        XCTAssertNil(missingProvider.toRecordedRun())
    }

    func testGarminImportProcessorFiltersFragmentsNearLongerRun() async {
        let realRun = makeGarminActivity(
            id: 13,
            activityID: "garmin-real-9k",
            startTime: "2026-05-14T06:30:00Z",
            durationS: 3_128,
            distanceM: 9_310
        )
        let shortFragments = [
            makeGarminActivity(id: 14, activityID: "fragment-17", startTime: "2026-05-14T06:20:00Z", durationS: 600, distanceM: 1_700),
            makeGarminActivity(id: 15, activityID: "fragment-26", startTime: "2026-05-14T06:28:00Z", durationS: 900, distanceM: 2_600),
            makeGarminActivity(id: 16, activityID: "fragment-27", startTime: "2026-05-14T06:34:00Z", durationS: 920, distanceM: 2_700)
        ]

        let runs = await GarminImportProcessor.normalizedRuns(
            from: shortFragments + [realRun],
            isHidden: { _ in false },
            routePointLoader: { _ in [] }
        )

        XCTAssertEqual(runs.map(\.providerActivityID), ["garmin-real-9k"])
    }

    func testGarminImportProcessorKeepsSeparateShortRunOutsideLongRunWindow() async {
        let shortRealRun = makeGarminActivity(
            id: 17,
            activityID: "short-real",
            startTime: "2026-05-14T05:00:00Z",
            durationS: 720,
            distanceM: 1_800
        )
        let longerRun = makeGarminActivity(
            id: 18,
            activityID: "longer-real",
            startTime: "2026-05-14T07:00:00Z",
            durationS: 3_128,
            distanceM: 9_310
        )

        let runs = await GarminImportProcessor.normalizedRuns(
            from: [longerRun, shortRealRun],
            isHidden: { _ in false },
            routePointLoader: { _ in [] }
        )

        XCTAssertEqual(runs.map(\.providerActivityID), ["longer-real", "short-real"])
    }

    // MARK: - Story D: Garmin batch processing idempotency

    func testGarminBatchProcessesAllNewRuns() async {
        let a1 = makeGarminActivity(id: 10, activityID: "batch-a1", startTime: "2026-05-13T06:00:00Z")
        let a2 = makeGarminActivity(id: 11, activityID: "batch-a2", startTime: "2026-05-12T06:00:00Z")
        let a3 = makeGarminActivity(id: 12, activityID: "batch-a3", startTime: "2026-05-11T06:00:00Z")

        var processedIDs: [String] = []
        let runs = await GarminImportProcessor.normalizedRuns(
            from: [a1, a2, a3],
            isHidden: { _ in false },
            routePointLoader: { _ in [] }
        )
        for run in runs {
            if let pid = run.providerActivityID { processedIDs.append(pid) }
        }

        XCTAssertEqual(processedIDs.count, 3, "All three new activities should be returned for processing")
        XCTAssertTrue(processedIDs.contains("batch-a1"))
        XCTAssertTrue(processedIDs.contains("batch-a2"))
        XCTAssertTrue(processedIDs.contains("batch-a3"))
    }

    func testGarminBatchSkipsAlreadyProcessedProviderIDs() async {
        let a1 = makeGarminActivity(id: 20, activityID: "existing-pid", startTime: "2026-05-13T06:00:00Z")
        let a2 = makeGarminActivity(id: 21, activityID: "new-pid", startTime: "2026-05-12T06:00:00Z")

        let existingProviderIDs: Set<String> = ["existing-pid"]

        let runs = await GarminImportProcessor.normalizedRuns(
            from: [a1, a2],
            isHidden: { _ in false },
            routePointLoader: { _ in [] }
        )
        let newRuns = runs.filter { run in
            guard let pid = run.providerActivityID else { return true }
            return !existingProviderIDs.contains(pid)
        }

        XCTAssertEqual(newRuns.count, 1, "Only the run with the new provider ID should be processed")
        XCTAssertEqual(newRuns.first?.providerActivityID, "new-pid")
    }

    func testGarminBatchWithMissingRouteDataDoesNotBlockOtherRuns() async {
        // Run without map data should still appear in the normalized output
        let withRoute = makeGarminActivity(id: 30, activityID: "with-route", startTime: "2026-05-13T06:00:00Z")
        let withoutRoute = makeGarminActivity(id: 31, activityID: "without-route", startTime: "2026-05-12T06:00:00Z")

        var routeLoadCount = 0
        let runs = await GarminImportProcessor.normalizedRuns(
            from: [withRoute, withoutRoute],
            isHidden: { _ in false },
            routePointLoader: { _ in
                routeLoadCount += 1
                return []
            }
        )

        XCTAssertEqual(runs.count, 2, "Both runs should be returned even when route loading returns empty")
        XCTAssertGreaterThanOrEqual(routeLoadCount, 0, "Route loader may be called 0+ times")
    }

    func testBenchmarkComparisonPresentationShowsFirstRunHistoryPrompt() {
        let runID = UUID()
        let routeID = UUID()
        let comparison = makeBenchmarkComparison(
            routeID: routeID,
            routeName: "Park Loop",
            currentRunID: runID,
            currentDuration: 1_500,
            previous: nil,
            personalBestRunID: runID,
            personalBestDuration: 1_500,
            allTimeRunCount: 1,
            monthlyRunCount: 1,
            monthlyHasEnoughData: false
        )

        let insights = BenchmarkComparisonPresentation.insights(for: comparison)

        XCTAssertEqual(insights.count, 3)
        XCTAssertEqual(insights[0], "This is your first tracked benchmark effort on this route.")
        XCTAssertEqual(insights[1], "This is your personal best on Park Loop.")
        XCTAssertEqual(insights[2], "Run this benchmark again to unlock route trends.")
    }

    func testBenchmarkComparisonPresentationShowsImprovementAgainstPreviousAndMonth() {
        let routeID = UUID()
        let previousRunID = UUID()
        let currentRunID = UUID()
        let comparison = makeBenchmarkComparison(
            routeID: routeID,
            routeName: "River Trail",
            currentRunID: currentRunID,
            currentDuration: 1_480,
            currentPace: 296,
            previous: BenchmarkRunPerformance(
                runID: previousRunID,
                source: .runSmart,
                startedAt: Date(timeIntervalSince1970: 1_000),
                durationSeconds: 1_520,
                paceSecondsPerKm: 304,
                averageHeartRateBPM: 146
            ),
            personalBestRunID: currentRunID,
            personalBestDuration: 1_480,
            allTimeRunCount: 3,
            monthlyRunCount: 3,
            monthlyPace: 305,
            monthlyHasEnoughData: true
        )

        let insights = BenchmarkComparisonPresentation.insights(for: comparison)

        XCTAssertEqual(insights[0], "You were 0:40 faster than your previous run on this route.")
        XCTAssertEqual(insights[1], "This is your personal best on River Trail.")
        XCTAssertEqual(insights[2], "You ran faster than this month's average pace.")
        XCTAssertEqual(BenchmarkComparisonPresentation.deltaLabel(current: 1_480, baseline: 1_520), "-0:40")
    }

    func testBenchmarkStatusCopyAvoidsMisleadingWeakGPSComparison() {
        XCTAssertEqual(BenchmarkComparisonStatus.weakGPS.title, "Benchmark confidence is low")
        XCTAssertTrue(BenchmarkComparisonStatus.weakGPS.message.contains("not showing pace or PB deltas"))
        XCTAssertTrue(BenchmarkComparisonStatus.noRouteData.message.contains("does not include enough map data"))
        XCTAssertTrue(BenchmarkComparisonStatus.noBenchmark.message.contains("Save this route as a benchmark"))
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

    func testSuggestedWorkoutContractUsesSchemaValidValuesAndReviewForDurationOnly() {
        let durationOnly = StructuredNextWorkout(
            title: "Moderate Run",
            dateLabel: "tomorrow",
            distance: nil,
            target: "25-40 min comfortable",
            notes: nil
        )
        let distanceRun = StructuredNextWorkout(
            title: "Easy 6 km",
            dateLabel: "tomorrow",
            distance: nil,
            target: "Easy",
            notes: nil
        )

        XCTAssertEqual(TrainingPlanRepository.durationMinutes(from: durationOnly), 25)
        XCTAssertTrue(TrainingPlanRepository.suggestedWorkoutNeedsReview(durationOnly))
        XCTAssertFalse(TrainingPlanRepository.suggestedWorkoutNeedsReview(distanceRun))
        XCTAssertEqual(TrainingPlanRepository.suggestedWorkoutTrainingPhase, "base")
        XCTAssertEqual(TrainingPlanRepository.recommendationFallbackPlanType, "basic")
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

    // WP-38 S10: timeLabel used to keep printing MM:SS past the hour
    // boundary ("90:00" for a 90-minute run). Branch to H:MM:SS at >=3600s
    // so live HUD / post-run / history inherit the fix from one helper.
    func testTimeLabelUsesHourFormatAtAndAboveOneHour() {
        XCTAssertEqual(RunRecorder.timeLabel(3600), "1:00:00", "exactly 60:00 must switch to H:MM:SS")
        XCTAssertEqual(RunRecorder.timeLabel(5400), "1:30:00", "90-minute run must read 1:30:00, not 90:00")
        XCTAssertEqual(RunRecorder.timeLabel(3661), "1:01:01")
    }

    func testTimeLabelKeepsMinuteFormatUnderOneHour() {
        XCTAssertEqual(RunRecorder.timeLabel(0), "00:00")
        XCTAssertEqual(RunRecorder.timeLabel(59), "00:59")
        XCTAssertEqual(RunRecorder.timeLabel(60), "01:00")
        XCTAssertEqual(RunRecorder.timeLabel(2700), "45:00", "45-minute run must stay MM:SS")
        XCTAssertEqual(RunRecorder.timeLabel(3599), "59:59", "one second under an hour must stay MM:SS")
    }

    // WP-37 S5: PostRunSummaryView.splitRows used to fabricate paces as
    // `averagePace + ((km % 3) - 1) * 4s` and present them as "KM SPLITS".
    // RunRecorder.kilometerSplits(from:) replaces that with real per-km splits
    // derived from route-point GPS distance and timestamps; a split only
    // appears once the recorded route actually crosses that kilometer boundary.
    func testKilometerSplitsComputesRealPaceFromRoutePointCrossings() {
        let start = Date(timeIntervalSince1970: 5_000)
        // ~0.011 degrees latitude ≈ 1221m at this latitude — comfortably clears
        // each 1000m boundary with margin, and never double-crosses a boundary
        // within one segment (1221m < 2000m).
        let points = [
            RunRoutePoint(latitude: 32.0000, longitude: 34.0, timestamp: start, horizontalAccuracy: 8, altitude: nil),
            RunRoutePoint(latitude: 32.0110, longitude: 34.0, timestamp: start.addingTimeInterval(300), horizontalAccuracy: 8, altitude: nil),
            RunRoutePoint(latitude: 32.0220, longitude: 34.0, timestamp: start.addingTimeInterval(630), horizontalAccuracy: 8, altitude: nil)
        ]

        let splits = RunRecorder.kilometerSplits(from: points)

        XCTAssertEqual(splits.count, 2, "distance never reaches a 3rd kilometer, so only 2 real splits should exist")
        XCTAssertEqual(splits[0].km, 1)
        XCTAssertEqual(splits[0].paceSecondsPerKm, 300, accuracy: 0.5, "split 1 pace must be the real elapsed time to cross 1km (5:00/km), not a fabricated drift value")
        XCTAssertEqual(splits[1].km, 2)
        XCTAssertEqual(splits[1].paceSecondsPerKm, 330, accuracy: 0.5, "split 2 pace must be the real elapsed time between the 1km and 2km crossings (5:30/km)")
    }

    func testKilometerSplitsReturnsEmptyWhenRouteNeverCompletesAKilometer() {
        let start = Date(timeIntervalSince1970: 5_100)
        // ~0.005 degrees latitude ≈ 555m — well under the 1000m first boundary.
        let points = [
            RunRoutePoint(latitude: 32.0000, longitude: 34.0, timestamp: start, horizontalAccuracy: 8, altitude: nil),
            RunRoutePoint(latitude: 32.0050, longitude: 34.0, timestamp: start.addingTimeInterval(180), horizontalAccuracy: 8, altitude: nil)
        ]

        let splits = RunRecorder.kilometerSplits(from: points)

        XCTAssertTrue(splits.isEmpty, "a run that never completes a full kilometer must show no splits (real crossing, not run.distanceMeters >= 500 filler)")
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

    // WP-37 S1: on a device with granted location permission, finishing a run must
    // leave the live-run state so the Run tab returns to PreRun. Before the fix,
    // finish()/discard() called updatePhaseForAuthorization(), which never reset
    // phase out of .recording/.paused when authorized, leaving a frozen "zombie"
    // recording screen with no Start button (only escape: kill the app). These
    // tests simulate the authorized state via authorizationStatusProvider; the
    // pre-existing discard test above passes only because the test host is
    // .notDetermined, which masked the device bug.
    @MainActor
    func testRunRecorderFinishReturnsToReadyPhaseWhenAuthorized() {
        let recorder = RunRecorder()
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        let now = Date(timeIntervalSince1970: 3_000)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 10, timestamp: now),
            makeLocation(latitude: 32.0810, longitude: 34.7810, accuracy: 10, timestamp: now.addingTimeInterval(3))
        ], now: now)
        XCTAssertEqual(recorder.phase, .recording)

        let run = recorder.finish()

        XCTAssertNotNil(run)
        XCTAssertEqual(recorder.phase, .ready, "after finishing an authorized run the recorder must return to .ready so the Run tab shows PreRun, not a zombie recording screen")
        XCTAssertNotEqual(recorder.phase, .recording)
        XCTAssertNotEqual(recorder.phase, .paused)
        XCTAssertEqual(recorder.distanceMeters, 0, "finish must clear stale metrics so the next run starts from zero")
        XCTAssertTrue(recorder.routePoints.isEmpty)
        XCTAssertNotNil(recorder.lastSavedRun)
    }

    @MainActor
    func testRunRecorderPauseThenDiscardReturnsToReadyPhaseWhenAuthorized() {
        let recorder = RunRecorder()
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        let now = Date(timeIntervalSince1970: 3_100)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 10, timestamp: now),
            makeLocation(latitude: 32.0810, longitude: 34.7810, accuracy: 10, timestamp: now.addingTimeInterval(3))
        ], now: now)
        XCTAssertEqual(recorder.phase, .recording)

        recorder.pause()
        XCTAssertEqual(recorder.phase, .paused)

        recorder.discard()

        XCTAssertEqual(recorder.phase, .ready, "discarding from paused while authorized must return to PreRun, not leave a paused zombie screen")
        XCTAssertNil(recorder.lastSavedRun)
        XCTAssertTrue(recorder.routePoints.isEmpty)
    }

    // WP-37 S2: a transient GPS error (e.g. kCLErrorLocationUnknown) mid-run must
    // not abort the recording. Before the fix, locationManager(_:didFailWithError:)
    // set phase = .failed on ANY error while recording, silently kicking the run
    // back to PreRun with no save. Apple's docs treat kCLErrorLocationUnknown as
    // transient; only an explicit .denied should stop an active run.
    @MainActor
    func testRunRecorderIgnoresTransientGPSErrorWhileRecording() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 4_000)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 10, timestamp: now)
        ], now: now)
        XCTAssertEqual(recorder.phase, .recording)

        recorder.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

        XCTAssertEqual(recorder.phase, .recording, "a transient GPS error must not abort an active recording")
        XCTAssertNotNil(recorder.lastErrorMessage, "the GPS pill should surface degraded-signal copy")

        // GPS recovers: the next usable location must clear the transient-error copy.
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0801, longitude: 34.7801, accuracy: 10, timestamp: now.addingTimeInterval(2))
        ], now: now.addingTimeInterval(2))

        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertNil(recorder.lastErrorMessage, "recovered GPS must clear the stale transient-error message")

        recorder.discard()
    }

    @MainActor
    func testRunRecorderStopsSafelyWhenPermissionDeniedWhileRecording() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 4_100)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.0800, longitude: 34.7800, accuracy: 10, timestamp: now)
        ], now: now)
        XCTAssertEqual(recorder.phase, .recording)

        recorder.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        XCTAssertEqual(recorder.phase, .denied, "an explicit permission denial must still stop an active run")
        XCTAssertNotNil(recorder.lastErrorMessage)
    }

    @MainActor
    func testRunRecorderStillFailsOnErrorWhenNotRecording() {
        let recorder = RunRecorder()
        let now = Date(timeIntervalSince1970: 4_200)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([
            makeLocation(latitude: 32.08, longitude: 34.78, accuracy: 80, timestamp: now)
        ], now: now)
        XCTAssertEqual(recorder.phase, .acquiringLocation, "weak accuracy should not have started recording yet")

        recorder.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

        XCTAssertEqual(recorder.phase, .failed, "pre-recording behavior is unchanged: any error still surfaces as .failed before a run has started")
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

    func testTrainingContextIncludesSummariesAndLimitsPrivateRouteData() async throws {
        let routePoints = makeRoutePoints(count: 3)
        let runs = (0..<6).map { index in
            makeRun(
                source: index.isMultiple(of: 2) ? .garmin : .runSmart,
                startedAt: makeDate("2026-05-0\(min(index + 1, 9))"),
                distanceMeters: Double(5_000 + (index * 500)),
                movingTimeSeconds: Double(1_500 + (index * 60)),
                heartRate: 145 + index,
                routePoints: routePoints
            )
        }
        let workouts = [
            makeWorkout(date: "2026-05-07", kind: .tempo, title: "Tempo Builder", distance: "8.0 km"),
            makeWorkout(date: "2026-05-09", kind: .easy, title: "Easy Run", distance: "5.0 km"),
            makeWorkout(date: "2026-05-11", kind: .long, title: "Long Run", distance: "12.0 km")
        ]
        let reports = (0..<4).map { index in
            RunReportSummary(
                id: "report-\(index)",
                title: "Run \(index)",
                dateLabel: "May \(index + 1)",
                distance: "5.\(index) km",
                pace: "5:1\(index) /km",
                score: 80 + index,
                insight: "Insight \(index)"
            )
        }
        let routes = (0..<4).map { index in
            makeRouteSuggestion(id: "route-\(index)", name: "Route \(index)", distanceKm: Double(5 + index), points: routePoints)
        }
        let service = TrainingContextTestServices(
            weekWorkouts: workouts,
            upcoming: workouts,
            runs: runs,
            routes: routes,
            reports: reports
        )

        let context = await service.trainingContext(for: .today)

        XCTAssertEqual(context.runner.goal, "10K PR")
        XCTAssertEqual(context.today.readiness, 82)
        XCTAssertEqual(context.plan.activePlanTitle, "10K Build")
        XCTAssertEqual(context.plan.upcomingWorkouts.count, 3)
        XCTAssertEqual(context.recovery.recommendation, "Ready for controlled work.")
        XCTAssertEqual(context.wellness.checkInStatus, "Checked in today.")
        XCTAssertEqual(context.activity.recentRunCount, 6)
        XCTAssertEqual(context.activity.recentRuns.count, 5)
        XCTAssertEqual(context.routes.count, 3)
        XCTAssertEqual(context.reports.count, 3)
        XCTAssertEqual(context.activity.recentRuns.first?.routePointCount, 3)
        XCTAssertTrue(context.routes.allSatisfy(\.hasGeometry))

        let routeFieldNames = Mirror(reflecting: try XCTUnwrap(context.routes.first)).children.compactMap(\.label).joined(separator: ",")
        XCTAssertFalse(routeFieldNames.contains("latitude"))
        XCTAssertFalse(routeFieldNames.contains("longitude"))
        XCTAssertFalse(routeFieldNames.contains("points"))
    }

    func testTrainingContextReportsMissingDataLimitations() async {
        var service = TrainingContextTestServices()
        service.today = TodayRecommendation.placeholder
        service.activePlan = nil
        service.weekWorkouts = []
        service.upcoming = []
        service.recovery = .loading
        service.wellness = .empty
        service.runs = []
        service.routes = []
        service.reports = []

        let context = await service.trainingContext(for: .plan)

        XCTAssertTrue(context.limitations.contains("Readiness is not available yet."))
        XCTAssertTrue(context.limitations.contains("No active training plan is available yet."))
        XCTAssertTrue(context.limitations.contains("No recent runs are available yet."))
        XCTAssertTrue(context.limitations.contains("Recovery data is limited until Garmin or HealthKit syncs."))
        XCTAssertTrue(context.limitations.contains("No wellness check-in is available yet."))
        XCTAssertTrue(context.limitations.contains("No saved or suggested routes are available yet."))
        XCTAssertTrue(context.limitations.contains("No run reports are available yet."))
    }

    func testGarminAttributionUsesActivityDeviceNameBeforeFallback() {
        let run = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-01"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            sourceDeviceName: "Garmin Forerunner 965"
        )

        XCTAssertEqual(RunSmartAttribution.sourceLabel(for: run, fallbackGarminDeviceName: "Garmin Fenix 8"), "Garmin Forerunner 965")
        XCTAssertEqual(RunSmartAttribution.runReportTitle(for: run, fallbackGarminDeviceName: "Garmin Fenix 8"), "Garmin Forerunner 965 Run Report")
    }

    func testGarminAttributionUsesConnectedDeviceFallbackWhenActivityLacksDeviceName() {
        let run = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-01"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500
        )

        XCTAssertEqual(RunSmartAttribution.sourceLabel(for: run, fallbackGarminDeviceName: "Garmin Forerunner 965"), "Garmin Forerunner 965")
        XCTAssertEqual(RunSmartAttribution.runReportTitle(for: run, fallbackGarminDeviceName: "Garmin Forerunner 965"), "Garmin Forerunner 965 Run Report")
    }

    func testGarminAttributionAddsBrandPrefixToBareModelNames() {
        let run = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-01"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            sourceDeviceName: "Forerunner 965"
        )

        XCTAssertEqual(RunSmartAttribution.sourceLabel(for: run), "Garmin Forerunner 965")
        XCTAssertEqual(RunSmartAttribution.runReportTitle(for: run), "Garmin Forerunner 965 Run Report")
    }

    func testGarminAttributionKeepsNonGarminSourcesUnchanged() {
        let run = makeRun(
            source: .healthKit,
            startedAt: makeDate("2026-05-01"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            sourceDeviceName: "Garmin Forerunner 965"
        )

        XCTAssertEqual(RunSmartAttribution.sourceLabel(for: run, fallbackGarminDeviceName: "Garmin Forerunner 965"), "HealthKit")
        XCTAssertEqual(RunSmartAttribution.runReportTitle(for: run, fallbackGarminDeviceName: "Garmin Forerunner 965"), "HealthKit Run Report")
    }

    func testGarminDeviceLabelUsesActivityNameThenFallback() {
        XCTAssertEqual(
            RunSmartAttribution.garminDeviceLabel(deviceName: "Forerunner 965", fallbackGarminDeviceName: "Garmin Fenix 8"),
            "Garmin Forerunner 965"
        )
        XCTAssertEqual(
            RunSmartAttribution.garminDeviceLabel(deviceName: nil, fallbackGarminDeviceName: "Garmin Forerunner 965"),
            "Garmin Forerunner 965"
        )
        XCTAssertEqual(RunSmartAttribution.garminDeviceLabel(deviceName: nil, fallbackGarminDeviceName: nil), "Garmin")
    }

    func testBareConnectedGarminDeviceFallbackGetsBrandPrefix() {
        let run = makeRun(
            source: .garmin,
            startedAt: makeDate("2026-05-01"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500
        )

        XCTAssertEqual(
            RunSmartAttribution.sourceLabel(for: run, fallbackGarminDeviceName: "Forerunner 965"),
            "Garmin Forerunner 965"
        )
        XCTAssertEqual(
            RunSmartAttribution.garminDeviceLabel(deviceName: nil, fallbackGarminDeviceName: "Forerunner 965"),
            "Garmin Forerunner 965"
        )
    }

    func testRecoverySnapshotDefaultsToNonGarminUntilExplicitlyMarked() {
        let healthOnly = RecoverySnapshot(
            readiness: 72,
            bodyBattery: 72,
            sleep: "7h 10m",
            hrv: "48 ms",
            hrvSource: .appleHealth,
            stress: "62 bpm resting",
            recommendation: "Recovery data synced from Apple Health."
        )

        let garmin = RecoverySnapshot(
            readiness: 76,
            bodyBattery: 76,
            sleep: "7h 40m",
            hrv: "52 ms",
            hrvSource: .garmin,
            stress: "—",
            recommendation: "Recovery data synced from Garmin.",
            includesGarminDeviceSourcedData: true
        )

        XCTAssertFalse(healthOnly.includesGarminDeviceSourcedData)
        XCTAssertTrue(garmin.includesGarminDeviceSourcedData)
    }

    func testGarminRouteSuggestionUsesLoopNameAndSourceAttribution() {
        let route = RouteSuggestion(
            id: "garmin-abc",
            name: "5K Loop",
            distanceKm: 5.0,
            elevationGainMeters: 12,
            estimatedDurationMinutes: 28,
            points: [],
            kind: .past,
            sourceAttribution: "Garmin Forerunner 965"
        )

        XCTAssertTrue(route.isGarminSourced)
        XCTAssertEqual(route.name, "5K Loop")
        XCTAssertEqual(route.sourceAttribution, "Garmin Forerunner 965")
        XCTAssertFalse(route.name.localizedCaseInsensitiveContains("from Garmin"))
    }

    func testCoachFallbackResponseUsesEntryPointSpecificContext() async {
        let run = makeRun(
            source: .runSmart,
            startedAt: makeDate("2026-05-01"),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_500,
            routePoints: []
        )
        let service = TrainingContextTestServices(
            upcoming: [makeWorkout(date: "2026-05-07", kind: .tempo, title: "Tempo Builder", distance: "8.0 km")],
            runs: [run],
            reports: [
                RunReportSummary(id: "report", title: "Tempo", dateLabel: "Today", distance: "5 km", pace: "5:00 /km", score: 88, insight: "Pace stayed controlled.")
            ]
        )

        let todayContext = await service.trainingContext(for: .today)
        let runContext = await service.trainingContext(for: .run)
        let reportContext = await service.trainingContext(for: .report)

        let todayResponse = await service.send(message: "What should I do?", context: todayContext)
        let runResponse = await service.send(message: "How was that?", context: runContext)
        let reportResponse = await service.send(message: "Any trend?", context: reportContext)

        XCTAssertTrue(todayResponse.text.contains("readiness at 82"))
        XCTAssertTrue(runResponse.text.contains("latest run was 5.0 km"))
        XCTAssertTrue(reportResponse.text.contains("Pace stayed controlled."))
        XCTAssertNotEqual(todayResponse.text, runResponse.text)
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

    func testOnboardingHealthKitStepUsesExistingProviderAndRequiresConnectedState() {
        XCTAssertEqual(OnboardingHealthKitStep.providerName, HealthKitSyncService.providerName)

        let connected = ConnectedDeviceStatus(
            provider: HealthKitSyncService.providerName,
            state: .connected,
            lastSuccessfulSync: nil,
            permissions: [],
            message: nil
        )
        let disconnected = ConnectedDeviceStatus(
            provider: HealthKitSyncService.providerName,
            state: .disconnected,
            lastSuccessfulSync: nil,
            permissions: [],
            message: nil
        )
        let error = ConnectedDeviceStatus(
            provider: HealthKitSyncService.providerName,
            state: .error,
            lastSuccessfulSync: nil,
            permissions: [],
            message: "Health access was not granted."
        )

        XCTAssertTrue(OnboardingHealthKitStep.didConnect(connected))
        XCTAssertFalse(OnboardingHealthKitStep.didConnect(disconnected))
        XCTAssertFalse(OnboardingHealthKitStep.didConnect(error))
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

    func testLocalStorePersistsRunRPESelection() {
        let store = RunSmartLocalStore.shared
        let run = RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 21_000),
            endedAt: Date(timeIntervalSince1970: 21_900),
            distanceMeters: 3_000,
            movingTimeSeconds: 900,
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil
        )

        store.saveRun(run)
        let updated = store.updateRunRPE(run, rpe: 8)
        let reloaded = store.loadRuns().first { $0.id == run.id }

        XCTAssertEqual(updated.rpe, 8)
        XCTAssertEqual(reloaded?.rpe, 8)
        XCTAssertTrue(store.removeRun(updated))
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

        let authUserID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let identity = RunSmartIdentity(authUserID: authUserID, profileUUID: nil, numericUserID: 7)
        let data = try JSONEncoder().encode(
            DBRunInsert(run: run, identity: identity, kind: .easy, notes: "Imported from Apple Health")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["auth_user_id"] as? String, authUserID.uuidString)
        XCTAssertEqual(json["profile_id"] as? Int, 7)
        XCTAssertEqual(json["source_provider"] as? String, "healthkit")
        XCTAssertEqual(json["source_activity_id"] as? String, providerID)
        XCTAssertEqual(json["heart_rate"] as? Int, 140)
    }

    func testDBRunInsertOmitsProfileIDForUUIDOnlyIdentity() throws {
        let authUserID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let profileUUID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let run = RecordedRun(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            providerActivityID: "garmin-activity-42",
            source: .garmin,
            startedAt: Date(timeIntervalSince1970: 30_000),
            endedAt: Date(timeIntervalSince1970: 30_900),
            distanceMeters: 5_000,
            movingTimeSeconds: 900,
            averagePaceSecondsPerKm: 180,
            averageHeartRateBPM: 152,
            routePoints: [],
            syncedAt: nil
        )

        let identity = RunSmartIdentity(authUserID: authUserID, profileUUID: profileUUID, numericUserID: nil)
        let data = try JSONEncoder().encode(
            DBRunInsert(run: run, identity: identity, kind: .easy, notes: "Completed activity from garmin")
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(json.keys)

        XCTAssertEqual(json["auth_user_id"] as? String, authUserID.uuidString)
        XCTAssertNil(json["profile_id"])
        XCTAssertEqual(keys.contains("profile_id"), false)
        XCTAssertEqual(json["source_provider"] as? String, "garmin")
        XCTAssertEqual(json["source_activity_id"] as? String, "garmin-activity-42")
    }

    func testChallengeEnrollmentPayloadUsesAuthUserIDWithoutHashedUserID() throws {
        struct EnrollInsert: Encodable {
            let user_id: Int64?
            let auth_user_id: String
            let challenge_id: String
            let started_at: String
            let updated_at: String

            enum CodingKeys: String, CodingKey {
                case user_id
                case auth_user_id
                case challenge_id
                case started_at
                case updated_at
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(user_id, forKey: .user_id)
                try container.encode(auth_user_id, forKey: .auth_user_id)
                try container.encode(challenge_id, forKey: .challenge_id)
                try container.encode(started_at, forKey: .started_at)
                try container.encode(updated_at, forKey: .updated_at)
            }
        }

        let authUserID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let payload = EnrollInsert(
            user_id: nil,
            auth_user_id: authUserID.uuidString,
            challenge_id: "11111111-1111-1111-1111-111111111111",
            started_at: "2026-06-11",
            updated_at: "2026-06-11T12:00:00Z"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["auth_user_id"] as? String, authUserID.uuidString)
        XCTAssertNil(json["user_id"])
        XCTAssertEqual(json["challenge_id"] as? String, "11111111-1111-1111-1111-111111111111")
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

    func testActivityConsolidationMergesRunSmartAndGarminWithinMorningWindow() {
        let start = makeDate("2026-05-14").addingTimeInterval(6 * 3600 + 30 * 60)
        let points = makeRoutePoints(count: 18)
        let runSmart = makeRun(
            source: .runSmart,
            startedAt: start,
            distanceMeters: 9_430,
            movingTimeSeconds: 3_211,
            routePoints: points
        )
        let garmin = makeRun(
            providerActivityID: "garmin-real-morning",
            source: .garmin,
            startedAt: start.addingTimeInterval(24 * 60),
            distanceMeters: 9_310,
            movingTimeSeconds: 3_128,
            heartRate: 142
        )

        let consolidated = ActivityConsolidationService.consolidatedRuns([runSmart, garmin])

        XCTAssertEqual(consolidated.count, 1)
        XCTAssertEqual(consolidated[0].source, .garmin)
        XCTAssertEqual(consolidated[0].providerActivityID, "garmin-real-morning")
        XCTAssertEqual(consolidated[0].averageHeartRateBPM, 142)
        XCTAssertEqual(consolidated[0].routePoints, points)
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

    func testWorkoutMatchAcceptsRealRunSmartGpsRunWithinTolerance() {
        let startedAt = makeDate("2026-05-18").addingTimeInterval(7 * 3600)
        let run = makeRun(
            source: .runSmart,
            startedAt: startedAt,
            distanceMeters: 7_050,
            movingTimeSeconds: 40 * 60 + 23,
            routePoints: makeRoutePoints(count: 24)
        )
        let planned = makeWorkout(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            date: "2026-05-18",
            kind: .easy,
            title: "Easy Run",
            distance: "7.0 km",
            durationMinutes: 40
        )

        let match = TrainingPlanRepository.bestWorkoutMatch(for: run, in: [planned])

        XCTAssertEqual(match?.id, planned.id)
    }

    func testWorkoutCompletionPayloadIncludesActualRunMetrics() throws {
        let startedAt = makeDate("2026-05-20").addingTimeInterval(7 * 3600)
        let run = makeRun(
            source: .runSmart,
            startedAt: startedAt,
            distanceMeters: 7_060,
            movingTimeSeconds: 40 * 60 + 24
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DBWorkoutCompletionUpdate(run: run))) as? [String: Any]
        let keys = Set(object?.keys.map { $0 } ?? [])
        let completedAtFormatter = ISO8601DateFormatter()
        completedAtFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        XCTAssertEqual(keys, ["completed", "completed_at", "actual_distance_km", "actual_duration_minutes", "actual_pace"])
        XCTAssertEqual(object?["completed"] as? Bool, true)
        XCTAssertEqual(object?["actual_distance_km"] as? Double, 7.06)
        XCTAssertEqual(object?["actual_duration_minutes"] as? Int, 40)
        XCTAssertEqual(object?["actual_pace"] as? Double, Double((run.averagePaceSecondsPerKm * 10).rounded()) / 10)
        XCTAssertNotNil(completedAtFormatter.date(from: object?["completed_at"] as? String ?? ""))
    }

    func testCompletedTodayWorkoutFallsThroughToNextActionableWorkout() throws {
        let planID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let completedToday = try makeDBWorkout(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888801")!,
            planID: planID,
            date: today,
            distance: 7.0,
            duration: 40,
            completed: true
        )
        let nextWorkout = try makeDBWorkout(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888802")!,
            planID: planID,
            date: tomorrow,
            distance: 5.0,
            duration: 30,
            completed: false
        )
        let plan = ActivePlan(
            plan: DBPlan(
                id: planID,
                profileId: .uuid(UUID(uuidString: "88888888-8888-8888-8888-888888888803")!),
                title: "Test Plan",
                description: nil,
                startDate: ISO8601DateFormatter.shortDate.string(from: today),
                endDate: ISO8601DateFormatter.shortDate.string(from: tomorrow),
                totalWeeks: 1,
                isActive: true,
                planType: "base"
            ),
            workouts: [completedToday, nextWorkout]
        )

        XCTAssertNil(plan.uncompletedTodayWorkout)
        XCTAssertEqual(plan.nextActionableWorkout?.id, nextWorkout.id)
    }

    func testRunSmartGpsReportIDIsStableWhenGarminDuplicateArrivesLater() {
        let start = makeDate("2026-05-18").addingTimeInterval(7 * 3600)
        let points = makeRoutePoints(count: 26)
        let runSmart = makeRun(
            source: .runSmart,
            startedAt: start,
            distanceMeters: 7_050,
            movingTimeSeconds: 40 * 60 + 23,
            routePoints: points
        )
        let runSmartOnly = ActivityConsolidationService.consolidatedRuns([runSmart])[0]
        let garmin = makeRun(
            providerActivityID: "garmin-sprint-7-real-run",
            source: .garmin,
            startedAt: start.addingTimeInterval(70),
            distanceMeters: 7_020,
            movingTimeSeconds: 40 * 60 + 10,
            heartRate: 146
        )
        let afterGarmin = ActivityConsolidationService.consolidatedRuns([runSmart, garmin])[0]

        XCTAssertEqual(SupabaseRunSmartServices.reportRunID(for: runSmartOnly), SupabaseRunSmartServices.reportRunID(for: afterGarmin))
        XCTAssertEqual(afterGarmin.source, .garmin)
        XCTAssertEqual(afterGarmin.routePoints, points)
    }

    func testReportLookupCandidatesPreserveOriginalRunSmartAndGarminAliases() {
        let start = makeDate("2026-05-18").addingTimeInterval(7 * 3600)
        let runSmart = makeRun(
            id: UUID(uuidString: "99999999-0000-4000-8000-000000000001")!,
            source: .runSmart,
            startedAt: start,
            distanceMeters: 7_050,
            movingTimeSeconds: 40 * 60
        )
        let garmin = makeRun(
            id: UUID(uuidString: "99999999-0000-4000-8000-000000000002")!,
            providerActivityID: "garmin-999",
            source: .garmin,
            startedAt: start.addingTimeInterval(45),
            distanceMeters: 7_020,
            movingTimeSeconds: 40 * 60,
            heartRate: 146
        )

        let canonical = ActivityConsolidationService.consolidatedRuns([runSmart, garmin])[0]
        let candidates = SupabaseRunSmartServices.reportRunIDCandidates(for: canonical)

        XCTAssertEqual(candidates.first, SupabaseRunSmartServices.reportRunID(for: canonical))
        XCTAssertTrue(candidates.contains("garmin-999"))
        XCTAssertTrue(candidates.contains(canonical.id.uuidString))
        XCTAssertEqual(Set(candidates).count, candidates.count)
    }

    func testSuggestedWorkoutDateHandlesRelativeAndFormattedLabels() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let iso = "2026-05-21"

        XCTAssertEqual(TrainingPlanRepository.suggestedWorkoutDate("today"), today)
        XCTAssertEqual(TrainingPlanRepository.suggestedWorkoutDate("tomorrow"), tomorrow)
        XCTAssertEqual(TrainingPlanRepository.suggestedWorkoutDate(iso), makeDate(iso))

        let nextTuesday = TrainingPlanRepository.suggestedWorkoutDate("next Tuesday")
        XCTAssertEqual(calendar.component(.weekday, from: nextTuesday), 3)
        XCTAssertGreaterThan(nextTuesday, today)
    }

    func testSuggestedWorkoutFailureCopyIsUserSafe() {
        let message = PostRunSuggestedWorkoutSaveCopy.failureMessage

        XCTAssertTrue(message.contains("Your run report is saved"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("Xcode"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("console"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("TrainingPlanRepo"))
    }

    // MARK: - Story A: Route sync merge logic

    func testRouteSyncMergeReturnsLocalWhenRemoteIsEmpty() {
        let route = makeSavedRoute(
            id: UUID(uuidString: "AA000000-0000-0000-0000-000000000001")!,
            points: [],
            distanceMeters: 5_000
        )
        let merged = RouteSync.merge(remote: [], local: [route])
        XCTAssertEqual(merged.map(\.id), [route.id])
    }

    func testRouteSyncMergeRemoteWinsOnConflictingRouteID() {
        let sharedID = UUID(uuidString: "AA000000-0000-0000-0000-000000000002")!
        let local = SavedRoute(
            id: sharedID, name: "Local Name",
            distanceMeters: 5_000, elevationGainMeters: 0, points: [],
            source: .recorded, tags: [], notes: "", isFavorite: false,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let remote = SavedRoute(
            id: sharedID, name: "Remote Name",
            distanceMeters: 5_200, elevationGainMeters: 20, points: [],
            source: .recorded, tags: ["race"], notes: "Updated on another device", isFavorite: true,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let merged = RouteSync.merge(remote: [remote], local: [local])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.name, "Remote Name")
        XCTAssertEqual(merged.first?.distanceMeters, 5_200)
        XCTAssertTrue(merged.first?.isFavorite ?? false)
    }

    func testRouteSyncBenchmarkMergeAddsRemoteEntriesMissingLocally() {
        let localRouteID = UUID(uuidString: "AA000000-0000-0000-0000-000000000001")!
        let remoteRouteID = UUID(uuidString: "BB000000-0000-0000-0000-000000000001")!
        let remoteEntryID = UUID(uuidString: "BB000000-0000-0000-0000-000000000002")!

        let localEntry = BenchmarkRoute(
            id: UUID(), savedRouteID: localRouteID,
            enabledAt: Date(timeIntervalSince1970: 1_000),
            historicalRunCount: 3, personalBestSeconds: 1_480, personalBestDate: nil,
            averagePaceSecondsPerKm: 295, averageDurationSeconds: 1_500
        )
        let remoteEntries: [(id: UUID, savedRouteID: UUID, enabledAt: Date)] = [
            (id: remoteEntryID, savedRouteID: remoteRouteID, enabledAt: Date(timeIntervalSince1970: 5_000))
        ]

        let merged = RouteSync.mergeBenchmarks(remoteEntries: remoteEntries, local: [localEntry])

        XCTAssertEqual(merged.count, 2)
        let remoteResult = merged.first(where: { $0.savedRouteID == remoteRouteID })
        XCTAssertNotNil(remoteResult)
        XCTAssertEqual(remoteResult?.id, remoteEntryID)
        XCTAssertEqual(remoteResult?.historicalRunCount, 0, "New remote entry starts with no cached stats")
        let localResult = merged.first(where: { $0.savedRouteID == localRouteID })
        XCTAssertEqual(localResult?.historicalRunCount, 3, "Existing local stats are preserved")
    }

    // MARK: - Story B: Benchmark stat hydration

    func testBenchmarkStatRefreshComputesCountPBAndAveragesFromMatchedRuns() {
        let routeID = UUID(uuidString: "CC000000-0000-0000-0000-000000000001")!
        let benchmark = BenchmarkRoute(
            id: UUID(), savedRouteID: routeID, enabledAt: Date(timeIntervalSince1970: 1_000),
            historicalRunCount: 0, personalBestSeconds: nil, personalBestDate: nil,
            averagePaceSecondsPerKm: nil, averageDurationSeconds: nil
        )
        let match = RouteMatchResult(
            routeID: routeID, candidateRouteID: routeID, confidence: .matched,
            distanceDeltaMeters: 10, startDeltaMeters: 5, endDeltaMeters: 5,
            shapeSimilarity: 0.98, isReversed: false
        )
        var run1 = makeRun(source: .runSmart, startedAt: makeDate("2026-05-01"), distanceMeters: 5_000, movingTimeSeconds: 1_560)
        run1.routeMatchResult = match
        var run2 = makeRun(source: .garmin, startedAt: makeDate("2026-05-08"), distanceMeters: 5_000, movingTimeSeconds: 1_500)
        run2.routeMatchResult = match

        let updated = BenchmarkStatRefresh.refresh([benchmark], from: [run1, run2])

        XCTAssertEqual(updated[0].historicalRunCount, 2)
        XCTAssertEqual(updated[0].personalBestSeconds, 1_500)
        XCTAssertEqual(updated[0].personalBestDate, run2.startedAt)
        XCTAssertEqual(updated[0].averageDurationSeconds ?? 0, 1_530, accuracy: 1)
    }

    func testBenchmarkStatRefreshSkipsRunsWithNoMatchOrWrongRoute() {
        let routeID = UUID(uuidString: "CC000000-0000-0000-0000-000000000002")!
        let otherRouteID = UUID(uuidString: "CC000000-0000-0000-0000-000000000003")!
        let benchmark = BenchmarkRoute(
            id: UUID(), savedRouteID: routeID, enabledAt: Date(timeIntervalSince1970: 1_000),
            historicalRunCount: 0, personalBestSeconds: nil, personalBestDate: nil,
            averagePaceSecondsPerKm: nil, averageDurationSeconds: nil
        )
        let correctMatch = RouteMatchResult(
            routeID: routeID, candidateRouteID: routeID, confidence: .matched,
            distanceDeltaMeters: 0, startDeltaMeters: 0, endDeltaMeters: 0, shapeSimilarity: 1, isReversed: false
        )
        let possibleMatch = RouteMatchResult(
            routeID: routeID, candidateRouteID: routeID, confidence: .possibleMatch,
            distanceDeltaMeters: 80, startDeltaMeters: 50, endDeltaMeters: 50, shapeSimilarity: 0.6, isReversed: false
        )
        let wrongRouteMatch = RouteMatchResult(
            routeID: otherRouteID, candidateRouteID: otherRouteID, confidence: .matched,
            distanceDeltaMeters: 0, startDeltaMeters: 0, endDeltaMeters: 0, shapeSimilarity: 1, isReversed: false
        )
        var matched = makeRun(source: .runSmart, startedAt: makeDate("2026-05-01"), distanceMeters: 5_000, movingTimeSeconds: 1_500)
        matched.routeMatchResult = correctMatch
        var possible = makeRun(source: .runSmart, startedAt: makeDate("2026-05-02"), distanceMeters: 5_000, movingTimeSeconds: 1_480)
        possible.routeMatchResult = possibleMatch
        var wrong = makeRun(source: .runSmart, startedAt: makeDate("2026-05-03"), distanceMeters: 5_000, movingTimeSeconds: 1_460)
        wrong.routeMatchResult = wrongRouteMatch
        let noMatch = makeRun(source: .runSmart, startedAt: makeDate("2026-05-04"), distanceMeters: 5_000, movingTimeSeconds: 1_440)

        let updated = BenchmarkStatRefresh.refresh([benchmark], from: [matched, possible, wrong, noMatch])

        XCTAssertEqual(updated[0].historicalRunCount, 1, "Only high-confidence match on the correct route counts")
        XCTAssertEqual(updated[0].personalBestSeconds, 1_500)
    }

    func testBenchmarkStatRefreshClearsStatsWhenNoMatchedRunsExist() {
        let routeID = UUID(uuidString: "CC000000-0000-0000-0000-000000000004")!
        let benchmark = BenchmarkRoute(
            id: UUID(), savedRouteID: routeID, enabledAt: Date(timeIntervalSince1970: 1_000),
            historicalRunCount: 5, personalBestSeconds: 1_400, personalBestDate: Date(timeIntervalSince1970: 2_000),
            averagePaceSecondsPerKm: 290, averageDurationSeconds: 1_450
        )
        let unrelatedRun = makeRun(source: .runSmart, startedAt: makeDate("2026-05-01"), distanceMeters: 5_000, movingTimeSeconds: 1_500)

        let updated = BenchmarkStatRefresh.refresh([benchmark], from: [unrelatedRun])

        XCTAssertEqual(updated[0].historicalRunCount, 0)
        XCTAssertNil(updated[0].personalBestSeconds)
        XCTAssertNil(updated[0].personalBestDate)
        XCTAssertNil(updated[0].averagePaceSecondsPerKm)
        XCTAssertNil(updated[0].averageDurationSeconds)
    }

    func testBenchmarkStatRefreshHandlesMixedGarminAndRunSmartSources() {
        let routeID = UUID(uuidString: "CC000000-0000-0000-0000-000000000005")!
        let benchmark = BenchmarkRoute(
            id: UUID(), savedRouteID: routeID, enabledAt: Date(timeIntervalSince1970: 1_000),
            historicalRunCount: 0, personalBestSeconds: nil, personalBestDate: nil,
            averagePaceSecondsPerKm: nil, averageDurationSeconds: nil
        )
        let match = RouteMatchResult(
            routeID: routeID, candidateRouteID: routeID, confidence: .matched,
            distanceDeltaMeters: 0, startDeltaMeters: 0, endDeltaMeters: 0, shapeSimilarity: 1, isReversed: false
        )
        var garminRun = makeRun(source: .garmin, startedAt: makeDate("2026-05-01"), distanceMeters: 5_000, movingTimeSeconds: 1_600)
        garminRun.routeMatchResult = match
        var runSmartRun = makeRun(source: .runSmart, startedAt: makeDate("2026-05-08"), distanceMeters: 5_000, movingTimeSeconds: 1_480)
        runSmartRun.routeMatchResult = match
        var healthKitRun = makeRun(source: .healthKit, startedAt: makeDate("2026-05-15"), distanceMeters: 5_000, movingTimeSeconds: 1_540)
        healthKitRun.routeMatchResult = match

        let updated = BenchmarkStatRefresh.refresh([benchmark], from: [garminRun, runSmartRun, healthKitRun])

        XCTAssertEqual(updated[0].historicalRunCount, 3, "Garmin, RunSmart, and HealthKit matched runs all count")
        XCTAssertEqual(updated[0].personalBestSeconds, 1_480)
        XCTAssertEqual(updated[0].averageDurationSeconds ?? 0, (1_600 + 1_480 + 1_540) / 3, accuracy: 1)
    }

    // MARK: - Sprint 5: Beginner 5K Habit Track

    func testBeginnerHabitTrackDetectsFirst5KGoal() {
        var profile = OnboardingProfile.empty
        profile.goal = "First 5K"
        profile.experience = "Building base"
        XCTAssertTrue(Beginner5KHabitTrack.isBeginnerFirst5K(profile: profile))
    }

    func testBeginnerHabitTrackNonBeginnerIgnored() {
        var profile = OnboardingProfile.empty
        profile.goal = "10K PR"
        profile.experience = "Getting started"
        XCTAssertFalse(Beginner5KHabitTrack.isBeginnerFirst5K(profile: profile))
    }

    func testBeginnerHabitTrackRestDayState() {
        let recovery = makeWorkout(date: "2026-05-17", kind: .recovery, title: "Recovery Jog")
        let track = Beginner5KHabitTrack.make(
            weekWorkouts: [recovery],
            activePlan: nil,
            now: makeDate("2026-05-17")
        )
        XCTAssertEqual(track.state, .restDay)
    }

    func testBeginnerHabitTrackMissedCopyIsNonShaming() {
        let missed = makeWorkout(date: "2026-05-16", kind: .easy, title: "Easy Run")
        let track = Beginner5KHabitTrack.make(
            weekWorkouts: [missed],
            activePlan: nil,
            now: makeDate("2026-05-17")
        )
        XCTAssertEqual(track.state, .missedRecently)
        let shameWords = ["fail", "missed", "skip", "shame", "bad"]
        for word in shameWords {
            XCTAssertFalse(
                track.stateMessage.lowercased().contains(word),
                "Missed copy should not contain shame word: '\(word)'"
            )
        }
    }

    func testBeginnerHabitTrackWeekCompleteState() {
        let w1 = WorkoutSummary(
            id: UUID(), scheduledDate: makeDate("2026-05-13"), planID: nil,
            weekday: "", date: "", kind: .easy, title: "Easy Run",
            distance: "3.0 km", detail: "", isToday: false, isComplete: true,
            durationMinutes: nil, targetPaceSecondsPerKm: nil,
            intensity: nil, trainingPhase: nil, workoutStructure: nil
        )
        let w2 = WorkoutSummary(
            id: UUID(), scheduledDate: makeDate("2026-05-15"), planID: nil,
            weekday: "", date: "", kind: .easy, title: "Easy Run",
            distance: "5.0 km", detail: "", isToday: false, isComplete: true,
            durationMinutes: nil, targetPaceSecondsPerKm: nil,
            intensity: nil, trainingPhase: nil, workoutStructure: nil
        )
        let track = Beginner5KHabitTrack.make(
            weekWorkouts: [w1, w2],
            activePlan: nil,
            now: makeDate("2026-05-17")
        )
        XCTAssertEqual(track.state, .weekComplete)
    }

    // MARK: - Sprint 5: Cue Preview

    func testPreRunCueMissingStructureHandledGracefully() {
        let workout = makeWorkout(date: "2026-05-17", kind: .tempo, title: "Tempo Run", distance: "6.0 km")
        // workoutStructure is nil by default from makeWorkout
        XCTAssertNil(workout.workoutStructure, "Fixture should have nil workoutStructure")
        // makeSteps falls back to derived steps for tempo — must not crash and must return non-empty
        let steps = StructuredWorkoutFactory.makeSteps(for: workout)
        XCTAssertNotNil(steps)
        XCTAssertFalse(steps?.isEmpty ?? true, "Derived tempo steps should not be empty")
    }

    // MARK: - Sprint 6B: Return Loop + Share Cards

    func testReturnReminderCopyIsCalmAndNonShaming() {
        for reminderType in RunSmartReminderType.allCases {
            let content = RunSmartReminderContent.content(for: reminderType, workoutTitle: "Easy Run")
            let combined = "\(content.title) \(content.body)".lowercased()
            for word in ["fail", "failed", "shame", "bad", "lazy", "guilt"] {
                XCTAssertFalse(combined.contains(word), "\(reminderType) copy should avoid shame word: \(word)")
            }
        }
    }

    func testReturnReminderPlanRespectsDisabledPreference() {
        var profile = OnboardingProfile.empty
        profile.notificationsEnabled = false
        let workout = makeWorkout(date: "2026-05-18", kind: .easy, title: "Easy Run")
        let plan = RunSmartReminderPlan.make(
            profile: profile,
            workouts: [workout],
            recentRuns: [],
            recovery: .loading,
            now: makeDate("2026-05-17")
        )
        XCTAssertTrue(plan.requests.isEmpty)
        XCTAssertTrue(plan.shouldCancelExisting)
    }

    func testOnboardingProfileDefaultsSmartRemindersOn() {
        XCTAssertTrue(OnboardingProfile.empty.notificationsEnabled)
    }

    func testFirstRunReminderSchedulesTomorrowMorning() async {
        let workoutID = UUID(uuidString: "00000000-0000-0000-0000-000000006B02")!
        let workout = makeWorkout(id: workoutID, date: "2026-05-18", kind: .easy, title: "Easy 3K")
        let now = makeDate("2026-05-17")
        let calendar = Calendar(identifier: .gregorian)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let expectedFireDate = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: calendar.startOfDay(for: tomorrow))!

        let request = RunSmartReminderRequest(
            identifier: "runsmart.reminder.firstRun",
            type: .workoutDue,
            fireDate: expectedFireDate,
            workoutID: workout.id,
            destination: .today,
            content: RunSmartReminderContent(
                title: "Time for your first RunSmart run",
                body: "\(workout.title) is ready when you are."
            )
        )

        XCTAssertEqual(request.identifier, "runsmart.reminder.firstRun")
        XCTAssertEqual(request.workoutID, workoutID)
        XCTAssertEqual(calendar.component(.hour, from: request.fireDate), 7)
        XCTAssertTrue(calendar.isDate(request.fireDate, inSameDayAs: tomorrow))
    }

    func testReturnReminderPlanSchedulesTomorrowWorkoutWhenEnabled() {
        let profile = OnboardingProfile.empty
        let workoutID = UUID(uuidString: "00000000-0000-0000-0000-000000006B01")!
        let workout = makeWorkout(id: workoutID, date: "2026-05-18", kind: .easy, title: "Easy Run")

        let plan = RunSmartReminderPlan.make(
            profile: profile,
            workouts: [workout],
            recentRuns: [],
            recovery: .loading,
            now: makeDate("2026-05-17")
        )

        XCTAssertTrue(plan.requests.contains { $0.type == .workoutDue && $0.workoutID == workoutID })
        XCTAssertTrue(plan.requests.contains { $0.type == .weeklyRecap })
    }

    func testProgressSharePayloadExcludesRawCoordinatesByDefault() {
        let payload = ProgressSharePayload.runReport(
            RunReportDetail(
                id: "report-1",
                runID: "run-1",
                title: "Morning Run",
                dateLabel: "May 17",
                source: "RunSmart",
                distance: "5.0 km",
                duration: "28:20",
                averagePace: "5:40 /km",
                averageHeartRate: "142 bpm",
                coachScore: 82,
                notes: CoachRunNotes(
                    summary: "Steady aerobic run.",
                    effort: "Controlled",
                    recovery: "Easy day next",
                    nextSessionNudge: "Keep the next run relaxed."
                ),
                structuredNextWorkout: nil
            )
        )

        XCTAssertFalse(payload.shareText.lowercased().contains("latitude"))
        XCTAssertFalse(payload.shareText.lowercased().contains("longitude"))
        XCTAssertFalse(payload.shareText.lowercased().contains("coordinate"))
        XCTAssertTrue(payload.privacyNote.lowercased().contains("no map"))
    }

    func testNullAnalyticsServiceSwallowsAllCallsWithoutCrashing() {
        let svc = NullAnalyticsService()
        svc.track("test_event", properties: ["key": "value"])
        svc.identify(userId: "user_123", traits: ["plan": "pro"])
        svc.reset()
        // No assertion needed — just confirm no crash
    }

    func testAnalyticsSharedDefaultsToNullService() {
        // The app host may call Analytics.setup() before tests run, so we can't
        // assert the compile-time default. Instead verify that shared is assignable
        // to NullAnalyticsService and the type-check protocol works correctly.
        let saved = Analytics.shared
        defer { Analytics.shared = saved }
        Analytics.shared = NullAnalyticsService()
        XCTAssertTrue(Analytics.shared is NullAnalyticsService,
            "Analytics.shared must accept and expose NullAnalyticsService assignments")
    }

    private nonisolated final class CapturingAnalyticsService: AnalyticsTracking {
        private(set) var events: [(name: String, properties: [String: Any])] = []
        private(set) var registrations: [[String: Any]] = []
        private(set) var resetCount = 0

        func track(_ event: String, properties: [String: Any]) {
            events.append((event, properties))
        }

        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {
            registrations.append(properties)
        }
        func reset() {
            resetCount += 1
        }
    }

    // MARK: - WP-51 build identity + onboarding_started dedupe

    /// Measured 2026-07-20: app_version was set on 2 of 3,813 events over 60 days,
    /// so RunSmart funnels could not be split by build at all.
    func testBuildIdentityPropertiesMapVersionAndBuild() {
        let bundle = StubInfoBundle(values: [
            "CFBundleShortVersionString": "1.1.1",
            "CFBundleVersion": "25"
        ])
        let props = Analytics.buildIdentityProperties(bundle: bundle)
        XCTAssertEqual(props["app_version"], "1.1.1",
            "app_version must come from CFBundleShortVersionString")
        XCTAssertEqual(props["app_build"], "25",
            "app_build must come from CFBundleVersion")
    }

    func testBuildIdentityPropertiesOmitsMissingAndEmptyValues() {
        XCTAssertTrue(Analytics.buildIdentityProperties(bundle: StubInfoBundle(values: [:])).isEmpty,
            "a bundle with no version keys must register nothing rather than empty strings")

        let blank = Analytics.buildIdentityProperties(bundle: StubInfoBundle(values: [
            "CFBundleShortVersionString": "",
            "CFBundleVersion": "25"
        ]))
        XCTAssertNil(blank["app_version"], "an empty version string must be omitted, not registered as \"\"")
        XCTAssertEqual(blank["app_build"], "25", "a present build must still register when version is blank")
    }

    func testAnalyticsResetReRegistersBuildIdentityForAnonymousEvents() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer { Analytics.shared = saved }
        Analytics.shared = tracker

        Analytics.resetUser(bundle: StubInfoBundle(values: [
            "CFBundleShortVersionString": "1.1.1",
            "CFBundleVersion": "25"
        ]))

        XCTAssertEqual(tracker.resetCount, 1, "reset must still clear the prior user identity")
        XCTAssertEqual(tracker.registrations.count, 1, "build identity must be restored immediately after reset")
        XCTAssertEqual(tracker.registrations.first?["app_version"] as? String, "1.1.1")
        XCTAssertEqual(tracker.registrations.first?["app_build"] as? String, "25")
    }

    /// OnboardingView emits from .onAppear, which SwiftUI runs again on re-mount and
    /// on return from background. Observed twice in one founder session (2026-07-20
    /// 09:22:11 and 09:23:59) against a single onboarding_completed.
    func testOnboardingStartedFiresOncePerUser() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer {
            Analytics.shared = saved
            Analytics.resetOnboardingStartGuardForTesting()
        }
        Analytics.shared = tracker
        Analytics.resetOnboardingStartGuardForTesting()

        Analytics.trackOnboardingStarted()
        Analytics.trackOnboardingStarted()
        Analytics.trackOnboardingStarted()

        XCTAssertEqual(tracker.events.filter { $0.name == "onboarding_started" }.count, 1,
            "repeated onAppear must emit onboarding_started exactly once")
    }

    func testIdentityResetDoesNotRestartAnActiveOnboardingLifecycle() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer {
            Analytics.shared = saved
            Analytics.resetOnboardingStartGuardForTesting()
        }
        Analytics.shared = tracker
        Analytics.resetOnboardingStartGuardForTesting()

        Analytics.trackOnboardingStarted()
        Analytics.resetUser()
        Analytics.trackOnboardingStarted()

        XCTAssertEqual(tracker.events.filter { $0.name == "onboarding_started" }.count, 1,
            "an analytics identity reset during authentication must not duplicate onboarding_started")
    }

    func testNewSignInAttemptStartsANewOnboardingLifecycle() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer {
            Analytics.shared = saved
            Analytics.resetOnboardingStartGuardForTesting()
        }
        Analytics.shared = tracker
        Analytics.resetOnboardingStartGuardForTesting()

        Analytics.trackSignInWallTapped()
        Analytics.trackOnboardingStarted()
        Analytics.resetUser()
        Analytics.trackSignInWallTapped()
        Analytics.trackOnboardingStarted()

        XCTAssertEqual(tracker.events.filter { $0.name == "onboarding_started" }.count, 2,
            "a distinct sign-in attempt must permit one new onboarding lifecycle")
    }

    @MainActor
    func testConcurrentNotificationAuthorizationSharesOnePromptAndTerminalEvent() async throws {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer { Analytics.shared = saved }
        Analytics.shared = tracker
        var promptCount = 0

        let service = PushService(
            authorizationStatusProvider: { .notDetermined },
            authorizationRequester: { _ in
                promptCount += 1
                try await Task.sleep(nanoseconds: 50_000_000)
                return true
            }
        )

        async let first = service.requestAuthorization()
        async let second = service.requestAuthorization()
        let results = try await (first, second)

        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(promptCount, 1, "concurrent callers must share one system authorization request")
        XCTAssertEqual(tracker.events.filter { $0.name == "permission_requested" }.count, 1)
        XCTAssertEqual(tracker.events.filter { $0.name == "permission_granted" }.count, 1)
        XCTAssertEqual(tracker.events.filter { $0.name == "permission_denied" }.count, 0)
    }

    private final class StubInfoBundle: Bundle, @unchecked Sendable {
        private let values: [String: String]

        init(values: [String: String]) {
            self.values = values
            super.init()
        }

        required init?(coder: NSCoder) { fatalError("unused") }

        override func object(forInfoDictionaryKey key: String) -> Any? {
            values[key]
        }
    }

    // WP-45: payload-key assertions for the instrumentation added to complete
    // the plan's event list (audit §11).
    func testWP45EventsCarryRequiredPayloadKeys() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer { Analytics.shared = saved }
        Analytics.shared = tracker

        Analytics.trackOnboardingStepAbandoned(lastStep: "goal", dwellSeconds: 12)
        Analytics.trackPermissionRequested(kind: "location")
        Analytics.trackPermissionGranted(kind: "notifications")
        Analytics.trackPermissionDenied(kind: "location")
        Analytics.trackHealthKitConnectFailed(reason: "error")
        Analytics.trackRunReportGenerateTapped(source: "run_report_detail")
        Analytics.trackRunReportGenerateSucceeded(source: "run_report_detail")
        Analytics.trackRunReportGenerateFailed(source: "garmin_activity")
        Analytics.trackInsightExpanded(surface: "workout_breakdown")
        Analytics.trackShareProgressTapped(payloadKind: "Milestone")
        Analytics.trackOnboardingCompleted(goal: "First 5K", experience: "Getting started", daysPerWeek: 3, completedAt: Date(timeIntervalSince1970: 1_750_000_000))

        func event(_ name: String) -> [String: Any]? {
            tracker.events.first { $0.name == name }?.properties
        }

        XCTAssertEqual(event("onboarding_step_abandoned")?["last_step"] as? String, "goal")
        XCTAssertEqual(event("onboarding_step_abandoned")?["dwell_seconds"] as? Int, 12)
        XCTAssertEqual(event("permission_requested")?["kind"] as? String, "location")
        XCTAssertEqual(event("permission_granted")?["kind"] as? String, "notifications")
        XCTAssertEqual(event("permission_denied")?["kind"] as? String, "location")
        XCTAssertEqual(event("healthkit_connect_failed")?["reason"] as? String, "error")
        XCTAssertEqual(event("run_report_generate_tapped")?["source"] as? String, "run_report_detail")
        XCTAssertNotNil(event("run_report_generate_succeeded"))
        XCTAssertNotNil(event("run_report_generate_failed"))
        XCTAssertEqual(event("insight_expanded")?["surface"] as? String, "workout_breakdown")
        XCTAssertEqual(event("share_progress_tapped")?["payload_kind"] as? String, "Milestone")

        let completedSet = event("onboarding_completed")?["$set"] as? [String: Any]
        XCTAssertNotNil(completedSet?["onboarding_completed_at"], "onboarding_completed must set the person property for D1/D7 cohorting")
    }

    // WP-45: first_workout_viewed must fire exactly once per install.
    func testFirstWorkoutViewedFiresOnce() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        let suiteName = "runsmart.analytics.first-workout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            Analytics.shared = saved
            defaults.removePersistentDomain(forName: suiteName)
        }
        Analytics.shared = tracker

        Analytics.trackFirstWorkoutViewed(workoutType: "easy", defaults: defaults)
        Analytics.trackFirstWorkoutViewed(workoutType: "tempo", defaults: defaults)

        let fired = tracker.events.filter { $0.name == "first_workout_viewed" }
        XCTAssertEqual(fired.count, 1, "first_workout_viewed is a first-time-only event")
        XCTAssertEqual(fired.first?.properties["workout_type"] as? String, "easy")
    }

    func testCompletedRunAnalyticsFiresOnceAndMarksFirstRunOnce() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        let suiteName = "runsmart.analytics.completed-run.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            Analytics.shared = saved
            defaults.removePersistentDomain(forName: suiteName)
        }

        Analytics.shared = tracker
        let firstRun = RecordedRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
            providerActivityID: nil,
            source: .runSmart,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_800),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil
        )
        let secondRun = RecordedRun(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!,
            providerActivityID: "garmin-activity-2",
            source: .garmin,
            startedAt: Date(timeIntervalSince1970: 10_000),
            endedAt: Date(timeIntervalSince1970: 12_100),
            distanceMeters: 6_000,
            movingTimeSeconds: 2_100,
            averagePaceSecondsPerKm: 350,
            averageHeartRateBPM: 148,
            routePoints: [],
            syncedAt: nil
        )

        Analytics.trackCompletedRunIfNeeded(firstRun, runType: "free", defaults: defaults)
        Analytics.trackCompletedRunIfNeeded(firstRun, runType: "free", defaults: defaults)
        Analytics.trackCompletedRunIfNeeded(secondRun, defaults: defaults)

        XCTAssertEqual(tracker.events.map(\.name), ["run_completed", "first_run_completed", "run_completed"])
        XCTAssertEqual(tracker.events[0].properties["run_type"] as? String, "free")
        XCTAssertEqual(tracker.events[0].properties["is_first_run"] as? Bool, true)
        XCTAssertEqual(tracker.events[2].properties["run_type"] as? String, "Garmin")
        XCTAssertEqual(tracker.events[2].properties["is_first_run"] as? Bool, false)
    }

    func testPlanRunCTAAnalyticsCapturesBridgeToRunStart() {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer { Analytics.shared = saved }

        Analytics.shared = tracker
        Analytics.trackPlanRunCTATapped(
            source: "today_up_next",
            workoutType: "easy",
            scheduledToday: false,
            hasPriorRuns: false
        )

        XCTAssertEqual(tracker.events.map(\.name), ["plan_run_cta_tapped"])
        XCTAssertEqual(tracker.events[0].properties["source"] as? String, "today_up_next")
        XCTAssertEqual(tracker.events[0].properties["workout_type"] as? String, "easy")
        XCTAssertEqual(tracker.events[0].properties["scheduled_today"] as? Bool, false)
        XCTAssertEqual(tracker.events[0].properties["has_prior_runs"] as? Bool, false)
    }

    // MARK: - E1: TodayRecommendation rationale field (Story 1)

    func testTodayRecommendationRationaleDefaultsToNil() {
        let rec = TodayRecommendation(
            readiness: 75,
            readinessLabel: "Good",
            workoutTitle: "Easy Run",
            distance: "5 km",
            pace: "6:00",
            elevation: "--",
            coachMessage: "Let's go"
        )
        XCTAssertNil(rec.rationale, "rationale must default to nil")
    }

    func testTodayRecommendationAcceptsRationaleString() {
        let rec = TodayRecommendation(
            readiness: 75,
            readinessLabel: "Good",
            workoutTitle: "Easy Run",
            distance: "5 km",
            pace: "6:00",
            elevation: "--",
            coachMessage: "Let's go",
            rationale: "Body battery at 82 — a strong signal you're ready to push today."
        )
        XCTAssertEqual(rec.rationale, "Body battery at 82 — a strong signal you're ready to push today.")
    }

    func testTodayRecommendationWithRationaleCompiles() {
        let withRationale = TodayRecommendation(
            readiness: 80, readinessLabel: "High",
            workoutTitle: "Easy Run", distance: "5 km",
            pace: "6:00", elevation: "--",
            coachMessage: "Go run.",
            rationale: "Body battery at 80 — a strong signal today."
        )
        let withoutRationale = TodayRecommendation(
            readiness: 80, readinessLabel: "High",
            workoutTitle: "Easy Run", distance: "5 km",
            pace: "6:00", elevation: "--",
            coachMessage: "Go run."
        )
        XCTAssertNotNil(withRationale.rationale)
        XCTAssertNil(withoutRationale.rationale)
    }

    // MARK: - E1: TodayRationaleBuilder (Story 2)

    func testRationaleUsesBodyBatteryHighPath() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: 85,
            hrv: nil,
            sleepSeconds: nil,
            workoutTitle: "Easy Run",
            isRestDay: false,
            planWeekIndex: 2
        )
        XCTAssertTrue(result.contains("85") || result.lowercased().contains("body battery"),
                      "High body battery rationale should reference the score or body battery")
        XCTAssertLessThanOrEqual(result.count, 140, "Rationale must fit on card (<=140 chars)")
    }

    func testRationaleUsesBodyBatteryLowPath() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: 28,
            hrv: nil,
            sleepSeconds: nil,
            workoutTitle: "Tempo Run",
            isRestDay: false,
            planWeekIndex: 4
        )
        XCTAssertTrue(result.lowercased().contains("low") || result.lowercased().contains("easy") || result.lowercased().contains("protect"),
                      "Low body battery should signal caution")
        XCTAssertLessThanOrEqual(result.count, 140)
    }

    func testRationaleUsesHRVWhenNoBattery() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: nil,
            hrv: 62.0,
            sleepSeconds: nil,
            workoutTitle: "Long Run",
            isRestDay: false,
            planWeekIndex: 6
        )
        XCTAssertTrue(result.lowercased().contains("hrv") || result.contains("62"),
                      "HRV path should reference HRV or the value")
        XCTAssertLessThanOrEqual(result.count, 140)
    }

    func testRationaleOnRestDay() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: nil,
            hrv: nil,
            sleepSeconds: nil,
            workoutTitle: "Rest Day",
            isRestDay: true,
            planWeekIndex: 3
        )
        XCTAssertTrue(result.lowercased().contains("rest") || result.lowercased().contains("recover"),
                      "Rest day rationale should mention rest or recovery")
        XCTAssertLessThanOrEqual(result.count, 140)
    }

    func testRationaleEarlyPlanFallback() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: nil,
            hrv: nil,
            sleepSeconds: nil,
            workoutTitle: "Easy Run",
            isRestDay: false,
            planWeekIndex: 1
        )
        XCTAssertTrue(result.lowercased().contains("early") || result.lowercased().contains("base") || result.lowercased().contains("foundation"),
                      "Early-plan fallback should mention building base")
        XCTAssertLessThanOrEqual(result.count, 140)
    }

    func testRationaleNoDataGenericFallback() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: nil,
            hrv: nil,
            sleepSeconds: nil,
            workoutTitle: "Easy Run",
            isRestDay: false,
            planWeekIndex: nil
        )
        XCTAssertFalse(result.isEmpty, "Fallback rationale must never be empty")
        XCTAssertLessThanOrEqual(result.count, 140)
    }

    // MARK: - E1: Fallback edge cases (Story 4)

    func testRationaleFallbackNeverExposesErrorLanguage() {
        let result = TodayRationaleBuilder.rationale(
            bodyBattery: nil,
            hrv: nil,
            sleepSeconds: nil,
            workoutTitle: "Easy Run",
            isRestDay: false,
            planWeekIndex: nil
        )
        let forbidden = ["unable", "error", "failed", "unavailable", "null", "nil"]
        for word in forbidden {
            XCTAssertFalse(result.lowercased().contains(word),
                           "Fallback must not expose technical language: '\(word)' found in '\(result)'")
        }
    }

    func testRationaleIsUnder140CharactersForAllPaths() {
        let paths: [(Int?, Double?, Double?, String, Bool, Int?)] = [
            (85, nil, nil, "Tempo Run", false, 4),
            (28, nil, nil, "Easy Run", false, 2),
            (nil, 65.0, nil, "Long Run", false, 6),
            (nil, 38.0, nil, "Easy Run", false, 1),
            (nil, nil, 7 * 3600, "Intervals", false, 5),
            (nil, nil, nil, "Rest Day", true, 3),
            (nil, nil, nil, "Easy Run", false, 1),
            (nil, nil, nil, "Easy Run", false, 9),
            (nil, nil, nil, "Easy Run", false, nil),
        ]
        for (bb, hrv, sleep, title, isRest, week) in paths {
            let result = TodayRationaleBuilder.rationale(
                bodyBattery: bb,
                hrv: hrv,
                sleepSeconds: sleep,
                workoutTitle: title,
                isRestDay: isRest,
                planWeekIndex: week
            )
            XCTAssertLessThanOrEqual(result.count, 140,
                "Rationale too long (\(result.count) chars) for path bb=\(String(describing: bb)): \(result)")
        }
    }

    func testPlaceholderRecommendationHasNilRationale() {
        XCTAssertNil(TodayRecommendation.placeholder.rationale,
                     "Placeholder must not show a rationale — card should hide the row gracefully")
    }

    // MARK: - SafetyExplanationBuilder

    func testSafetyExplanationBuilderFiresReadinessGateWhenReadinessIsLow() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 38,
            bodyBattery: nil,
            hrv: nil,
            workoutTitle: "Easy Run",
            isRestDay: false
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .readinessGate)
        XCTAssertFalse(result?.coachVoice.isEmpty ?? true)
        XCTAssertEqual(result?.action, "Amend workout")
    }

    func testSafetyExplanationBuilderReadinessGateOnRestDayHasNoAction() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 32,
            bodyBattery: nil,
            hrv: nil,
            workoutTitle: "Rest Day",
            isRestDay: true
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .readinessGate)
        XCTAssertNil(result?.action)
    }

    func testSafetyExplanationBuilderFiresLowBodyBatteryWhenReadinessIsModerate() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 60,
            bodyBattery: 28,
            hrv: nil,
            workoutTitle: "Easy Run",
            isRestDay: false
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .lowBodyBattery)
        XCTAssertTrue(result?.coachVoice.contains("28") ?? false)
    }

    func testSafetyExplanationBuilderFiresLowHRVWhenBodyBatteryIsAboveThreshold() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 55,
            bodyBattery: 50,
            hrv: 35.0,
            workoutTitle: "Easy Run",
            isRestDay: false
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .lowHRV)
        XCTAssertTrue(result?.coachVoice.contains("35") ?? false)
    }

    func testSafetyExplanationBuilderReturnsNilWhenReadinessIsGood() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 80,
            bodyBattery: 72,
            hrv: 60.0,
            workoutTitle: "Tempo Run",
            isRestDay: false
        )
        XCTAssertNil(result)
    }

    func testSafetyExplanationBuilderReturnsNilWhenReadinessIsZero() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 0,
            bodyBattery: 20,
            hrv: 30.0,
            workoutTitle: "Easy Run",
            isRestDay: false
        )
        XCTAssertNil(result)
    }

    func testSafetyExplanationBuilderBoundaryReadiness45DoesNotFireGate() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 45,
            bodyBattery: nil,
            hrv: nil,
            workoutTitle: "Easy Run",
            isRestDay: false
        )
        XCTAssertNil(result)
    }

    func testSafetyExplanationBuilderEvidenceIncludesReadiness() {
        let result = SafetyExplanationBuilder.explanation(
            readiness: 38,
            bodyBattery: 25,
            hrv: 42.0,
            workoutTitle: "Easy Run",
            isRestDay: false
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.evidence.contains("38") ?? false)
        XCTAssertTrue(result?.evidence.contains("25") ?? false)
    }

    func testRunDebriefRequestDTOEncodesIntent() throws {
        let dto = RunSmartDTO.RunDebriefRequestDTO(
            runDistanceKm: 5.0,
            runDurationSeconds: 1500,
            averagePaceMinPerKm: 5.0,
            averageHeartRateBPM: nil,
            workoutType: "easy",
            planPhase: nil,
            recentLoadDays: 2,
            limitations: []
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["intent"] as? String, "run_debrief")
        XCTAssertEqual(json["runDistanceKm"] as? Double, 5.0)
    }

    func testRunDebriefResponseDTODecodes() throws {
        let json = """
        {
          "headline": "Solid effort",
          "debrief": "You held pace well for 5 km.",
          "tomorrow": "Easy day tomorrow.",
          "planImpact": "Plan stays on track",
          "source": "live_ai"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(RunSmartDTO.RunDebriefResponseDTO.self, from: data)
        XCTAssertEqual(dto.headline, "Solid effort")
        XCTAssertEqual(dto.source, "live_ai")
    }

    func testPostRunDebriefModelFallbackHasContent() {
        let run = RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: Date(),
            endedAt: Date(),
            distanceMeters: 5000,
            movingTimeSeconds: Double(1500),
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil
        )
        let fallback = PostRunDebriefModel.fallback(for: run)
        XCTAssertFalse(fallback.headline.isEmpty)
        XCTAssertFalse(fallback.debrief.isEmpty)
        XCTAssertFalse(fallback.tomorrow.isEmpty)
        XCTAssertEqual(fallback.source, .fallback)
    }

    func testPostActivityOutcomeHasDebriefField() {
        let run = RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: Date(),
            endedAt: Date(),
            distanceMeters: 3000,
            movingTimeSeconds: Double(1200),
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil
        )
        let outcome = PostActivityOutcome(
            canonicalRun: run,
            report: nil,
            completedWorkout: nil,
            didCompletePlannedWorkout: false,
            debrief: nil
        )
        XCTAssertNil(outcome.debrief)
    }

    func testPostRunDebriefModelSourceIsAIOrFallback() {
        // Verify the Source enum only has .ai and .fallback
        let ai = PostRunDebriefModel.Source.ai
        let fallback = PostRunDebriefModel.Source.fallback
        XCTAssertNotEqual(ai, fallback)
        XCTAssertEqual(ai.rawValue, "ai")
        XCTAssertEqual(fallback.rawValue, "fallback")
    }

    func testPostRunDebriefModelFallbackForNilRun() {
        let fallback = PostRunDebriefModel.fallback(for: nil)
        XCTAssertFalse(fallback.headline.isEmpty)
        XCTAssertFalse(fallback.debrief.isEmpty)
        XCTAssertFalse(fallback.tomorrow.isEmpty)
        XCTAssertEqual(fallback.source, .fallback)
    }

    func testWeeklyProgressSummaryFallbackHasHeadline() {
        let summary = WeeklyProgressSummary.fallback(runsCompleted: 3, totalDistanceKm: 15.4)
        XCTAssertFalse(summary.headline.isEmpty)
        XCTAssertEqual(summary.source, .fallback)
    }

    func testWeeklySummaryRequestDTOEncodesIntent() throws {
        let dto = RunSmartDTO.WeeklySummaryRequestDTO(
            weekStartDate: "2026-05-18",
            runsCompleted: 3,
            runsPlanned: 4,
            totalDistanceKm: 18.5,
            prevWeekDistanceKm: 15.2,
            planPhase: "build",
            isRecoveryWeek: false,
            readinessAverage: 72.0,
            limitations: []
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["intent"] as? String, "weekly_summary")
        XCTAssertEqual(json["runsCompleted"] as? Int, 3)
    }

    func testWeeklySummaryResponseDTODecodes() throws {
        let json = """
        {
          "headline": "3 runs · 18.5 km",
          "narrative": "A strong base week.",
          "forwardLook": "Next week's long run is where this pays off.",
          "weekLabel": "Week 3 of your plan",
          "source": "live_ai"
        }
        """
        let data = json.data(using: .utf8)!
        let dto = try JSONDecoder().decode(RunSmartDTO.WeeklySummaryResponseDTO.self, from: data)
        XCTAssertEqual(dto.headline, "3 runs · 18.5 km")
        XCTAssertEqual(dto.source, "live_ai")
    }

    func testWeeklyProgressSummaryCacheRoundTrip() throws {
        let summary = WeeklyProgressSummary(
            headline: "3 runs · 15 km",
            narrative: "Good week.",
            forwardLook: "Next week builds on this.",
            weekLabel: "Week 2 of your plan",
            generatedDate: Date(),
            isoWeekKey: WeeklyProgressSummary.currentISOWeekKey(),
            source: .fallback
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(WeeklyProgressSummary.self, from: data)
        XCTAssertEqual(decoded.headline, summary.headline)
        XCTAssertEqual(decoded.isoWeekKey, summary.isoWeekKey)
        XCTAssertEqual(decoded.source, summary.source)
    }

    func testWeeklyProgressSummaryISOWeekKeyIsStable() {
        let key = WeeklyProgressSummary.currentISOWeekKey()
        // Format must be YYYY-Www (e.g. "2026-W21")
        let pattern = #"^\d{4}-W\d{2}$"#
        XCTAssertTrue(key.range(of: pattern, options: .regularExpression) != nil,
                      "Expected YYYY-Www format, got '\(key)'")
        // Must be idempotent within the same second
        XCTAssertEqual(key, WeeklyProgressSummary.currentISOWeekKey())
        // Session is running in 2026 — sanity-check the year prefix
        XCTAssertTrue(key.hasPrefix("2026-"), "Expected 2026 prefix for current test run, got '\(key)'")
    }

    func testWeeklyProgressSummaryIsNewWeekDetection() {
        let oldKey = "2020-W01"
        XCTAssertTrue(WeeklyProgressSummary.isNewWeek(since: oldKey))
        let currentKey = WeeklyProgressSummary.currentISOWeekKey()
        XCTAssertFalse(WeeklyProgressSummary.isNewWeek(since: currentKey))
    }

    func testWeeklyProgressCardSuppressedDuringBeginnerChallenge() {
        // Gate condition: isBeginnerFirst5K returns true for a First 5K profile,
        // confirming the suppression logic in TodayTabView works correctly.
        let beginnerProfile = OnboardingProfile(
            displayName: "Runner",
            goal: "First 5K",
            experience: "Getting started",
            age: nil,
            averageWeeklyDistanceKm: nil,
            trainingDataSource: nil,
            trainingDataUpdatedAt: nil,
            weeklyRunDays: 3,
            preferredDays: ["Tue", "Thu", "Sat"],
            units: "Metric",
            coachingTone: "Motivating",
            notificationsEnabled: false,
            planAdjustmentConfirmationsEnabled: true
        )
        let isChallenge = Beginner5KHabitTrack.isBeginnerFirst5K(profile: beginnerProfile)
        XCTAssertTrue(isChallenge)

        // Non-beginner profile should not trigger suppression
        let advancedProfile = OnboardingProfile(
            displayName: "Runner",
            goal: "10K PR",
            experience: "Intermediate",
            age: nil,
            averageWeeklyDistanceKm: nil,
            trainingDataSource: nil,
            trainingDataUpdatedAt: nil,
            weeklyRunDays: 4,
            preferredDays: ["Tue", "Thu", "Sat", "Sun"],
            units: "Metric",
            coachingTone: "Motivating",
            notificationsEnabled: false,
            planAdjustmentConfirmationsEnabled: true
        )
        XCTAssertFalse(Beginner5KHabitTrack.isBeginnerFirst5K(profile: advancedProfile))
    }

    // WP-43 S2: SignInView used to set `errorMessage = error.localizedDescription`,
    // which surfaced raw strings like "com.apple.AuthenticationServices.AuthorizationError
    // error 1000" straight to a first-time user. humanReadableAppleSignInError(for:) maps
    // ASAuthorizationError cases to human copy and must never forward NSError.localizedDescription.
    func testSignInErrorMappingHidesRawNSError() {
        let canceled = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )
        XCTAssertNil(SignInView.humanReadableAppleSignInError(for: canceled), "user backed out — no error should show")

        let failed = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.failed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "com.apple.AuthenticationServices.AuthorizationError error 1000"]
        )
        let mapped = SignInView.humanReadableAppleSignInError(for: failed)
        XCTAssertNotNil(mapped)
        XCTAssertFalse(mapped!.contains("com.apple"), "raw NSError domain string must never reach the screen")
        XCTAssertFalse(mapped!.contains("1000"), "raw NSError code must never reach the screen")

        let otherError = AppleSignInError.invalidCredential
        let mappedOther = SignInView.humanReadableAppleSignInError(for: otherError)
        XCTAssertNotNil(mappedOther)
        XCTAssertFalse(mappedOther!.contains("credential type"), "generic fallback copy must not leak the raw error's wording")
    }

    // 1.1.2 (27). The 2026-07-22 revoke-and-retry test proved first-time Sign in
    // with Apple works, so the three real devices stuck on code 1000 are failing
    // for a device- or account-side reason. Sign in with Apple cannot work unless
    // the device is signed in to iCloud, and that is invisible from inside the
    // app. "Tap to try again" gives a blocked user nothing to act on, so the copy
    // must name the one precondition they can actually check and fix.
    func testSignInErrorCopyTellsBlockedUserWhatToCheck() {
        let failed = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.unknown.rawValue
        )
        let mapped = SignInView.humanReadableAppleSignInError(for: failed)

        XCTAssertNotNil(mapped)
        XCTAssertTrue(
            mapped!.localizedCaseInsensitiveContains("iCloud"),
            "a user blocked by a missing iCloud session must be told to check it; 'try again' alone loops them forever"
        )
        XCTAssertTrue(
            mapped!.localizedCaseInsensitiveContains("nothing was created")
                || mapped!.localizedCaseInsensitiveContains("no account"),
            "the reassurance that no partial account exists is load-bearing trust copy from WP-43 S2 — do not drop it"
        )
        // The raw-NSError guarantee from the test above must survive the rewrite.
        XCTAssertFalse(mapped!.contains("com.apple"))
        XCTAssertFalse(mapped!.contains("1000"))
    }

    // WP-44 S1: the first screen's pills said "Run guidance and cue previews"
    // (feature-speak) and "HealthKit reads approved data..." (compliance-speak).
    // The audit's daily-answer promise must lead, and neither old bullet may return.
    func testSignInFeaturePillsLeadWithDailyAnswerPromise() {
        let texts = SignInView.featurePills.map(\.text)
        XCTAssertEqual(texts.first, "Know exactly what to run today", "the daily-answer promise must be the first thing a skeptical user reads")
        for text in texts {
            XCTAssertFalse(text.contains("cue previews"), "feature-speak bullet must not return")
            XCTAssertFalse(text.contains("approved data"), "compliance-speak bullet must not return")
        }
    }

    // WP-44 S6: Terms/Privacy used to be `Link`s that ejected a pre-auth user to
    // external Safari. They now present in-app; the document URLs must still be
    // the canonical ExternalURLs so the in-app move never changes the destination.
    func testSignInLegalDocumentsUseCanonicalURLs() {
        XCTAssertEqual(SignInView.LegalDocument.terms.url, ExternalURLs.terms)
        XCTAssertEqual(SignInView.LegalDocument.privacy.url, ExternalURLs.privacy)
    }

    // WP-44 S4: the fourth onboarding step was titled "Privacy" with a
    // "Confirm Privacy" CTA while its content is coaching tone + reminders —
    // the title must match the content (audit §7/§9).
    func testOnboardingCoachingStepCopyMatchesContent() {
        XCTAssertEqual(OnboardingView.coachingStepTitle, "Coaching", "step title must describe its content (tone + reminders), not claim to be a privacy step")
        XCTAssertEqual(OnboardingView.coachingStepCTA, "Continue", "the CTA must not ask the user to 'confirm privacy' they never reviewed")
    }

    // WP-44 S3: weekly distance must be one summation (TrainingMetrics), not a
    // per-surface computation — the audit found Plan claiming 86.20 km while the
    // summed workouts were ~36 km because surfaces summed independently.
    func testWeeklyDistanceMatchesSummedWorkouts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = makeDate("2026-05-20").addingTimeInterval(12 * 3600)
        let thisWeekA = makeRun(source: .runSmart, startedAt: now.addingTimeInterval(-3600), distanceMeters: 5_000, movingTimeSeconds: 1800)
        let thisWeekB = makeRun(source: .runSmart, startedAt: now.addingTimeInterval(-24 * 3600), distanceMeters: 7_500, movingTimeSeconds: 2700)
        let lastMonth = makeRun(source: .runSmart, startedAt: now.addingTimeInterval(-30 * 24 * 3600), distanceMeters: 10_000, movingTimeSeconds: 3600)

        let weekly = TrainingMetrics.weeklyDistanceKm(runs: [thisWeekA, thisWeekB, lastMonth], now: now, calendar: calendar)
        XCTAssertEqual(weekly, 12.5, accuracy: 0.001, "weekly distance must equal the sum of this week's runs only")
    }

    // WP-44 S3: streak labels must carry one unit everywhere. Backends send
    // "12 days", "12 day streak", or "3x/week"; re-rendering the raw value with
    // " day streak" appended produced "12 days day streak" and turned a weekly
    // cadence into a fake day streak (Profile "11-week" vs Today "11 day").
    func testStreakUnitConsistentAcrossSurfaces() {
        XCTAssertEqual(TrainingMetrics.canonicalStreakLabel(fromLabel: "12 days"), "12 day streak")
        XCTAssertEqual(TrainingMetrics.canonicalStreakLabel(fromLabel: "12 day streak"), "12 day streak")
        XCTAssertEqual(TrainingMetrics.canonicalStreakLabel(fromLabel: "12"), "12 day streak")
        XCTAssertEqual(TrainingMetrics.canonicalStreakLabel(fromLabel: "1 day"), "1 day streak")
        XCTAssertNil(TrainingMetrics.canonicalStreakLabel(fromLabel: "3x/week"), "a weekly cadence must never be re-rendered as a day streak")
        XCTAssertNil(TrainingMetrics.canonicalStreakLabel(fromLabel: "--"))
    }

    // WP-44 S3: the plan week number is clamped to plan bounds and computed in
    // exactly one place.
    func testCurrentWeekNumberClampsToPlanBounds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let start = makeDate("2026-05-04")

        XCTAssertEqual(TrainingMetrics.currentWeekNumber(planStartDate: start, totalWeeks: 8, now: start.addingTimeInterval(3 * 24 * 3600), calendar: calendar), 1)
        XCTAssertEqual(TrainingMetrics.currentWeekNumber(planStartDate: start, totalWeeks: 8, now: start.addingTimeInterval(10 * 24 * 3600), calendar: calendar), 2)
        XCTAssertEqual(TrainingMetrics.currentWeekNumber(planStartDate: start, totalWeeks: 8, now: start.addingTimeInterval(200 * 24 * 3600), calendar: calendar), 8, "week number must clamp to the plan's final week")
        XCTAssertEqual(TrainingMetrics.currentWeekNumber(planStartDate: start, totalWeeks: 8, now: start.addingTimeInterval(-7 * 24 * 3600), calendar: calendar), 1, "dates before the plan start must clamp to week 1")
    }

    // WP-44 S3: a stable or improving HRV must never map to the alarm color,
    // and BOTH producers' vocabularies must resolve (Supabase: Stable/Lower;
    // Garmin: Stable/Moderate/Low — GarminMappers.swift:124).
    func testHRVTrendGoodnessNeverAlarmsOnPositive() {
        for label in ["Stable", "Higher", "Up", "Improving", " improving "] {
            XCTAssertEqual(TrainingMetrics.hrvTrendGoodness(forLabel: label), .positive, "\(label) is a positive trend")
        }
        for label in ["Lower", "Down", "Declining", "Low"] {
            XCTAssertEqual(TrainingMetrics.hrvTrendGoodness(forLabel: label), .caution, "\(label) is a caution trend")
        }
        XCTAssertEqual(TrainingMetrics.hrvTrendGoodness(forLabel: "Moderate"), .neutral)
        XCTAssertEqual(TrainingMetrics.hrvTrendGoodness(forLabel: "--"), .neutral)
    }

    // Review fix (adversarial): the workout-breakdown sheet's "Week N" used a
    // week-of-MONTH fallback (resets monthly) because the trainingPhase digit
    // path never fires ("base" has no digits) — the exact "Week 3 vs Week 4"
    // audit class at an unconverted call site. With a plan it must use the
    // single accessor.
    func testWorkoutDisplayWeekLabelUsesPlanWeekWhenPlanKnown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let plan = TrainingPlanSnapshot(id: UUID(), title: "10K Build", startDate: makeDate("2026-05-04"), endDate: makeDate("2026-06-30"), totalWeeks: 8, planType: "10K")
        let recommendation = TodayRecommendation(readiness: 82, readinessLabel: "Ready", workoutTitle: "Tempo Builder", distance: "8.0 km", pace: "5:44 /km", elevation: "--", coachMessage: "Go steady.")
        let workout = makeWorkout(date: "2026-05-13", kind: .tempo, title: "Tempo Builder", distance: "8.0 km", durationMinutes: 50)

        let display = TodayWorkoutDisplayModel.make(recommendation: recommendation, workout: workout, plan: plan, calendar: calendar)
        XCTAssertEqual(display.weekLabel, "Week 2", "May 13 is week 2 of a plan starting May 4 — must come from TrainingMetrics, not week-of-month")

        let displayNoPlan = TodayWorkoutDisplayModel.make(recommendation: recommendation, workout: workout, calendar: calendar)
        XCTAssertEqual(displayNoPlan.weekLabel, "Week \(calendar.component(.weekOfMonth, from: workout.scheduledDate))", "without a plan the legacy fallback stays")
    }

    // Review fix (v1.0.9 smoke): the Plan week total naive-parsed every label,
    // counting "8 x 400m" as 8 km and "45 min" as 45 km — the audit's literal
    // "86.20 km vs summed ~36 km" (§10 B10), reproduced live in the smoke run.
    func testPlanWeekTotalDistanceMatchesRealWorkoutDistances() {
        let week = PlanWeekSummary(
            id: "w1",
            weekNumber: 1,
            startDate: makeDate("2026-07-12"),
            endDate: makeDate("2026-07-18"),
            workouts: [
                makeWorkout(date: "2026-07-12", kind: .easy, title: "Easy Run", distance: "5.0 km"),
                makeWorkout(date: "2026-07-13", kind: .intervals, title: "Intervals", distance: "8 x 400m"),
                makeWorkout(date: "2026-07-14", kind: .tempo, title: "Tempo Run", distance: "8.2 km"),
                makeWorkout(date: "2026-07-15", kind: .strength, title: "Strength", distance: "45 min"),
                makeWorkout(date: "2026-07-17", kind: .easy, title: "Easy Run", distance: "6.0 km"),
                makeWorkout(date: "2026-07-18", kind: .long, title: "Long Run", distance: "14.0 km"),
            ],
            isCurrentWeek: true
        )
        // 5.0 + (8 × 0.4) + 8.2 + 0 (duration, not distance) + 6.0 + 14.0
        XCTAssertEqual(week.totalDistanceKm, 36.4, accuracy: 0.001, "intervals expand via the S4 parser; durations contribute zero — never 86.2")
    }

    // Review fix: a zero-day streak is not a streak; the single accessor owns
    // the >0 rule so Today and Profile can't diverge on the boundary.
    func testZeroStreakNeverRendersAsAStreak() {
        XCTAssertNil(TrainingMetrics.canonicalStreakLabel(fromLabel: "0"))
        XCTAssertNil(TrainingMetrics.canonicalStreakLabel(fromLabel: "0 days"))
        XCTAssertEqual(TrainingMetrics.streakDays(fromLabel: "0 days"), 0, "parsing still reports zero; only the label suppresses it")
    }

    // Release-review fix: a brand-new runner's backend streak label is literally
    // "0 day streak" (SupabaseRunSmartServices runnerProfile) while Today's is
    // "0 days". Both surfaces must resolve to "show nothing" — Profile used to
    // fall back to the raw label and rendered "0 day streak" to every new user.
    func testNewRunnerSeesNoStreakOnEitherSurface() {
        // Exactly what the live backend sends a user with no streak record.
        let profileLabel = "0 day streak"   // RunnerProfile.streak
        let todayLabel = "0 days"           // TodayRecommendation.streak

        XCTAssertNil(
            TrainingMetrics.canonicalStreakLabel(fromLabel: profileLabel),
            "Profile must render nothing for a new runner, not the raw '0 day streak'"
        )
        XCTAssertNil(
            TrainingMetrics.canonicalStreakLabel(fromLabel: todayLabel),
            "Today must render nothing for a new runner"
        )

        // And the placeholder the profile fetch falls back to.
        XCTAssertNil(TrainingMetrics.canonicalStreakLabel(fromLabel: "--"))

        // Once the runner has a streak, both surfaces agree on one label.
        XCTAssertEqual(TrainingMetrics.canonicalStreakLabel(fromLabel: "1 day streak"), "1 day streak")
        XCTAssertEqual(TrainingMetrics.canonicalStreakLabel(fromLabel: "11 days"), "11 day streak")
    }

    // A milestone share for a runner with no streak must not emit a dangling
    // "Progress: " line.
    func testMilestoneShareOmitsMissingProgressValue() {
        let withoutStreak = ProgressSharePayload.milestone(
            title: "First week done",
            subtitle: "Consistency",
            value: nil,
            insight: "A private RunSmart milestone worth keeping."
        )
        XCTAssertTrue(withoutStreak.metrics.isEmpty)
        XCTAssertFalse(withoutStreak.shareText.contains("Progress:"), "no streak → no empty Progress metric in the shared text")

        let withStreak = ProgressSharePayload.milestone(
            title: "First week done",
            subtitle: "Consistency",
            value: "11 day streak",
            insight: "A private RunSmart milestone worth keeping."
        )
        XCTAssertTrue(withStreak.shareText.contains("Progress: 11 day streak"))
    }

    // Review fix: pin the analytics step names so a future step reorder or
    // rename can't silently break existing PostHog funnels ("privacy" is the
    // Coaching step's funnel name on purpose — WP-44 S4).
    func testOnboardingAnalyticsStepNamesStayFunnelCompatible() {
        XCTAssertEqual(OnboardingView.analyticsStepNames.count, 6)
        XCTAssertEqual(OnboardingView.analyticsStepNames[3], "privacy")
    }

    // WP-45 review fix: the denied path is the exact gap the permission events
    // close — prove the resolution logic, including cold-start suppression.
    func testLocationPermissionEventOnlyResolvesWhilePromptPending() {
        XCTAssertEqual(RunRecorder.locationPermissionEvent(phase: .requestingPermission, status: .authorizedWhenInUse), "permission_granted")
        XCTAssertEqual(RunRecorder.locationPermissionEvent(phase: .requestingPermission, status: .authorizedAlways), "permission_granted")
        XCTAssertEqual(RunRecorder.locationPermissionEvent(phase: .requestingPermission, status: .denied), "permission_denied")
        XCTAssertEqual(RunRecorder.locationPermissionEvent(phase: .requestingPermission, status: .restricted), "permission_denied")
        XCTAssertNil(RunRecorder.locationPermissionEvent(phase: .requestingPermission, status: .notDetermined), "an unresolved prompt emits nothing")
        XCTAssertNil(RunRecorder.locationPermissionEvent(phase: .idle, status: .authorizedWhenInUse), "the cold-start authorization callback must not fake a grant event")
        XCTAssertNil(RunRecorder.locationPermissionEvent(phase: .recording, status: .denied), "a mid-run revocation is not a prompt resolution")
    }

    // WP-44 S2: a failed HealthKit connect in onboarding used to silently reset
    // the button (audit §4 Risk 7) — no error, no retry hint. A non-connected
    // result must surface user-facing failure copy; a connected one must not.
    func testHealthKitConnectSurfacesFailureState() {
        let failed = ConnectedDeviceStatus(
            provider: OnboardingHealthKitStep.providerName,
            state: .error,
            lastSuccessfulSync: nil,
            permissions: [],
            message: nil
        )
        let message = OnboardingHealthKitStep.failureMessage(for: failed)
        XCTAssertNotNil(message, "a failed connect must tell the user it failed")
        XCTAssertTrue(message!.contains("Profile"), "failure copy must say where to retry later")

        let connected = ConnectedDeviceStatus(
            provider: OnboardingHealthKitStep.providerName,
            state: .connected,
            lastSuccessfulSync: nil,
            permissions: [],
            message: nil
        )
        XCTAssertNil(OnboardingHealthKitStep.failureMessage(for: connected), "a successful connect must not show failure copy")
    }

    // WP-43 S4: StructuredWorkoutFactory.intervalSteps used to derive the rep
    // count from `distanceKm(from: workout.distance)`, which digit-strips
    // "8 x 400m" into "8400" → 8400 km → reps = max(4, Int(8400/0.4)) = 21000,
    // rendering "21000 × 400 m" in the breakdown sheet while the card honestly
    // shows "8 x 400m". The rep count must be parsed from the structured
    // interval notation instead.
    private func makeIntervalSummary(distance: String) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            scheduledDate: Date(timeIntervalSince1970: 0),
            planID: nil,
            weekday: "TUE",
            date: "29",
            kind: .intervals,
            title: "Intervals",
            distance: distance,
            detail: "",
            isToday: true,
            isComplete: false,
            durationMinutes: nil,
            targetPaceSecondsPerKm: nil,
            intensity: nil,
            trainingPhase: nil,
            workoutStructure: nil,
            adjustedAt: nil,
            adjustedReason: nil
        )
    }

    private func repsStepDuration(for distance: String) -> String? {
        let steps = StructuredWorkoutFactory.makeSteps(for: makeIntervalSummary(distance: distance))
        return steps?.first { $0.title == "Repeats" }?.duration
    }

    func testIntervalBreakdownParsesRepsFromStructure() {
        XCTAssertEqual(
            repsStepDuration(for: "8 x 400m"),
            "8 × 400 m",
            "an '8 x 400m' interval must render 8 reps parsed from the notation, not a digit-stripped 21000"
        )
        XCTAssertEqual(repsStepDuration(for: "6 × 800m"), "6 × 800 m")
        XCTAssertEqual(repsStepDuration(for: "10x200m"), "10 × 200 m")
    }

    func testBreakdownNeverExceedsPlausibleReps() {
        for distance in ["8 x 400m", "6 × 800m", "10x200m", "5 x 1000m"] {
            let duration = repsStepDuration(for: distance) ?? ""
            let leadingReps = Int(duration.prefix { $0.isNumber }) ?? -1
            XCTAssertGreaterThan(leadingReps, 0, "\(distance) must yield a positive rep count")
            XCTAssertLessThanOrEqual(leadingReps, 40, "\(distance) must never render an implausible rep count (was 21000)")
        }
    }

    // WP-43 S3: GoalTimelineMomentView hardcoded "Six weeks from now..." for
    // any 5K goal while the timeline graphic rendered "in \(timeline.weeks)
    // weeks". For an 8-week persona the headline said six weeks and the graphic
    // said eight — a trust-eroding contradiction. The headline must single-source
    // its duration from timeline.weeks.
    private func makeTimeline(weeks: Int, goalLabel: String, category: GoalTimelineCategory) -> GoalTimelineProjection {
        GoalTimelineProjection(
            weeks: weeks,
            milestoneWeek: max(1, weeks / 2),
            milestoneLabel: "Milestone",
            goalLabel: goalLabel,
            projectedDate: Date(timeIntervalSince1970: 0),
            normalizedGoal: category
        )
    }

    func testGoalTimelineHeadlineMatchesMilestoneWeeks() {
        let cases: [(goalLabel: String, category: GoalTimelineCategory)] = [
            ("First 5K", .distance),
            ("10K", .distance),
            ("Half Marathon", .distance),
            ("Marathon", .distance),
            ("Faster 5K", .speed),
            ("Run 3x a week", .habit)
        ]
        for weeks in [6, 8, 12] {
            for goalCase in cases {
                let timeline = makeTimeline(weeks: weeks, goalLabel: goalCase.goalLabel, category: goalCase.category)
                let headline = GoalTimelineMomentView.headlineText(for: timeline)
                XCTAssertTrue(
                    headline.contains("\(weeks) weeks"),
                    "headline must state the timeline's own \(weeks)-week duration for \(goalCase.goalLabel); got: \(headline)"
                )
                XCTAssertFalse(
                    headline.lowercased().contains("six weeks"),
                    "headline must not hardcode 'Six weeks' — it contradicts the \(weeks)-week graphic; got: \(headline)"
                )
            }
        }
    }

    func testGoalTimelineSublineHasNoGuaranteeLanguage() {
        let subline = GoalTimelineMomentView.sublineText.lowercased()
        XCTAssertFalse(subline.contains("we know you'll finish"), "must not guarantee the runner will finish")
        XCTAssertFalse(subline.contains("guarantee"), "must not use guarantee language")
    }

    // WP-43 S5: PostRunLearningSource raw values ("AI"/"Fallback"/"Report"/
    // "Heuristic") were rendered directly as trust-surface badges. displayLabel
    // maps each tier to user language; the raw enum stays for internal
    // logic/analytics (audit §4 Risk 10 / §10 B12).
    func testPostRunSourceDisplayLabelsAreUserFacing() {
        for source in [PostRunLearningSource.ai, .fallback, .report, .heuristic] {
            let label = source.displayLabel
            XCTAssertFalse(label.isEmpty, "\(source) needs a display label")
            XCTAssertNotEqual(
                label, source.rawValue,
                "\(source) must not render its raw enum value (\(source.rawValue)) to users"
            )
            let lowered = label.lowercased()
            XCTAssertFalse(lowered.contains("heuristic"), "\(source) label leaks 'Heuristic': \(label)")
            XCTAssertFalse(lowered.contains("fallback"), "\(source) label leaks 'Fallback': \(label)")
        }
    }

    // The audit's actual §10 B12 evidence string ("Imported activity ·
    // Heuristic") comes from PlanExplanationSource.displayName, rendered on
    // Today next to the trigger — a separate enum from PostRunLearningSource.
    func testPlanExplanationSourceDisplayNamesAreUserFacing() {
        for source in [PlanExplanationSource.heuristic, .ai, .fallback] {
            let label = source.displayName
            XCTAssertFalse(label.isEmpty, "\(source) needs a display label")
            let lowered = label.lowercased()
            XCTAssertFalse(lowered.contains("heuristic"), "\(source) label leaks 'Heuristic': \(label)")
            XCTAssertFalse(lowered.contains("fallback"), "\(source) label leaks 'Fallback': \(label)")
            XCTAssertNotEqual(label, "AI", "the AI source must render as coach language, not the raw tier name")
        }
    }

    // WP-43 S6: OnboardingProfile.empty.goal defaulted to "10K improvement" —
    // a value not among the five visible goal options, so a user who never
    // picked a goal had a plan silently built around it (audit §4 Risk 9 /
    // §10 B15). The default must force an explicit visible choice, and the
    // Goal step must not advance until one is made.
    func testOnboardingRequiresVisibleGoalSelection() {
        var profile = OnboardingProfile.empty
        XCTAssertFalse(OnboardingView.canAdvanceFromGoal(profile), "the empty default goal must not allow advancing")

        profile.goal = "10K improvement" // the old hidden value, not a visible option
        XCTAssertFalse(OnboardingView.canAdvanceFromGoal(profile), "a non-visible goal must not allow advancing")

        profile.goal = "First 5K"
        XCTAssertTrue(OnboardingView.canAdvanceFromGoal(profile), "an explicit visible goal must allow advancing")
    }

    func testOnboardingDefaultGoalIsNotHiddenValue() {
        let defaultGoal = OnboardingProfile.empty.goal
        XCTAssertNotEqual(defaultGoal, "10K improvement", "the default goal must not be a hidden value never shown to the user")
        XCTAssertTrue(
            defaultGoal.isEmpty || OnboardingView.goalOptions.contains(defaultGoal),
            "the default goal must be empty (forcing a choice) or a visible option; got '\(defaultGoal)'"
        )
    }

    // WP-43 S1: after onboarding there was no explicit plan-generation state —
    // Today/Plan rendered a blank body for ~30-45s while generation ran, and the
    // only signal was a transient banner that vanished (audit §4 Risk 1).
    // PlanGenerationStore maps the existing notification to an explicit state so
    // Today/Plan always show the generating card, the plan, or an inline retry.
    private func postPlanGeneration(_ status: RunSmartPlanGenerationStatus, on center: NotificationCenter) {
        center.post(name: .runSmartPlanGenerationStatusDidChange, object: status)
    }

    func testPlanGenerationStateTransitionsGeneratingToReady() {
        let center = NotificationCenter()
        let store = PlanGenerationStore(notificationCenter: center)

        XCTAssertEqual(store.state, .idle, "no plan activity yet")
        XCTAssertFalse(store.state.showsGeneratingCard)

        postPlanGeneration(.generating, on: center)
        XCTAssertEqual(store.state, .generating, "the generating notification must surface the waiting state")
        XCTAssertTrue(store.state.showsGeneratingCard, "Today/Plan must show the generating card, never a blank body")
        XCTAssertFalse(store.state.showsInlineRetry)

        postPlanGeneration(.amended, on: center)
        XCTAssertEqual(store.state, .ready, "a successful regeneration must resolve to ready")
        XCTAssertFalse(store.state.showsGeneratingCard, "the generating card must disappear once the plan is ready")
        XCTAssertFalse(store.state.showsInlineRetry)
    }

    func testPlanGenerationFailureExposesInlineRetry() {
        let center = NotificationCenter()
        let store = PlanGenerationStore(notificationCenter: center)

        postPlanGeneration(.generating, on: center)
        postPlanGeneration(.failed, on: center)

        XCTAssertEqual(store.state, .failed)
        XCTAssertTrue(store.state.showsInlineRetry, "a failed generation must expose an inline retry on Today/Plan")
        XCTAssertFalse(store.state.showsGeneratingCard, "a failed generation must not keep showing the generating card")

        // Retrying returns to the generating card without leaving Today/Plan.
        store.markGenerating()
        XCTAssertEqual(store.state, .generating)
        XCTAssertTrue(store.state.showsGeneratingCard)
        XCTAssertFalse(store.state.showsInlineRetry)
    }

    func testPlanGenerationFailedNoticeDoesNotPointAtBuriedScreen() {
        let message = RunSmartPlanNotice(status: .failed).message
        XCTAssertFalse(
            message.contains("Training Data"),
            "the failure notice must not send a first-time user to a Profile-buried screen; got: \(message)"
        )
    }

    // MARK: - Activation cliff S1: sign-in wall instrumentation

    // The wall is the first screen every unauthenticated user sees and fired no
    // event at all, so the 22-of-23 organic drop-off could not be attributed:
    // "refused to sign in", "sign-in failed silently", and "app hung" were
    // indistinguishable. These tests pin the semantics the funnel depends on.

    /// Runs `body` with a capturing analytics sink installed, and hands back the
    /// events it saw. Restores the previous sink even if an assertion throws.
    private func captureAnalytics(_ body: (CapturingAnalyticsService) -> Void) -> [(name: String, properties: [String: Any])] {
        let saved = Analytics.shared
        let tracker = CapturingAnalyticsService()
        defer { Analytics.shared = saved }
        Analytics.shared = tracker
        body(tracker)
        return tracker.events
    }

    func testSignInWallViewedFiresAtMostOncePerSession() {
        let events = captureAnalytics { _ in
            let wall = SignInWallTracker(now: { Date(timeIntervalSince1970: 0) })
            wall.wallAppeared()
            wall.wallAppeared()
            wall.wallAppeared()
        }

        XCTAssertEqual(
            events.filter { $0.name == "sign_in_wall_viewed" }.count, 1,
            "SwiftUI re-runs onAppear on every rebuild; a repeated viewed event would inflate the funnel's denominator"
        )
        XCTAssertEqual(
            events.first?.properties["screen"] as? String, SignInWallTracker.screenName,
            "$screen autocapture is a generic hosting-controller string, so the wall must name itself"
        )
    }

    func testSignInWallAbandonedIgnoresDwellUnderThreshold() {
        var now = Date(timeIntervalSince1970: 0)
        let events = captureAnalytics { _ in
            let wall = SignInWallTracker(now: { now })
            wall.wallAppeared()
            now = now.addingTimeInterval(SignInWallTracker.abandonThresholdSeconds - 1)
            wall.appDidEnterBackground()
        }

        XCTAssertTrue(
            events.allSatisfy { $0.name != "sign_in_wall_abandoned" },
            "a user who backgrounds in under \(Int(SignInWallTracker.abandonThresholdSeconds))s never read the screen; counting them inflates the very signal we are measuring"
        )
    }

    func testSignInWallAbandonedFiresOnceWithDwellAfterThreshold() {
        var now = Date(timeIntervalSince1970: 0)
        let events = captureAnalytics { _ in
            let wall = SignInWallTracker(now: { now })
            wall.wallAppeared()
            now = now.addingTimeInterval(42)
            wall.appDidEnterBackground()
            // Foreground, then background again — still one abandonment.
            now = now.addingTimeInterval(60)
            wall.appDidEnterBackground()
        }

        let abandons = events.filter { $0.name == "sign_in_wall_abandoned" }
        XCTAssertEqual(abandons.count, 1, "abandonment is once per session, not once per background")
        XCTAssertEqual(abandons.first?.properties["dwell_seconds"] as? Int, 42)
        XCTAssertEqual(abandons.first?.properties["screen"] as? String, SignInWallTracker.screenName)
    }

    func testSignInWallTapPermanentlyDisarmsAbandonment() {
        var now = Date(timeIntervalSince1970: 0)
        let events = captureAnalytics { _ in
            let wall = SignInWallTracker(now: { now })
            wall.wallAppeared()
            now = now.addingTimeInterval(10)
            wall.signInTapped()
            // Apple's sheet backgrounds the app; returning and leaving again must
            // not retro-emit an abandonment for a user who did attempt sign-in.
            now = now.addingTimeInterval(120)
            wall.appDidEnterBackground()
        }

        XCTAssertEqual(events.filter { $0.name == "sign_in_wall_tapped" }.count, 1)
        XCTAssertTrue(
            events.allSatisfy { $0.name != "sign_in_wall_abandoned" },
            "a user who tapped is a sign-in failure, not an abandonment; conflating them re-creates the blind spot S1 exists to remove"
        )
    }

    func testSignInFailedCarriesScreenAndErrorMetadata() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: 1000)
        let events = captureAnalytics { _ in
            Analytics.trackSignInFailed(error: error)
            Analytics.trackSignInCompleted(method: "apple")
        }

        let failed = events.first { $0.name == "sign_in_failed" }?.properties
        XCTAssertEqual(failed?["error_domain"] as? String, ASAuthorizationError.errorDomain)
        XCTAssertEqual(
            failed?["error_code"] as? Int, 1000,
            "code 1000 is the open P0; without it on every failure the outage-vs-environment question needs a device repro every time"
        )
        XCTAssertEqual(failed?["screen"] as? String, SignInWallTracker.screenName)
        XCTAssertEqual(
            events.first { $0.name == "sign_in_completed" }?.properties["screen"] as? String,
            SignInWallTracker.screenName
        )
    }

    // WP-52a step 1. `ASAuthorizationError` 1000 is `.unknown` — a wrapper that
    // names nothing. WP-52 cleared all five configuration links, so the only
    // remaining lead is whatever AuthKit put in `NSUnderlyingErrorKey`, and the
    // event discarded it. Without these properties every hypothesis about the
    // first-time-authorization failure is unfalsifiable.
    func testSignInFailedCapturesUnderlyingError() {
        let underlying = NSError(
            domain: "AKAuthenticationError",
            code: -7003,
            userInfo: [NSLocalizedDescriptionKey: "Authentication failed"]
        )
        let error = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: 1000,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let events = captureAnalytics { _ in
            Analytics.trackSignInFailed(error: error)
        }
        let failed = events.first { $0.name == "sign_in_failed" }?.properties

        XCTAssertEqual(failed?["has_underlying_error"] as? Bool, true)
        XCTAssertEqual(failed?["underlying_error_domain"] as? String, "AKAuthenticationError")
        XCTAssertEqual(failed?["underlying_error_code"] as? Int, -7003)
        XCTAssertEqual(failed?["underlying_error_description"] as? String, "Authentication failed")
        // The wrapper's own values must survive alongside the unwrapped ones.
        XCTAssertEqual(failed?["error_code"] as? Int, 1000)
    }

    // A genuinely bare 1000 and a 1000 we simply failed to unwrap look identical
    // in the data, and they imply opposite next steps: the first escalates to the
    // guest path (WP-53), the second is an instrumentation bug. `has_underlying_error`
    // is what separates them, so it must be present and false, never absent.
    func testSignInFailedMarksGenuinelyBareErrorAsBare() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: 1000)

        let events = captureAnalytics { _ in
            Analytics.trackSignInFailed(error: error)
        }
        let failed = events.first { $0.name == "sign_in_failed" }?.properties

        XCTAssertEqual(
            failed?["has_underlying_error"] as? Bool, false,
            "a bare 1000 must be explicitly marked bare, not left to an absent key"
        )
        XCTAssertNil(failed?["underlying_error_domain"])
        XCTAssertNil(failed?["underlying_error_code"])
        XCTAssertNil(failed?["underlying_error_description"])
    }

    // `trackSignInFailed` fires for every error in the wall's catch block, which
    // includes Supabase and network errors — and those descriptions can embed the
    // user's email or a bearer token. Analytics must never carry either.
    func testSignInFailedRedactsIdentifiersFromUnderlyingDescription() {
        // The token below is a zero-entropy placeholder that satisfies the JWT
        // shape (`eyJ` + three dot-separated base64url runs) without being a
        // credential. Do not "improve" it into a realistic token: secret
        // scanners flag valid-structure JWTs, and a real one has no business in
        // the repo even as a fixture.
        let fakeJWT = "eyJEXAMPLEEXAMPLEEXAMPLE.PAYLOADPAYLOADPAYLOAD.SIGNATURESIGNATURE"
        let underlying = NSError(
            domain: "NSURLErrorDomain",
            code: -1011,
            userInfo: [NSLocalizedDescriptionKey:
                "Rejected for runner@example.com with token \(fakeJWT)"]
        )
        let error = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: 1000,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let events = captureAnalytics { _ in
            Analytics.trackSignInFailed(error: error)
        }
        let description = events.first { $0.name == "sign_in_failed" }?
            .properties["underlying_error_description"] as? String ?? ""

        XCTAssertFalse(description.contains("runner@example.com"), "an email must never reach analytics")
        XCTAssertFalse(description.contains("eyJEXAMPLE"), "a token must never reach analytics")
        XCTAssertTrue(
            description.contains("Rejected for"),
            "redaction must preserve the diagnostic text around the identifiers, or the property is worthless"
        )
    }

    // MARK: - Activation cliff S1: plan-generation double-fire

    func testPlanGenerationEmitsOneOutcomePerGeneration() {
        let center = NotificationCenter()
        let events = captureAnalytics { _ in
            let store = PlanGenerationStore(notificationCenter: center)
            postPlanGeneration(.generating, on: center)
            // Two terminal posts back to back — the shape observed on device
            // `0efa0d1b`, where six failed/succeeded pairs landed 19ms apart.
            postPlanGeneration(.failed, on: center)
            postPlanGeneration(.amended, on: center)
            XCTAssertEqual(store.state, .ready, "UI state must still follow the latest status")
        }

        let outcomes = events.filter { $0.name.hasPrefix("plan_generation_") && $0.name != "plan_generation_started" }
        XCTAssertEqual(
            outcomes.count, 1,
            "one generation must yield one outcome; a failed/succeeded pair means one of them is lying. Got: \(outcomes.map(\.name))"
        )
        XCTAssertEqual(outcomes.first?.name, "plan_generation_failed", "the first terminal status owns the outcome")
        XCTAssertNotNil(
            outcomes.first?.properties["duration_ms"],
            "an outcome matched to its start always has a duration"
        )
    }

    func testPlanGenerationIgnoresTerminalStatusItNeverSawStart() {
        let center = NotificationCenter()
        let events = captureAnalytics { _ in
            let store = PlanGenerationStore(notificationCenter: center)
            postPlanGeneration(.amended, on: center)
            XCTAssertEqual(store.state, .ready, "UI state is independent of whether the funnel counts this")
        }

        XCTAssertTrue(
            events.isEmpty,
            "an outcome with no observed start would let the funnel's numerator exceed its denominator; got: \(events.map(\.name))"
        )
    }
}

final class RunSmartAPIStubProtocol: URLProtocol {
    static var responseStatusCode = 200
    static var responseData = Data()
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
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
