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
}
