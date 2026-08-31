import XCTest
@testable import IOS_RunSmart_app

final class TrainingLoadCalculatorTests: XCTestCase {

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

    // MARK: - Session load (Foster session-RPE: minutes x effort)

    func testSessionLoadUsesFosterSessionRPEWhenRPEPresent() {
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: run(daysAgo: 0, minutes: 40, rpe: 6)), 240, accuracy: 0.01)
    }

    func testSessionLoadFallsBackToModerateRPEWithoutSignals() {
        // No RPE, no HR: assume moderate effort (RPE 5)
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: run(daysAgo: 0, minutes: 30)), 150, accuracy: 0.01)
    }

    func testSessionLoadDerivesEffortFromHeartRateWhenNoRPE() {
        // HR 155 falls in the hard band -> derived RPE 7
        XCTAssertEqual(TrainingLoadCalculator.sessionLoad(for: run(daysAgo: 0, minutes: 30, hr: 155)), 210, accuracy: 0.01)
    }

    // MARK: - ACWR snapshot

    func testACWRBalancedLoadIsOptimal() {
        // Every 2nd day for four weeks, 40 min at RPE 5 (200 load/run):
        // acute window (>= now-7d) holds days 0/2/4/6 -> 4 x 200 = 800;
        // chronic = 14 x 200 / 4 = 700 -> ACWR 8/7, inside the optimal band.
        let runs = (0..<28).compactMap { day -> RecordedRun? in
            day % 2 == 0 ? run(daysAgo: day, minutes: 40, rpe: 5) : nil
        }
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.acwr ?? 0, 800.0 / 700.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.status, .optimal)
    }

    func testACWRSpikeFlagsHighRisk() {
        // Quiet month then a huge current week -> ACWR > 1.5
        var runs = (7..<28).compactMap { day -> RecordedRun? in
            day % 3 == 0 ? run(daysAgo: day, minutes: 30, rpe: 4) : nil
        }
        runs += (0..<7).map { run(daysAgo: $0, minutes: 60, rpe: 8) }
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        XCTAssertGreaterThan(snapshot.acwr ?? 0, 1.5)
        XCTAssertEqual(snapshot.status, .highRisk)
    }

    func testFewerThanFourRunsInMonthIsInsufficientData() {
        let snapshot = TrainingLoadCalculator.snapshot(
            runs: [run(daysAgo: 1, minutes: 40, rpe: 5), run(daysAgo: 9, minutes: 40, rpe: 5)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.status, .insufficientData)
        XCTAssertNil(snapshot.acwr)
    }

    func testRunsOlderThan28DaysAreIgnored() {
        var runs = (0..<28).compactMap { day -> RecordedRun? in
            day % 2 == 0 ? run(daysAgo: day, minutes: 40, rpe: 5) : nil
        }
        let baseline = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        runs.append(run(daysAgo: 40, minutes: 300, rpe: 10)) // must not skew chronic
        let withStaleRun = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        XCTAssertEqual(withStaleRun, baseline)
    }

    // MARK: - Daily series (Training Load timeline, Story 1)

    /// Every 2nd day for four weeks; same fixture as the optimal-band test above.
    private var everyOtherDayRuns: [RecordedRun] {
        (0..<28).compactMap { day -> RecordedRun? in
            day % 2 == 0 ? run(daysAgo: day, minutes: 40, rpe: 5) : nil
        }
    }

    func testSeriesReturnsOnePointPerDayOldestFirst() {
        let series = TrainingLoadCalculator.series(runs: everyOtherDayRuns, days: 28, now: now, calendar: calendar)
        XCTAssertEqual(series.count, 28)
        XCTAssertEqual(series.map(\.date), series.map(\.date).sorted())
        XCTAssertEqual(series.last?.date, calendar.startOfDay(for: now))
        XCTAssertEqual(
            series.first?.date,
            calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: now))
        )
    }

    /// The invariant that keeps the chart honest: its final point is the same
    /// number the headline shows.
    func testSeriesFinalPointMatchesTheCurrentSnapshot() throws {
        let runs = everyOtherDayRuns
        let series = TrainingLoadCalculator.series(runs: runs, days: 28, now: now, calendar: calendar)
        let snapshot = TrainingLoadCalculator.snapshot(runs: runs, now: now, calendar: calendar)
        let last = try XCTUnwrap(series.last)
        XCTAssertEqual(last.acuteLoad, snapshot.acuteLoad, accuracy: 0.001)
        XCTAssertEqual(last.chronicLoad, snapshot.chronicLoad, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(last.acwr), try XCTUnwrap(snapshot.acwr), accuracy: 0.001)
        XCTAssertEqual(last.status, snapshot.status)
    }

    func testSeriesAcuteLoadFallsAcrossARestGap() {
        // Trained hard three weeks ago, then stopped: acute load peaks while
        // those runs sit inside the sliding 7-day window, then decays to zero
        // once the window has moved past all of them.
        //
        // Note the peak is mid-series, not at `first`: the oldest point sees
        // only one run inside its own trailing 28-day window, so it is
        // correctly .insufficientData with zero load.
        let runs = (21..<28).map { run(daysAgo: $0, minutes: 60, rpe: 8) }
        let series = TrainingLoadCalculator.series(runs: runs, days: 28, now: now, calendar: calendar)

        XCTAssertGreaterThan(series.map(\.acuteLoad).max() ?? 0, 0)
        XCTAssertEqual(series.last?.acuteLoad ?? -1, 0, accuracy: 0.001)
        // Chronic load still remembers the block, so the ratio reads as detraining.
        XCTAssertEqual(series.last?.status, .detraining)
    }

    func testSeriesIsInsufficientDataForEveryDayWhenTooFewRuns() {
        let series = TrainingLoadCalculator.series(
            runs: [run(daysAgo: 1, minutes: 40, rpe: 5), run(daysAgo: 9, minutes: 40, rpe: 5)],
            days: 28,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(series.count, 28)
        XCTAssertTrue(series.allSatisfy { $0.status == .insufficientData })
        XCTAssertTrue(series.allSatisfy { $0.acwr == nil })
    }

    func testSeriesIgnoresRunsOutsideEachDaysTrailingWindow() {
        var runs = everyOtherDayRuns
        let baseline = TrainingLoadCalculator.series(runs: runs, days: 28, now: now, calendar: calendar)
        runs.append(run(daysAgo: 90, minutes: 300, rpe: 10))
        let withStaleRun = TrainingLoadCalculator.series(runs: runs, days: 28, now: now, calendar: calendar)
        XCTAssertEqual(withStaleRun, baseline)
    }

    func testSeriesDoesNotCountRunsRecordedLaterToday() {
        // `now` is 08:00Z; a run starting 12 hours later today must not land in
        // today's point, because the final day is clamped to `now`.
        var runs = everyOtherDayRuns
        let baseline = TrainingLoadCalculator.series(runs: runs, days: 28, now: now, calendar: calendar)
        runs.append(run(daysAgo: -1, minutes: 60, rpe: 10)) // 24h ahead of `now`
        let withFutureRun = TrainingLoadCalculator.series(runs: runs, days: 28, now: now, calendar: calendar)
        XCTAssertEqual(withFutureRun, baseline)
    }

    func testSeriesWithNonPositiveDaysIsEmpty() {
        XCTAssertTrue(TrainingLoadCalculator.series(runs: everyOtherDayRuns, days: 0, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(TrainingLoadCalculator.series(runs: everyOtherDayRuns, days: -5, now: now, calendar: calendar).isEmpty)
    }
}
