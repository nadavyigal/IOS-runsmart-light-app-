import XCTest
@testable import IOS_RunSmart_app

final class FlexWeekCacheTests: XCTestCase {

    private let userA = UUID()
    private let userB = UUID()
    private var request: FlexWeekRequest!
    private let cachePrefix = "runsmart.flexWeek.response."

    override func setUp() {
        super.setUp()
        let base = Calendar.current.startOfDay(for: Date())
        let workouts = (0..<7).map { i -> PlannedWorkout in
            PlannedWorkout(
                id: UUID(),
                scheduledDate: Calendar.current.date(byAdding: .day, value: i, to: base)!,
                weekday: "MON",
                date: "\(i + 1)",
                kind: .easy,
                title: "Easy Run",
                distance: "5 km",
                detail: "",
                isToday: i == 0,
                isComplete: false
            )
        }
        request = FlexWeekRequest(reason: .tired, currentWeek: workouts, readinessContext: nil)
    }

    override func tearDown() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(cachePrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    private var stubbedResponse: RunSmartDTO.FlexWeekResponseDTO {
        RunSmartDTO.FlexWeekResponseDTO(
            restructuredWeek: [],
            changes: [RunSmartDTO.FlexWeekChangeDTO(
                workoutID: UUID().uuidString,
                changeType: "downgraded",
                rationale: "Tired",
                originalWorkoutID: nil
            )],
            safetyWarnings: nil,
            source: "live_ai"
        )
    }

    // MARK: - Finding 2A regression: cross-user cache isolation

    func testCacheMissWhenUserIDDiffers() {
        FlexWeekServiceSupport.cacheResponse(stubbedResponse, for: request, userID: userA)
        let result = FlexWeekServiceSupport.cachedOutcome(for: request, userID: userB)
        XCTAssertNil(result, "User B must not receive User A's cached flex week — cross-user cache leak")
    }

    func testCacheWrittenWithUserIDInKey() {
        FlexWeekServiceSupport.cacheResponse(stubbedResponse, for: request, userID: userA)
        let keyExists = UserDefaults.standard.dictionaryRepresentation().keys
            .contains { $0.hasPrefix(cachePrefix) && $0.contains(userA.uuidString) }
        XCTAssertTrue(keyExists, "Cache key must contain the user ID so different users get isolated entries")
    }

    func testNoCacheWrittenWithoutUserID() {
        FlexWeekServiceSupport.cacheResponse(stubbedResponse, for: request, userID: nil)
        let anyWritten = UserDefaults.standard.dictionaryRepresentation().keys
            .contains { $0.hasPrefix(cachePrefix) }
        XCTAssertFalse(anyWritten, "Cache must not be written when userID is nil — unauthenticated state")
    }

    func testCachedOutcomeNilWithoutUserID() {
        FlexWeekServiceSupport.cacheResponse(stubbedResponse, for: request, userID: userA)
        let result = FlexWeekServiceSupport.cachedOutcome(for: request, userID: nil)
        XCTAssertNil(result, "Cache read with nil userID must return nil even if data exists under another user's key")
    }
}
