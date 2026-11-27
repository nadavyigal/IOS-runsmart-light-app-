import XCTest
import Supabase
@testable import IOS_RunSmart_app

/// C8.5: the AI and the athlete side respect coach locks.
final class CoachLockTests: XCTestCase {
    private let planID = UUID()

    private func decodeWorkout(_ extra: [String: Any] = [:], id: UUID = UUID(), date: String = "2026-12-01") throws -> DBWorkout {
        var payload: [String: Any] = [
            "id": id.uuidString, "plan_id": planID.uuidString, "week": 1, "day": "Tue",
            "type": "tempo", "distance": 8.0, "completed": false, "scheduled_date": date,
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return try JSONDecoder().decode(DBWorkout.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func decodePlan(_ extra: [String: Any] = [:]) throws -> DBPlan {
        var payload: [String: Any] = [
            "id": planID.uuidString, "profile_id": UUID().uuidString, "title": "Plan",
            "start_date": "2026-11-01", "end_date": "2026-12-31", "total_weeks": 8,
            "is_active": true, "plan_type": "basic",
        ]
        extra.forEach { payload[$0.key] = $0.value }
        return try JSONDecoder().decode(DBPlan.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func summary(_ id: UUID, day: Int, locked: Bool = false, detail: String = "") -> WorkoutSummary {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: day))!
        return WorkoutSummary(
            id: id, scheduledDate: date, planID: planID, weekday: "MON", date: "\(day)", kind: .easy,
            title: "Easy Run", distance: "5.0 km", detail: detail, isToday: false, isComplete: false,
            coachLocked: locked
        )
    }

    // MARK: Schema before and after Batch C

    func testMissingLockColumnsDecodeAsUnlocked() throws {
        let before = try decodeWorkout()
        XCTAssertFalse(before.locked)
        XCTAssertNil(before.source)
        XCTAssertFalse(before.toWorkoutSummary().coachLocked)
        XCTAssertFalse(try decodeWorkout(["locked": NSNull()]).locked)

        let coach = try decodeWorkout(["locked": true, "source": "coach"])
        XCTAssertTrue(coach.locked)
        XCTAssertEqual(coach.source, "coach")
        XCTAssertTrue(coach.toWorkoutSummary().coachLocked)

        XCTAssertFalse(try decodePlan().isCoachPublished)
        XCTAssertFalse(try decodePlan(["coach_published": NSNull()]).isCoachPublished)
        XCTAssertTrue(try decodePlan(["coach_published": true]).isCoachPublished)
    }

    // MARK: AC 1

    func testLockedIdsReachLinkedRequestsOnlyAndSoloBytesStayTheSame() throws {
        let source = CoachContextSource()
        let owner = UUID()
        let locked = UUID()
        source.replaceLockedWorkouts([locked], ownerID: owner)

        source.replace(.solo, ownerID: owner)
        XCTAssertEqual(source.context(for: owner), .solo, "a solo athlete never carries locked ids")
        struct Payload: Encodable { let message: String }
        let plain = try JSONEncoder().encode(Payload(message: "hi"))
        XCTAssertEqual(try CoachRequestJSON.encode(Payload(message: "hi"), coach: source.context(for: owner)), plain)

        source.replace(CoachContext(coachDisplayName: "Dana", linkActive: true, lockedWorkoutIDs: []), ownerID: owner)
        XCTAssertEqual(source.context(for: owner).lockedWorkoutIDs, [locked.uuidString.lowercased()])
        XCTAssertEqual(source.context(for: UUID()), .solo)

        let other = UUID()
        source.replaceLockedWorkouts([UUID()], ownerID: other)
        XCTAssertEqual(source.context(for: owner).lockedWorkoutIDs, [], "another account's locks never leak")
    }

    func testOpenPainFlagIsEncodedOnlyWhenTrue() throws {
        struct Payload: Encodable { let message: String }
        var coach = CoachContext(coachDisplayName: "Dana", linkActive: true, lockedWorkoutIDs: [])
        let without = try JSONSerialization.jsonObject(with: CoachRequestJSON.encode(Payload(message: "m"), coach: coach)) as? [String: Any]
        XCTAssertNil((without?["coachContext"] as? [String: Any])?["openPainFlag"])
        coach.openPainFlag = true
        let with = try JSONSerialization.jsonObject(with: CoachRequestJSON.encode(Payload(message: "m"), coach: coach)) as? [String: Any]
        XCTAssertEqual((with?["coachContext"] as? [String: Any])?["openPainFlag"] as? Bool, true)
    }

    func testOpenPainFlagMeansThisAthletesUnhandledPainFlag() {
        let owner = UUID()
        func flag(_ kind: RunFlagKind, owner: UUID, resolved: Date? = nil) -> AthleteRunFlag {
            AthleteRunFlag(id: UUID(), ownerID: owner, kind: kind, note: nil, runKey: nil, createdAt: Date(), resolvedAt: resolved)
        }
        XCTAssertTrue(CoachLockRules.hasOpenPainFlag([flag(.pain, owner: owner)], ownerID: owner))
        XCTAssertFalse(CoachLockRules.hasOpenPainFlag([flag(.pain, owner: owner, resolved: Date())], ownerID: owner))
        XCTAssertFalse(CoachLockRules.hasOpenPainFlag([flag(.off, owner: owner)], ownerID: owner))
        XCTAssertFalse(CoachLockRules.hasOpenPainFlag([flag(.pain, owner: UUID())], ownerID: owner))
        XCTAssertFalse(CoachLockRules.hasOpenPainFlag([flag(.pain, owner: owner)], ownerID: nil))
    }

    // MARK: AC 2 / AC 4, client filter

    func testFlexWeekFilterKeepsCoachRowsAndTheirDays() {
        let coachTempo = UUID(), easy = UUID(), coachRest = UUID(), longRun = UUID()
        let original = [
            summary(easy, day: 1),
            summary(coachTempo, day: 2, locked: true),
            summary(coachRest, day: 4, locked: true),
            summary(longRun, day: 5),
        ]
        var changedTempo = original[1]
        changedTempo.distance = "4.0 km"
        var movedEasy = original[0]
        movedEasy.scheduledDate = original[2].scheduledDate // onto the coach rest day
        var shorterLong = original[3]
        shorterLong.distance = "10.0 km"
        let outcome = FlexWeekOutcome(
            restructuredWeek: [movedEasy, changedTempo, original[2], shorterLong],
            changes: [
                FlexWeekChange(workoutID: coachTempo, changeType: .downgraded, rationale: "x"),
                FlexWeekChange(workoutID: easy, changeType: .moved, rationale: "x", originalWorkoutID: easy),
                FlexWeekChange(workoutID: longRun, changeType: .downgraded, rationale: "x"),
            ],
            safetyWarnings: [],
            source: .ai
        )

        let filtered = CoachLockRules.respectingLocks(outcome, originalWeek: original)
        XCTAssertEqual(filtered.restructuredWeek[0], original[0], "no move onto a coach rest day")
        XCTAssertEqual(filtered.restructuredWeek[1], original[1], "the coach workout is copied back")
        XCTAssertEqual(filtered.restructuredWeek[3].distance, "10.0 km")
        XCTAssertEqual(filtered.changes.map(\.workoutID), [longRun])
    }

    func testFlexWeekFilterIsANoOpWithoutLocks() {
        let original = [summary(UUID(), day: 1), summary(UUID(), day: 2)]
        var shorter = original[1]
        shorter.distance = "3.0 km"
        let outcome = FlexWeekOutcome(
            restructuredWeek: [original[0], shorter],
            changes: [FlexWeekChange(workoutID: original[1].id, changeType: .downgraded, rationale: "x")],
            safetyWarnings: ["w"],
            source: .deterministicFallback
        )
        XCTAssertEqual(CoachLockRules.respectingLocks(outcome, originalWeek: original), outcome)
    }

    func testLockedFutureCountIgnoresPastAndUnlockedRows() throws {
        let today = ISO8601DateFormatter.shortDate.date(from: "2026-12-02")!
        let rows = [
            try decodeWorkout(["locked": true], date: "2026-12-01"),
            try decodeWorkout(["locked": true], date: "2026-12-02"),
            try decodeWorkout(["locked": true], date: "2026-12-09"),
            try decodeWorkout(date: "2026-12-10"),
        ]
        XCTAssertEqual(CoachLockRules.lockedFutureCount(rows, today: today), 2)
        XCTAssertEqual(CoachLockRules.lockedFutureCount([], today: today), 0)
    }

    // MARK: AC 3 / AC 6 / AC 7 copy and error mapping

    func testServerLockErrorsMapToNoticesNeverRawText() {
        XCTAssertEqual(CoachLockError.classify(PostgrestError(code: "P0001", message: "workout_locked")), .workoutLocked)
        XCTAssertEqual(CoachLockError.classify(PostgrestError(code: "P0001", message: "plan_locked_by_coach")), .planLockedByCoach)
        XCTAssertEqual(CoachLockError.classify(PostgrestError(code: "P0001", message: "coach_workouts_present")), .coachWorkoutsPresent)
        XCTAssertEqual(CoachLockError.classify(PostgrestError(detail: "3", code: "P0001", message: "count_changed")), .countChanged)
        XCTAssertNil(CoachLockError.classify(PostgrestError(message: "duplicate key value")))
        XCTAssertNil(CoachLockError.classify(URLError(.notConnectedToInternet)))

        XCTAssertEqual(CoachLockError.workoutLocked.notice, .workoutLocked)
        XCTAssertEqual(CoachLockError.planLockedByCoach.notice, .planLocked)
        XCTAssertEqual(CoachLockError.dateTaken.notice, .dateTaken)
        XCTAssertNil(CoachLockError.coachWorkoutsPresent.notice, "C7.9 owns this warning")

        XCTAssertTrue(CoachLockError.isMissingFunction(PostgrestError(code: "PGRST202", message: "Could not find the function public.athlete_replace_training_plan")))
        XCTAssertFalse(CoachLockError.isMissingFunction(PostgrestError(code: "P0001", message: "count_changed")))
    }

    func testCopyMatchesTheAcceptanceCriteria() {
        func plain(_ text: String) -> String {
            text.filter { $0 != BidiText.firstStrongIsolate && $0 != BidiText.popDirectionalIsolate }
        }
        XCTAssertEqual(plain(CoachLockCopy.workoutLocked(coach: "Dana")), "Dana set this workout, so it can't be changed here.")
        XCTAssertEqual(CoachLockCopy.dateTaken, "That day already has a workout.")
        XCTAssertEqual(plain(CoachLockCopy.planLockedTitle(coach: "Dana")), "Ask Dana to change your plan")
        XCTAssertEqual(
            plain(CoachLockCopy.planLockedBody(coach: "Dana")),
            "Dana manages your goal and plan. To change your race, date or runs per week, ask Dana."
        )
        XCTAssertEqual(plain(CoachLockCopy.replyToLatestNote(coach: "Dana")), "Reply to Dana's latest note")
        XCTAssertEqual(plain(CoachLockCopy.setBy(coach: "Dana")), "Set by Dana")
        XCTAssertEqual(CoachLockCopy.coachName(nil), "Your coach")
        for text in [CoachLockCopy.workoutLocked(coach: "D"), CoachLockCopy.planLockedBody(coach: "D"), CoachLockCopy.dateTaken] {
            XCTAssertFalse(text.contains("\u{2014}"), "no em dashes")
        }
    }

    func testLockReplyComesFromTheLoadedRowAndItsNote() {
        let locked = UUID(), open = UUID()
        let provider = WorkoutSummaryLockProvider(workouts: [
            summary(locked, day: 2, locked: true, detail: "Hold 4:10 on the reps."),
            summary(open, day: 3, detail: "AI note"),
        ])
        let reply = CoachLockReplyBuilder.replyIfLocked(coachName: "Dana", workoutID: locked.uuidString.lowercased(), provider: provider)
        XCTAssertEqual(reply?.message, "That's Dana's workout.")
        XCTAssertEqual(reply?.noteLinkTitle, "Read Dana's note")
        XCTAssertNil(CoachLockReplyBuilder.replyIfLocked(coachName: "Dana", workoutID: open.uuidString, provider: provider))

        let noNote = WorkoutSummaryLockProvider(workouts: [summary(locked, day: 2, locked: true)])
        XCTAssertNil(CoachLockReplyBuilder.replyIfLocked(coachName: "Dana", workoutID: locked.uuidString, provider: noNote)?.noteLinkTitle)
    }

    func testPlanLockNoticeIsPostedAndRemembered() {
        let center = NotificationCenter()
        let posted = expectation(forNotification: .runSmartCoachLockNotice, object: nil, notificationCenter: center) { note in
            (note.object as? CoachLockNotice) == .planLocked
        }
        CoachLockNotices.post(.planLocked, center: center)
        wait(for: [posted], timeout: 2)
        XCTAssertTrue(CoachLockNotices.planLockedRecently())
        XCTAssertFalse(CoachLockNotices.planLockedRecently(now: Date().addingTimeInterval(60)))
    }

    func testPlanGenerationReasonsForLocks() {
        XCTAssertEqual(PlanGenerationFailureReason.planLockedByCoach.rawValue, "plan_locked_by_coach")
        XCTAssertEqual(PlanGenerationFailureReason.coachWorkoutsPresent.rawValue, "coach_workouts_present")
    }
}
