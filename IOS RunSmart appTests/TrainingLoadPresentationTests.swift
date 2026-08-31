import XCTest
@testable import IOS_RunSmart_app

final class TrainingLoadPresentationTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-07-18T08:00:00Z")!

    private func run(daysAgo: Int, minutes: Double, rpe: Int? = nil, hr: Int? = nil) -> RecordedRun {
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
            averageHeartRateBPM: hr,
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

    // MARK: - Load ratio series (Story 3)

    func testEachPlottedPointCarriesItsOwnRatio() throws {
        let source = series(everyOtherDayRuns)
        let presentation = TrainingLoadPresentation.make(from: source)
        let scored = source.filter { $0.status != .insufficientData }

        XCTAssertEqual(presentation.points.count, scored.count)
        for (point, day) in zip(presentation.points, scored) {
            XCTAssertEqual(point.acwr, try XCTUnwrap(day.acwr), accuracy: 0.001)
        }
    }

    /// The ratio is acute ÷ chronic, so the plotted ratio must reproduce the
    /// plotted loads rather than being computed on a different basis.
    func testPlottedRatioIsConsistentWithThePlottedLoads() throws {
        let presentation = TrainingLoadPresentation.make(from: series(everyOtherDayRuns))
        let point = try XCTUnwrap(presentation.points.last)
        // optimalLow is chronic x 0.8, so chronic is recoverable from the band.
        let chronic = point.optimalLow / TrainingLoadPresentation.optimalRatioRange.lowerBound
        XCTAssertEqual(point.acwr, point.acuteLoad / chronic, accuracy: 0.001)
    }

    /// A day with no chronic load cannot produce a ratio, so it must never be
    /// plotted — that is the divide-by-zero guard, seen from the chart's side.
    func testDaysWithoutAChronicBaseAreNeverPlotted() {
        let presentation = TrainingLoadPresentation.make(
            from: series([run(daysAgo: 1, minutes: 40, rpe: 5), run(daysAgo: 2, minutes: 40, rpe: 5)])
        )
        XCTAssertTrue(presentation.points.isEmpty)
        XCTAssertEqual(presentation.daysCollected, 0)
        XCTAssertNil(presentation.currentACWR)
    }

    func testRatioInsideTheBandMatchesTheOptimalStatus() throws {
        let presentation = TrainingLoadPresentation.make(from: series(everyOtherDayRuns))
        let point = try XCTUnwrap(presentation.points.last)

        XCTAssertEqual(presentation.status, .optimal)
        XCTAssertTrue(TrainingLoadPresentation.optimalRatioRange.contains(point.acwr))
    }

    func testRatioAboveTheBandMatchesAnAboveOptimalStatus() throws {
        var runs = (7..<28).compactMap { day in day % 3 == 0 ? run(daysAgo: day, minutes: 30, rpe: 4) : nil }
        runs += (0..<7).map { run(daysAgo: $0, minutes: 60, rpe: 8) }

        let presentation = TrainingLoadPresentation.make(from: series(runs))
        let point = try XCTUnwrap(presentation.points.last)

        XCTAssertGreaterThan(point.acwr, TrainingLoadPresentation.optimalRatioRange.upperBound)
        XCTAssertTrue([.elevated, .highRisk].contains(presentation.status))
    }

    /// The band drawn on the ratio chart must agree with the status word for
    /// every plotted day, not just the latest one.
    ///
    /// Note the comparison is half-open. `optimalRatioRange` is a closed range
    /// because that is what gets *drawn* (the band is painted up to and
    /// including 1.3), while `TrainingLoadCalculator.status(for:)` classifies
    /// optimal as `..<1.3`. The two only disagree at exactly 1.3, where the
    /// drawn edge is sub-pixel; asserting with `.contains` here would pass
    /// today purely because no fixture lands on the boundary.
    func testBandMembershipAgreesWithStatusForEveryPlottedDay() {
        let source = series(everyOtherDayRuns)
        let presentation = TrainingLoadPresentation.make(from: source)
        let scored = source.filter { $0.status != .insufficientData }
        let range = TrainingLoadPresentation.optimalRatioRange

        for (point, day) in zip(presentation.points, scored) {
            let inside = point.acwr >= range.lowerBound && point.acwr < range.upperBound
            XCTAssertEqual(inside, day.status == .optimal, "ratio \(point.acwr) vs status \(day.status)")
        }
    }

    // MARK: - Exercise load list (Story 5)

    func testExerciseLoadListsTheAcuteWindowNewestFirst() {
        let runs = (0..<10).map { run(daysAgo: $0, minutes: 40, rpe: 5) }
        let entries = ExerciseLoadEntry.acuteWindow(runs: runs, days: 7, now: now, calendar: calendar)

        XCTAssertEqual(entries.count, 8) // days 0...7 inclusive of the boundary
        XCTAssertEqual(entries.map(\.date), entries.map(\.date).sorted(by: >))
    }

    /// The list explains the acute number, so its entries must sum to it.
    func testExerciseLoadEntriesSumToTheAcuteLoad() {
        let runs = (0..<10).map { run(daysAgo: $0, minutes: 40, rpe: 5) }
        let entries = ExerciseLoadEntry.acuteWindow(runs: runs, days: 7, now: now, calendar: calendar)
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)

        XCTAssertEqual(entries.map(\.load).reduce(0, +), snapshot.acuteLoad, accuracy: 0.001)
    }

    func testExerciseLoadEntryCarriesFosterSessionLoad() throws {
        let entries = ExerciseLoadEntry.acuteWindow(
            runs: [run(daysAgo: 1, minutes: 40, rpe: 6)], days: 7, now: now, calendar: calendar
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.load, 240, accuracy: 0.001) // 40 min x RPE 6
        XCTAssertEqual(entry.durationMinutes, 40)
    }

    func testExerciseLoadNamesWhereEachEffortEstimateCameFrom() throws {
        let reported = run(daysAgo: 1, minutes: 30, rpe: 7)
        let fromHR = run(daysAgo: 2, minutes: 30, rpe: nil, hr: 150)
        let assumed = run(daysAgo: 3, minutes: 30)

        let entries = ExerciseLoadEntry.acuteWindow(
            runs: [reported, fromHR, assumed], days: 7, now: now, calendar: calendar
        )
        XCTAssertEqual(entries.map(\.effortSource), [.reportedRPE, .heartRate, .assumedModerate])
    }

    /// `effortSource` mirrors `effortRPE`'s branch order but does not share its
    /// return, so pin them together: an out-of-range RPE must fall through to
    /// heart rate in both.
    func testEffortSourceAgreesWithTheEffortUsedForLoad() {
        let outOfRangeRPE = run(daysAgo: 1, minutes: 30, rpe: 42, hr: 150)
        XCTAssertEqual(TrainingLoadCalculator.effortSource(for: outOfRangeRPE), .heartRate)
        // HR 150 lands in the hard band -> RPE 7 -> 30 x 7.
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: outOfRangeRPE), 210, accuracy: 0.001)

        let noSignals = run(daysAgo: 1, minutes: 30)
        XCTAssertEqual(TrainingLoadCalculator.effortSource(for: noSignals), .assumedModerate)
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: noSignals), 150, accuracy: 0.001)
    }

    func testExerciseLoadExcludesRunsOutsideTheAcuteWindow() {
        let entries = ExerciseLoadEntry.acuteWindow(
            runs: [run(daysAgo: 30, minutes: 40, rpe: 5)], days: 7, now: now, calendar: calendar
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testExerciseLoadWithNonPositiveDaysIsEmpty() {
        XCTAssertTrue(
            ExerciseLoadEntry.acuteWindow(runs: everyOtherDayRuns, days: 0, now: now, calendar: calendar).isEmpty
        )
    }

    /// Pins the boundary semantics above so a future change to either the band
    /// or the calculator bands has to face this explicitly.
    func testOptimalClassificationIsHalfOpenAtTheUpperBound() {
        let upper = TrainingLoadPresentation.optimalRatioRange.upperBound
        XCTAssertTrue(TrainingLoadPresentation.optimalRatioRange.contains(upper))
        // ...but the calculator calls exactly-upper "elevated", not "optimal".
        XCTAssertEqual(TrainingLoadCalculator.status(for: upper), .elevated)
        XCTAssertEqual(TrainingLoadCalculator.status(for: upper - 0.0001), .optimal)
    }
}
