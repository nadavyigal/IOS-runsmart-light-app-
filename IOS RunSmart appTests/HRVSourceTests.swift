import XCTest
@testable import IOS_RunSmart_app

final class HRVSourceTests: XCTestCase {
    func testAttributionLabelsMapToDisplayCopy() {
        XCTAssertEqual(HRVSource.garmin.attributionLabel, "Garmin")
        XCTAssertEqual(HRVSource.appleHealth.attributionLabel, "Apple Health")
        XCTAssertNil(HRVSource.unknown.attributionLabel)
    }

    func testHealthKitDailySnapshotDecodesOldPayloadWithoutSource() throws {
        let json = """
        {
          "date": "2026-06-22T07:00:00Z",
          "steps": 4200,
          "restingHeartRateBPM": 48,
          "hrvMilliseconds": 61.5,
          "sleepSeconds": 27000,
          "activeEnergyKilocalories": 340
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(HealthKitDailySnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.hrvMilliseconds, 61.5)
        XCTAssertEqual(snapshot.hrvSource, .unknown)
    }

    func testHealthKitDailySnapshotRoundTripsSource() throws {
        let snapshot = HealthKitDailySnapshot(
            date: Date(timeIntervalSince1970: 1_772_000_000),
            steps: 4200,
            restingHeartRateBPM: 48,
            hrvMilliseconds: 61.5,
            hrvSource: .garmin,
            sleepSeconds: 27000,
            activeEnergyKilocalories: 340
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(HealthKitDailySnapshot.self, from: data)

        XCTAssertEqual(decoded.hrvMilliseconds, 61.5)
        XCTAssertEqual(decoded.hrvSource, .garmin)
    }

    func testResolveHRVPrecedence() {
        // Garmin attribution is reserved for the Garmin Connect API path; HealthKit-read HRV is
        // always Apple Health. The resolver prefers Garmin-direct over the HealthKit fallback.
        let garminDirect = HRVReading(value: 64, source: .garmin)
        let appleHealth = HRVReading(value: 58, source: .appleHealth)

        XCTAssertEqual(HRVResolver.resolve(garminDirect: garminDirect, healthKit: appleHealth), garminDirect)
        XCTAssertEqual(HRVResolver.resolve(garminDirect: nil, healthKit: appleHealth), appleHealth)
        XCTAssertNil(HRVResolver.resolve(garminDirect: nil, healthKit: nil))
    }
    func testHealthDailySummaryFormatting() {
        let s = HealthDailySummary(steps: 8420, activeCalories: 540, sleepSeconds: 7 * 3600 + 48 * 60)
        XCTAssertEqual(s.stepsDisplay, "8.4k")
        XCTAssertEqual(s.caloriesDisplay, "540")
        XCTAssertEqual(s.sleepDisplay, "7h 48m")
        XCTAssertTrue(s.hasAnyData)
    }

    func testHealthDailySummaryHandlesMissingData() {
        XCTAssertFalse(HealthDailySummary.empty.hasAnyData)
        XCTAssertEqual(HealthDailySummary.empty.stepsDisplay, "--")
        XCTAssertEqual(HealthDailySummary.empty.sleepDisplay, "--")
        XCTAssertEqual(HealthDailySummary(steps: 850, activeCalories: nil, sleepSeconds: nil).stepsDisplay, "850")
    }
}
