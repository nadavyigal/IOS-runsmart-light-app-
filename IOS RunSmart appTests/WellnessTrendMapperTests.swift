import XCTest
@testable import IOS_RunSmart_app

final class WellnessTrendMapperTests: XCTestCase {
    func testSeriesUsesTrainingReadinessWhenAvailable() {
        let metrics = [
            makeMetric(id: 1, date: "2026-05-20", hrv: 51, bodyBattery: 62, trainingReadiness: 65),
            makeMetric(id: 2, date: "2026-05-21", hrv: 54, bodyBattery: 66, trainingReadiness: 70),
            makeMetric(id: 3, date: "2026-05-22", hrv: 58, bodyBattery: 68, trainingReadiness: 74)
        ]

        let series = WellnessTrendMapper.series(from: metrics, maxDays: 7)

        XCTAssertEqual(series.latestReadinessDisplay, "74")
        XCTAssertEqual(series.latestHRVDisplay, "58 ms")
        XCTAssertEqual(series.days.count, 3)
        XCTAssertFalse(series.readinessBars.isEmpty)
        XCTAssertFalse(series.hrvBars.isEmpty)
    }

    func testSeriesFallsBackToBodyBatteryWhenTrainingReadinessMissing() {
        let metrics = [
            makeMetric(id: 1, date: "2026-05-20", hrv: 50, bodyBattery: 60, trainingReadiness: nil),
            makeMetric(id: 2, date: "2026-05-21", hrv: 49, bodyBattery: 63, trainingReadiness: nil),
            makeMetric(id: 3, date: "2026-05-22", hrv: 52, bodyBattery: 67, trainingReadiness: nil)
        ]

        let series = WellnessTrendMapper.series(from: metrics, maxDays: 7)

        XCTAssertEqual(series.latestReadinessDisplay, "67")
        XCTAssertFalse(series.readinessBars.isEmpty)
    }

    func testSeriesReturnsEmptyForNoRows() {
        let series = WellnessTrendMapper.series(from: [], maxDays: 7)
        XCTAssertEqual(series, .empty)
    }

    func testSeriesUsesBuildingTrendCopyForSparseHistory() {
        let metrics = [
            makeMetric(id: 1, date: "2026-05-26", hrv: 50, bodyBattery: 60, trainingReadiness: 62),
            makeMetric(id: 2, date: "2026-05-27", hrv: 52, bodyBattery: 63, trainingReadiness: 64)
        ]

        let series = WellnessTrendMapper.series(from: metrics, maxDays: 7)

        XCTAssertEqual(series.hrvTrendSummary, "Building hrv trend")
        XCTAssertEqual(series.readinessTrendSummary, "Building readiness trend")
        XCTAssertEqual(series.days.count, 2)
    }

    private func makeMetric(
        id: Int,
        date: String,
        hrv: Double?,
        bodyBattery: Int?,
        trainingReadiness: Int?
    ) -> DBGarminDailyMetrics {
        DBGarminDailyMetrics(
            id: id,
            authUserId: nil,
            date: date,
            steps: nil,
            sleepScore: nil,
            sleepDurationS: nil,
            hrv: hrv,
            bodyBattery: bodyBattery,
            bodyBatteryBalance: nil,
            stress: nil,
            trainingReadiness: trainingReadiness,
            restingHR: nil
        )
    }
}
