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

    func testClassifyHRVSourceFromBundleIdentifier() {
        XCTAssertEqual(HealthKitSyncService.classifyHRVSource(bundleIdentifier: "com.garmin.connect.mobile"), .garmin)
        XCTAssertEqual(HealthKitSyncService.classifyHRVSource(bundleIdentifier: "com.garmin.connect.mobile.watch"), .garmin)
        XCTAssertEqual(HealthKitSyncService.classifyHRVSource(bundleIdentifier: "com.apple.Health"), .appleHealth)
        XCTAssertEqual(HealthKitSyncService.classifyHRVSource(bundleIdentifier: "com.apple.health"), .appleHealth)
        XCTAssertEqual(HealthKitSyncService.classifyHRVSource(bundleIdentifier: "com.thirdparty.runner"), .unknown)
        XCTAssertEqual(HealthKitSyncService.classifyHRVSource(bundleIdentifier: nil), .unknown)
    }

    func testDominantHRVSourceUsesMostRecentSample() {
        let samples = [
            HRVSourceSample(value: 55, source: .appleHealth, endDate: Date(timeIntervalSince1970: 100)),
            HRVSourceSample(value: 61, source: .garmin, endDate: Date(timeIntervalSince1970: 200))
        ]

        XCTAssertEqual(HealthKitSyncService.dominantHRVSource(from: samples), .garmin)
    }

    func testResolveHRVPrecedence() {
        let garminDirect = HRVReading(value: 64, source: .garmin)
        let garminViaHealth = HRVReading(value: 61, source: .garmin)
        let appleHealth = HRVReading(value: 58, source: .appleHealth)
        let unknown = HRVReading(value: 52, source: .unknown)

        XCTAssertEqual(HRVResolver.resolve(garminDirect: garminDirect, healthKit: appleHealth), garminDirect)
        XCTAssertEqual(HRVResolver.resolve(garminDirect: nil, healthKit: garminViaHealth), garminViaHealth)
        XCTAssertEqual(HRVResolver.resolve(garminDirect: nil, healthKit: appleHealth), appleHealth)
        XCTAssertEqual(HRVResolver.resolve(garminDirect: nil, healthKit: unknown), unknown)
        XCTAssertNil(HRVResolver.resolve(garminDirect: nil, healthKit: nil))
    }
}
