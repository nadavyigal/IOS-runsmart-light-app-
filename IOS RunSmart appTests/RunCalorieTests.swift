import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunCalorieTests: XCTestCase {
    func testTenKilometersAtSeventyKilogramsIsSevenHundredActiveKilocalories() throws {
        XCTAssertEqual(try XCTUnwrap(RunCalorieEstimator.activeKilocalories(distanceMeters: 10_000, weightKg: 70)), 700, accuracy: 0.01)
    }

    func testHalfDistanceAndDifferentWeightScaleEstimate() throws {
        XCTAssertEqual(try XCTUnwrap(RunCalorieEstimator.activeKilocalories(distanceMeters: 5_000, weightKg: 60)), 300, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RunCalorieEstimator.activeKilocalories(distanceMeters: 0, weightKg: 70)), 0)
    }

    func testUnknownWeightAndInvalidInputsNeverInventEnergy() {
        XCTAssertNil(RunCalorieEstimator.activeKilocalories(distanceMeters: 1_000, weightKg: nil))
        for weight in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(RunCalorieEstimator.activeKilocalories(distanceMeters: 1_000, weightKg: weight))
        }
        for distance in [-1.0, Double.nan, Double.infinity] {
            XCTAssertNil(RunCalorieEstimator.activeKilocalories(distanceMeters: distance, weightKg: 70))
        }
    }

    func testHealthWeightPreferredThenManualFallbackAndPersistence() throws {
        let suiteName = "RunWeightTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RunnerWeightStore(defaults: defaults)
        XCTAssertNil(store.weightKg)
        XCTAssertTrue(store.setManualWeightKg(70))
        XCTAssertEqual(store.weightKg, 70)
        store.updateHealthWeight(72)
        XCTAssertEqual(store.weightKg, 72)
        store.updateHealthWeight(nil)
        XCTAssertEqual(store.weightKg, 70)
        XCTAssertEqual(RunnerWeightStore(defaults: defaults).weightKg, 70)
        XCTAssertFalse(store.setManualWeightKg(.nan))
        XCTAssertEqual(store.weightKg, 70)
    }

    func testWeightSetupIsOfferedOnlyOnceAndNeverWithKnownWeight() throws {
        let suiteName = "RunWeightPromptTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RunnerWeightStore(defaults: defaults)
        XCTAssertTrue(store.shouldOfferWeightSetup)
        store.markWeightSetupOffered()
        XCTAssertFalse(store.shouldOfferWeightSetup)
        XCTAssertFalse(RunnerWeightStore(defaults: defaults).shouldOfferWeightSetup)
    }

    func testEstimateSurvivesRunRoundTripAndLegacyRunDecodesWithoutIt() throws {
        let now = Date()
        let run = RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart,
                              startedAt: now, endedAt: now.addingTimeInterval(3_000),
                              distanceMeters: 10_000, movingTimeSeconds: 3_000,
                              averagePaceSecondsPerKm: 300, averageHeartRateBPM: nil,
                              routePoints: [], syncedAt: nil, estimatedActiveKilocalories: 700)
        let data = try JSONEncoder().encode(run)
        XCTAssertEqual(try JSONDecoder().decode(RecordedRun.self, from: data).estimatedActiveKilocalories, 700)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "estimatedActiveKilocalories")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertNil(try JSONDecoder().decode(RecordedRun.self, from: legacyData).estimatedActiveKilocalories)
    }
}
