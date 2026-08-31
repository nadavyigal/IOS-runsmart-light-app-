import XCTest
@testable import IOS_RunSmart_app

final class TrainingLoadPresentationTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-07-18T08:00:00Z")!

    private func run(daysAgo: Int, minutes: Double, rpe: Int? = nil) -> RecordedRun {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .healthKit,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            distanceMeters: minutes * 160,
            movingTimeSeconds: minutes * 60,
            averagePaceSecondsPerKm: 375,
            averageHeartRateBPM: nil,
            routePoints: [],
            rpe: rpe,
            syncedAt: nil
        )
    }

    private func series(_ runs: [RecordedRun], days: Int = 28) -> [DailyTrainingLoadPoint] {
        TrainingLoadCalculator.series(runs: runs, days: days, now: now, calendar: calendar)
    }

    private var everyOtherDayRuns: [RecordedRun] {
        (0..<28).compactMap { day in day % 2 == 0 ? run(daysAgo: day, minutes: 40, rpe: 5) : nil }
    }

    // MARK: - Band

    func testOptimalBandIsDerivedFromChronicLoadUsingTheCalculatorsOwnThresholds() throws {
        let source = series(everyOtherDayRuns)
        let presentation = TrainingLoadPresentation.make(from: source)

        let day = try XCTUnwrap(source.last)
        let point = try XCTUnwrap(presentation.points.last)
        XCTAssertEqual(point.optimalLow, day.chronicLoad * 0.8, accuracy: 0.001)
        XCTAssertEqual(point.optimalHigh, day.chronicLoad * 1.3, accuracy: 0.001)
    }

    /// The band and the status word are printed side by side, so they must never
    /// disagree: an acute load inside the band must not be reported as elevated.
    func testPointInsideTheBandAgreesWithAnOptimalStatus() throws {
        let source = series(everyOtherDayRuns)
        let presentation = TrainingLoadPresentation.make(from: source)
        let point = try XCTUnwrap(presentation.points.last)

        XCTAssertEqual(presentation.status, .optimal)
        XCTAssertTrue(point.isInsideOptimalRange)
    }

    func testSpikeSitsAboveTheBandAndReportsHighRisk() throws {
        var runs = (7..<28).compactMap { day in day % 3 == 0 ? run(daysAgo: day, minutes: 30, rpe: 4) : nil }
        runs += (0..<7).map { run(daysAgo: $0, minutes: 60, rpe: 8) }

        let presentation = TrainingLoadPresentation.make(from: series(runs))
        let point = try XCTUnwrap(presentation.points.last)

        XCTAssertEqual(presentation.status, .highRisk)
        XCTAssertFalse(point.isInsideOptimalRange)
        XCTAssertGreaterThan(point.acuteLoad, point.optimalHigh)
    }

    // MARK: - Current values

    func testCurrentValuesMirrorTheFinalSeriesPoint() throws {
        let source = series(everyOtherDayRuns)
        let presentation = TrainingLoadPresentation.make(from: source)
        let day = try XCTUnwrap(source.last)

        XCTAssertEqual(try XCTUnwrap(presentation.currentAcuteLoad), day.acuteLoad, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(presentation.currentChronicLoad), day.chronicLoad, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(presentation.currentACWR), try XCTUnwrap(day.acwr), accuracy: 0.001)
        XCTAssertEqual(presentation.status, day.status)
    }

    // MARK: - Thin history

    /// Ramp-up days are dropped, not plotted as zero: a flat run of zeros would
    /// read as "you did nothing", which is false.
    func testUnscoredDaysAreNotPlotted() {
        let runs = (0..<6).map { run(daysAgo: $0, minutes: 40, rpe: 5) }
        let source = series(runs)
        let presentation = TrainingLoadPresentation.make(from: source)

        XCTAssertLessThan(presentation.points.count, source.count)
        XCTAssertEqual(presentation.points.count, source.filter { $0.status != .insufficientData }.count)
        XCTAssertEqual(presentation.daysCollected, presentation.points.count)
    }

    func testTooFewRunsProducesNoChartAndInsufficientStatus() {
        let presentation = TrainingLoadPresentation.make(
            from: series([run(daysAgo: 1, minutes: 40, rpe: 5), run(daysAgo: 9, minutes: 40, rpe: 5)])
        )
        XCTAssertFalse(presentation.hasChart)
        XCTAssertEqual(presentation.daysCollected, 0)
        XCTAssertEqual(presentation.status, .insufficientData)
        XCTAssertNil(presentation.currentACWR)
    }

    func testEmptySeriesProducesEmptyPresentation() {
        let presentation = TrainingLoadPresentation.make(from: [])
        XCTAssertFalse(presentation.hasChart)
        XCTAssertEqual(presentation.daysCollected, 0)
        XCTAssertEqual(presentation.windowDays, 0)
        XCTAssertNil(presentation.currentAcuteLoad)
        XCTAssertEqual(presentation.status, .insufficientData)
    }

    func testWindowDaysReportsTheWholeRequestedWindowNotJustScoredDays() {
        let runs = (0..<6).map { run(daysAgo: $0, minutes: 40, rpe: 5) }
        let presentation = TrainingLoadPresentation.make(from: series(runs, days: 28))
        XCTAssertEqual(presentation.windowDays, 28)
        XCTAssertLessThan(presentation.daysCollected, 28)
    }

    /// Guards the constant the chart and the status word share.
    func testOptimalRatioRangeMatchesTheCalculatorBands() {
        XCTAssertEqual(TrainingLoadPresentation.optimalRatioRange.lowerBound, 0.8, accuracy: 0.0001)
        XCTAssertEqual(TrainingLoadPresentation.optimalRatioRange.upperBound, 1.3, accuracy: 0.0001)
    }
}
