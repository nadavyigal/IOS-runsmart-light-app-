import XCTest
@testable import IOS_RunSmart_app

final class FlexWeekTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Deterministic builder

    func testTiredDowngradesTodaysHardWorkout() {
        let week = sampleWeek(hardToday: true)
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .tired,
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[2].kind, .easy)
        XCTAssertTrue(changes.contains { $0.changeType == .downgraded })
        XCTAssertTrue(changes.contains { $0.rationale.localizedCaseInsensitiveContains("RECOVERY") })
    }

    func testTiredOnRestDayEasesNextHardWorkout() {
        let week = sampleWeek(hardToday: false, restToday: true)
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .tired,
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[2].distance, "Rest")
        XCTAssertFalse(updated[4].kind == .long)
        XCTAssertTrue(changes.count >= 1)
    }

    func testTravelingMarksBlockedDaysAsRest() {
        let week = sampleWeek(hardToday: false)
        let blocked = [week[3].scheduledDate, week[4].scheduledDate]
        let (_, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .traveling(blockedDays: blocked),
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertTrue(changes.contains { $0.changeType == .rest })
        XCTAssertTrue(changes.contains { $0.rationale.localizedCaseInsensitiveContains("travel") })
    }

    func testTravelingDoesNotCreateBackToBackHardDays() {
        var week = sampleWeek(hardToday: false)
        week[3] = workout(
            offset: 3,
            kind: .tempo,
            title: "Tempo Run",
            distance: "8.0 km",
            from: week[0].scheduledDate
        )
        week[4] = workout(
            offset: 4,
            kind: .intervals,
            title: "Intervals",
            distance: "6.0 km",
            from: week[0].scheduledDate
        )

        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .traveling(blockedDays: [week[3].scheduledDate]),
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[3].distance, "Rest")
        XCTAssertTrue(changes.count >= 1)
        XCTAssertFalse(hasBackToBackHardSessions(in: updated))
    }

    func testMissedEasyWorkoutIsDropped() {
        var week = sampleWeek(hardToday: false)
        week[1] = workout(
            offset: 1,
            kind: .easy,
            title: "Easy Run",
            distance: "5.0 km",
            from: week[0].scheduledDate
        )
        let missed = week[1]
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .missedWorkout(workoutID: missed.id),
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[1].distance, "Rest")
        XCTAssertTrue(changes.contains { $0.changeType == .dropped })
    }

    func testMissedHardWorkoutMovesToOpenTomorrow() {
        let week = sampleWeek(hardToday: false)
        let missed = week[1]
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .missedWorkout(workoutID: missed.id),
            now: week[1].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[1].distance, "Rest")
        XCTAssertTrue(changes.contains { $0.changeType == .moved })
        XCTAssertEqual(updated[2].title, missed.title)
    }

    func testMissedWorkoutRestructureKeepsWorkoutIDsUnique() {
        // Regression: the rescheduled copy of a missed workout kept its original
        // UUID while the vacated slot (turned into rest) kept the same UUID,
        // producing two rows with one identity and breaking SwiftUI diffing.
        let week = sampleWeek(hardToday: false)
        let missed = week[1]
        let (updated, _) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .missedWorkout(workoutID: missed.id),
            now: week[1].scheduledDate,
            calendar: calendar
        )

        let ids = updated.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Restructured week must not contain duplicate workout IDs")
    }

    func testTravelingRestructureKeepsWorkoutIDsUnique() {
        // Same identity bug on the traveling path: a displaced hard workout
        // moved into an open slot kept its original UUID alongside its old
        // slot's rest-day copy.
        var week = sampleWeek(hardToday: false)
        week[3] = workout(
            offset: 3,
            kind: .tempo,
            title: "Tempo Run",
            distance: "8.0 km",
            from: week[0].scheduledDate
        )

        let (updated, _) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .traveling(blockedDays: [week[3].scheduledDate]),
            now: week[2].scheduledDate,
            calendar: calendar
        )

        let ids = updated.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Restructured week must not contain duplicate workout IDs")
    }

    func testMissedHardWorkoutDoesNotStackOnHardTomorrow() {
        var week = sampleWeek(hardToday: true)
        week[1] = workout(
            offset: 1,
            kind: .intervals,
            title: "Missed Intervals",
            distance: "6.0 km",
            from: week[0].scheduledDate
        )
        let missed = week[1]
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .missedWorkout(workoutID: missed.id),
            now: week[1].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[1].distance, "Rest")
        XCTAssertTrue(changes.contains { $0.rationale.localizedCaseInsensitiveContains("back-to-back") || $0.changeType == .rest })
        XCTAssertNotEqual(updated[2].title, missed.title)
        XCTAssertFalse(hasBackToBackHardSessions(in: updated))
    }

    func testSickMarksRecoveryWindowAsRest() {
        let week = sampleWeek(hardToday: false)
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .sick(daysOut: 4),
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertTrue(updated[2...4].allSatisfy { $0.distance == "Rest" })
        XCTAssertTrue(changes.contains { $0.rationale.localizedCaseInsensitiveContains("recover") })
    }

    func testSickDowngradesFirstWorkoutAfterRecoveryWindow() {
        var week = sampleWeek(hardToday: false)
        week[6] = workout(
            offset: 6,
            kind: .long,
            title: "Long Run",
            distance: "14.0 km",
            from: week[0].scheduledDate
        )
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .sick(daysOut: 3),
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated[6].kind, .easy)
        XCTAssertTrue(changes.contains { $0.rationale.localizedCaseInsensitiveContains("first run back") })
    }

    func testTaperWeekReturnsLockedSchedule() {
        var week = sampleWeek(hardToday: true)
        week = week.map { workout in
            var copy = workout
            copy.trainingPhase = "Taper"
            return copy
        }

        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .tired,
            now: week[2].scheduledDate,
            calendar: calendar
        )

        XCTAssertEqual(updated, week)
        XCTAssertTrue(changes.contains { $0.rationale.localizedCaseInsensitiveContains("Taper week") })
    }

    func testRestructureAlwaysReturnsAtLeastOneChangeForTired() {
        let week = sampleWeek(hardToday: true)
        let (_, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .tired,
            now: week[2].scheduledDate,
            calendar: calendar
        )
        XCTAssertFalse(changes.isEmpty)
    }

    // MARK: - Presentation helpers

    func testMostRecentMissedWorkoutSkipsCompletedSessions() {
        let week = sampleWeek(hardToday: false)
        let missed = FlexWeekPresentation.mostRecentMissedWorkout(
            in: week,
            now: week[2].scheduledDate,
            calendar: calendar
        )
        XCTAssertEqual(missed?.id, week[1].id)
    }

    func testTravelingReasonRequiresBlockedDays() {
        let week = sampleWeek(hardToday: false)
        XCTAssertFalse(FlexWeekPresentation.isValid(.traveling(blockedDays: []), week: week))
        XCTAssertTrue(
            FlexWeekPresentation.isValid(.traveling(blockedDays: [week[3].scheduledDate]), week: week)
        )
    }

    func testApplicationHashIsStableForSameOutcome() {
        let week = sampleWeek(hardToday: true)
        let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .tired,
            now: week[2].scheduledDate,
            calendar: calendar
        )
        let outcome = FlexWeekOutcome(
            restructuredWeek: updated,
            changes: changes,
            safetyWarnings: [],
            source: .deterministicFallback
        )
        XCTAssertEqual(outcome.applicationHash, outcome.applicationHash)
    }

    func testApplicationHashChangesWhenWeekChanges() {
        let week = sampleWeek(hardToday: true)
        let (updatedA, changesA) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .tired,
            now: week[2].scheduledDate,
            calendar: calendar
        )
        let (updatedB, changesB) = DeterministicFlexWeekBuilder.restructure(
            week: week,
            reason: .traveling(blockedDays: [week[4].scheduledDate]),
            now: week[2].scheduledDate,
            calendar: calendar
        )
        let outcomeA = FlexWeekOutcome(restructuredWeek: updatedA, changes: changesA, safetyWarnings: [], source: .deterministicFallback)
        let outcomeB = FlexWeekOutcome(restructuredWeek: updatedB, changes: changesB, safetyWarnings: [], source: .deterministicFallback)
        XCTAssertNotEqual(outcomeA.applicationHash, outcomeB.applicationHash)
    }

    func testAppliedHashStoreMarksAndDetectsPlanApplication() {
        let planID = UUID()
        let hash = "abc123"
        FlexWeekAppliedHash.markApplied(hash: hash, planID: planID)
        XCTAssertTrue(FlexWeekAppliedHash.isApplied(hash: hash, planID: planID))
        XCTAssertFalse(FlexWeekAppliedHash.isApplied(hash: "other", planID: planID))
    }

    func testTodayLinkShowsForLowReadiness() {
        let week = sampleWeek(hardToday: false)
        XCTAssertTrue(
            FlexWeekEntryPresentation.shouldShowTodayLink(readiness: 42, weekWorkouts: week)
        )
    }

    func testTodayLinkShowsForMissedWorkout() {
        let week = sampleWeek(hardToday: false)
        XCTAssertTrue(
            FlexWeekEntryPresentation.shouldShowTodayLink(readiness: 82, weekWorkouts: week, now: week[2].scheduledDate, calendar: calendar)
        )
    }

    func testTodayLinkHiddenWhenOnTrack() {
        var week = sampleWeek(hardToday: false)
        week = week.map { workout in
            var copy = workout
            copy.isComplete = true
            return copy
        }
        XCTAssertFalse(
            FlexWeekEntryPresentation.shouldShowTodayLink(readiness: 82, weekWorkouts: week, now: week[2].scheduledDate, calendar: calendar)
        )
    }

    func testPreselectedMissedReasonUsesLatestMissedWorkout() {
        let week = sampleWeek(hardToday: false)
        let reason = FlexWeekEntryPresentation.preselectedMissedReason(from: week, now: week[2].scheduledDate, calendar: calendar)
        guard case .missedWorkout(let workoutID) = reason else {
            return XCTFail("Expected missed workout reason")
        }
        XCTAssertEqual(workoutID, week[1].id)
    }

    // MARK: - Service support (Story 3)

    func testFlexWeekRequestDTOEncodesReasonFields() {
        let week = sampleWeek(hardToday: false)
        let request = FlexWeekRequest(
            reason: .traveling(blockedDays: [week[3].scheduledDate]),
            currentWeek: week,
            readinessContext: nil
        )
        let dto = FlexWeekServiceSupport.buildRequestDTO(from: request)
        XCTAssertEqual(dto.reason, "traveling")
        XCTAssertEqual(dto.blockedDays?.count, 1)
        XCTAssertEqual(dto.currentWeek.count, week.count)
    }

    func testFlexWeekRequestDTOEncodesTrainingLoadFields() throws {
        var context = ReadinessContext(
            readiness: 42,
            readinessLabel: "Low",
            bodyBattery: 30,
            hrv: "38 ms",
            sleep: "6h 10m",
            recommendation: "Take it easy"
        )
        context.acwr = 1.62
        context.acuteLoad = 1780
        context.chronicLoad = 1100
        context.loadStatus = "highRisk"

        let request = FlexWeekRequest(reason: .tired, currentWeek: [], readinessContext: context)
        let dto = FlexWeekServiceSupport.buildRequestDTO(from: request)
        let data = try JSONEncoder().encode(dto)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"acwr\":1.62"), "missing acwr: \(json)")
        XCTAssertTrue(json.contains("\"acuteLoad\":1780"), "missing acuteLoad: \(json)")
        XCTAssertTrue(json.contains("\"chronicLoad\":1100"), "missing chronicLoad: \(json)")
        XCTAssertTrue(json.contains("\"loadStatus\":\"highRisk\""), "missing loadStatus: \(json)")
    }

    func testFlexWeekRequestDTOOmitsLoadFieldsWhenAbsent() throws {
        let context = ReadinessContext(
            readiness: 42,
            readinessLabel: "Low",
            bodyBattery: 30,
            hrv: "38 ms",
            sleep: "6h 10m",
            recommendation: "Take it easy"
        )
        let request = FlexWeekRequest(reason: .tired, currentWeek: [], readinessContext: context)
        let dto = FlexWeekServiceSupport.buildRequestDTO(from: request)
        let data = try JSONEncoder().encode(dto)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("acwr"), "nil load fields must be omitted, not null: \(json)")
    }

    func testReadinessContextMakeAttachesLoadOnlyWhenSufficient() {
        let recovery = RecoverySnapshot(
            readiness: 40, bodyBattery: 30, sleep: "6h", hrv: "38 ms",
            stress: "Low", recommendation: "Easy day"
        )
        let today = TodayRecommendation.placeholder

        let sufficient = TrainingLoadMetrics(acuteLoad: 900, chronicLoad: 600, acwr: 1.5, status: .highRisk)
        let withLoad = ReadinessContext.make(recovery: recovery, recommendation: today, load: sufficient)
        XCTAssertEqual(withLoad.acwr, 1.5)
        XCTAssertEqual(withLoad.loadStatus, "highRisk")

        let insufficient = TrainingLoadMetrics(acuteLoad: 0, chronicLoad: 0, acwr: nil, status: .insufficientData)
        let withoutLoad = ReadinessContext.make(recovery: recovery, recommendation: today, load: insufficient)
        XCTAssertNil(withoutLoad.acwr)
        XCTAssertNil(withoutLoad.loadStatus)
    }

    func testFlexWeekRequestDTOUsesEdgeFunctionKeySpelling() throws {
        let week = sampleWeek(hardToday: false)
        let request = FlexWeekRequest(
            reason: .missedWorkout(workoutID: week[1].id),
            currentWeek: week,
            readinessContext: nil
        )

        let dto = FlexWeekServiceSupport.buildRequestDTO(from: request)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(dto)
        ) as? [String: Any])
        let currentWeek = try XCTUnwrap(payload["currentWeek"] as? [[String: Any]])
        let firstWorkout = try XCTUnwrap(currentWeek.first)

        XCTAssertEqual(payload["intent"] as? String, "flex_week")
        XCTAssertEqual(payload["missedWorkoutId"] as? String, week[1].id.uuidString)
        XCTAssertNil(payload["missedWorkoutID"])
        XCTAssertEqual(firstWorkout["workoutId"] as? String, week[0].id.uuidString)
        XCTAssertNil(firstWorkout["workoutID"])
    }

    func testFlexWeekResponseDTODecodesEdgeFunctionKeySpelling() throws {
        let week = sampleWeek(hardToday: false)
        let json = """
        {
          "restructuredWeek": [
            {
              "workoutId": "\(week[0].id.uuidString)",
              "scheduledDate": "2026-05-19",
              "weekday": "MON",
              "dateLabel": "19",
              "kind": "easy",
              "title": "Easy Run",
              "distanceLabel": "5.0 km",
              "detailLabel": "Keep it relaxed.",
              "intensity": "easy",
              "trainingPhase": "base",
              "isToday": false,
              "isComplete": false,
              "originalWorkoutId": null
            }
          ],
          "changes": [
            {
              "workoutId": "\(week[0].id.uuidString)",
              "changeType": "downgraded",
              "rationale": "RECOVERY — made the session easier.",
              "originalWorkoutId": null
            }
          ],
          "safetyWarnings": [],
          "source": "live_ai"
        }
        """

        let dto = try JSONDecoder().decode(
            RunSmartDTO.FlexWeekResponseDTO.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(dto.restructuredWeek.first?.workoutID, week[0].id.uuidString)
        XCTAssertEqual(dto.changes.first?.workoutID, week[0].id.uuidString)
    }

    func testFlexWeekResponseDTODecodesLegacyAndSnakeCaseKeySpelling() throws {
        let week = sampleWeek(hardToday: false)
        let json = """
        {
          "restructured_week": [
            {
              "workout_id": "\(week[0].id.uuidString)",
              "scheduled_date": "2026-05-19",
              "weekday": "MON",
              "date_label": "19",
              "kind": "Recovery",
              "title": "Rest",
              "distance_label": "Rest",
              "detail_label": "Recovery",
              "intensity": "rest",
              "training_phase": "base",
              "is_today": false,
              "is_complete": false,
              "original_workout_id": null
            }
          ],
          "changes": [
            {
              "workoutID": "\(week[0].id.uuidString)",
              "change_type": "rest",
              "rationale": "Illness recovery comes before training load.",
              "originalWorkoutID": null
            }
          ],
          "safety_warnings": ["Keep this easy."],
          "source": "fallback"
        }
        """

        let dto = try JSONDecoder().decode(
            RunSmartDTO.FlexWeekResponseDTO.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(dto.restructuredWeek.first?.workoutID, week[0].id.uuidString)
        XCTAssertEqual(dto.restructuredWeek.first?.distanceLabel, "Rest")
        XCTAssertEqual(dto.changes.first?.workoutID, week[0].id.uuidString)
        XCTAssertEqual(dto.safetyWarnings, ["Keep this easy."])
    }

    func testFlexWeekOutcomeMapsValidAIResponse() {
        let week = sampleWeek(hardToday: true)
        let response = RunSmartDTO.FlexWeekResponseDTO(
            restructuredWeek: week.map {
                RunSmartDTO.FlexWeekWorkoutDTO(
                    workoutID: $0.id.uuidString,
                    scheduledDate: ISO8601DateFormatter.shortDate.string(from: $0.scheduledDate),
                    weekday: $0.weekday,
                    dateLabel: $0.date,
                    kind: $0.kind == .tempo ? WorkoutKind.easy.rawValue : $0.kind.rawValue,
                    title: $0.kind == .tempo ? "Easy Run" : $0.title,
                    distanceLabel: $0.distance,
                    detailLabel: $0.detail,
                    intensity: "easy",
                    trainingPhase: $0.trainingPhase,
                    isToday: $0.isToday,
                    isComplete: $0.isComplete,
                    originalWorkoutID: nil
                )
            },
            changes: [
                RunSmartDTO.FlexWeekChangeDTO(
                    workoutID: week[2].id.uuidString,
                    changeType: FlexWeekChangeType.downgraded.rawValue,
                    rationale: "RECOVERY — downgraded today's hard session to easy while you recharge.",
                    originalWorkoutID: nil
                )
            ],
            safetyWarnings: [],
            source: "live_ai"
        )

        let outcome = FlexWeekServiceSupport.outcome(from: response, originalWeek: week)
        XCTAssertEqual(outcome?.source, .ai)
        XCTAssertEqual(outcome?.restructuredWeek[2].kind, .easy)
        XCTAssertEqual(outcome?.changes.count, 1)
    }

    func testFlexWeekOutcomeRejectsMalformedAIResponse() {
        let week = sampleWeek(hardToday: true)
        let response = RunSmartDTO.FlexWeekResponseDTO(
            restructuredWeek: [],
            changes: [],
            safetyWarnings: nil,
            source: "live_ai"
        )
        XCTAssertNil(FlexWeekServiceSupport.outcome(from: response, originalWeek: week))
    }

    func testFlexWeekDeterministicFallbackOutcomeSource() {
        let week = sampleWeek(hardToday: true)
        let request = FlexWeekRequest(reason: .tired, currentWeek: week, readinessContext: nil)
        let outcome = FlexWeekServiceSupport.deterministicOutcome(for: request)
        XCTAssertEqual(outcome.source, .deterministicFallback)
        XCTAssertFalse(outcome.changes.isEmpty)
    }

    // MARK: - Fixtures

    private func sampleWeek(hardToday: Bool, restToday: Bool = false) -> [PlannedWorkout] {
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 19))!
        return [
            workout(offset: 0, kind: .easy, title: "Easy Run", distance: "5.0 km", from: start, isComplete: true),
            workout(offset: 1, kind: .tempo, title: "Tempo Run", distance: "8.0 km", from: start),
            workout(
                offset: 2,
                kind: restToday ? .recovery : (hardToday ? .tempo : .easy),
                title: restToday ? "Rest" : (hardToday ? "Tempo Run" : "Easy Run"),
                distance: restToday ? "Rest" : (hardToday ? "8.0 km" : "5.0 km"),
                from: start
            ),
            workout(offset: 3, kind: .easy, title: "Easy Run", distance: "6.0 km", from: start),
            workout(offset: 4, kind: .long, title: "Long Run", distance: "14.0 km", from: start),
            workout(offset: 5, kind: .recovery, title: "Recovery", distance: "Rest", from: start),
            workout(offset: 6, kind: .easy, title: "Easy Run", distance: "5.0 km", from: start)
        ]
    }

    private func workout(
        offset: Int,
        kind: WorkoutKind,
        title: String,
        distance: String,
        from start: Date,
        isComplete: Bool = false
    ) -> PlannedWorkout {
        let date = calendar.date(byAdding: .day, value: offset, to: start)!
        return PlannedWorkout(
            id: UUID(),
            scheduledDate: date,
            weekday: weekday(for: date),
            date: String(calendar.component(.day, from: date)),
            kind: kind,
            title: title,
            distance: distance,
            detail: "",
            isToday: offset == 2,
            isComplete: isComplete
        )
    }

    private func weekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func hasBackToBackHardSessions(in week: [PlannedWorkout]) -> Bool {
        let hardKinds: Set<WorkoutKind> = [.tempo, .intervals, .hills, .long, .race]
        for index in week.indices.dropLast() {
            if hardKinds.contains(week[index].kind), hardKinds.contains(week[index + 1].kind) {
                return true
            }
        }
        return false
    }
}
