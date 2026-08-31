import Foundation

/// One plotted day: the acute load, plus the optimal band for that day.
///
/// The band is expressed against *that day's* chronic load, which is why it
/// moves with training history rather than sitting at a fixed height.
struct TrainingLoadChartPoint: Hashable, Identifiable {
    let date: Date
    let acuteLoad: Double
    let optimalLow: Double
    let optimalHigh: Double
    /// Acute:chronic ratio for that day. Non-optional because only scored days
    /// are plotted, and a scored day always has a ratio.
    let acwr: Double

    var id: Date { date }

    /// True when the acute load sits inside the optimal band for that day.
    var isInsideOptimalRange: Bool {
        acuteLoad >= optimalLow && acuteLoad <= optimalHigh
    }
}

/// Which series the Training Load screen is showing. Mirrors the two-way
/// toggle in Garmin's Training Load tab.
enum TrainingLoadMode: String, CaseIterable, Hashable {
    case acuteLoad
    case loadRatio
}

/// One run's contribution to acute load — the input side of the headline
/// number, equivalent to Garmin's Exercise Load tab.
struct ExerciseLoadEntry: Hashable, Identifiable {
    let id: UUID
    let date: Date
    let load: Double
    let durationMinutes: Int
    let distanceKm: Double
    let effortSource: TrainingLoadCalculator.EffortSource

    /// Builds the list for the acute window, newest first.
    ///
    /// Scoped to the acute window on purpose: this list exists to explain the
    /// acute number above it, so showing runs that no longer contribute would
    /// invite the reader to add them up and get a different total.
    static func acuteWindow(
        runs: [RecordedRun],
        days: Int = 7,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ExerciseLoadEntry] {
        guard days > 0 else { return [] }
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now

        return runs
            .filter { $0.startedAt >= start && $0.startedAt <= now }
            .sorted { $0.startedAt > $1.startedAt }
            .map { run in
                ExerciseLoadEntry(
                    id: run.id,
                    date: run.startedAt,
                    load: TrainingLoadCalculator.sessionLoad(for: run),
                    durationMinutes: Int((run.movingTimeSeconds / 60.0).rounded()),
                    distanceKm: run.distanceMeters / 1000.0,
                    effortSource: TrainingLoadCalculator.effortSource(for: run)
                )
            }
    }
}

/// View state for the Training Load chart. Pure and testable: it holds numbers
/// and a status, never user-facing copy. The view switches on `status` with
/// literal `Text`, so every string stays in Localizable.xcstrings.
struct TrainingLoadPresentation: Hashable {

    /// Optimal acute:chronic band. Must stay in lockstep with the thresholds in
    /// `TrainingLoadCalculator.status(for:)` (0.8 detraining / 1.3 optimal), or
    /// the chart would contradict the status word printed beside it.
    static let optimalRatioRange: ClosedRange<Double> = 0.8...1.3

    let points: [TrainingLoadChartPoint]
    let currentAcuteLoad: Double?
    let currentChronicLoad: Double?
    let currentACWR: Double?
    let status: TrainingLoadStatus
    /// Days in the window that actually have enough history to be scored.
    let daysCollected: Int
    let windowDays: Int

    var hasChart: Bool { !points.isEmpty }

    static let empty = TrainingLoadPresentation(
        points: [],
        currentAcuteLoad: nil,
        currentChronicLoad: nil,
        currentACWR: nil,
        status: .insufficientData,
        daysCollected: 0,
        windowDays: 0
    )

    /// Builds the chart state from a calculator series.
    ///
    /// Days that cannot be scored yet are dropped rather than plotted as zero:
    /// a flat run of zeros during ramp-up reads as "you did nothing", which is
    /// false. `daysCollected` reports how many real days are behind the chart
    /// so the view can say how far along the window is.
    static func make(from series: [DailyTrainingLoadPoint]) -> TrainingLoadPresentation {
        // A scored day always carries a ratio (the calculator only omits it when
        // it also reports .insufficientData), but compactMap rather than force
        // unwrap so a future change to that contract drops a point instead of
        // crashing the screen.
        let scored = series.filter { $0.status != .insufficientData }

        let points = scored.compactMap { day -> TrainingLoadChartPoint? in
            guard let acwr = day.acwr else { return nil }
            return TrainingLoadChartPoint(
                date: day.date,
                acuteLoad: day.acuteLoad,
                optimalLow: day.chronicLoad * optimalRatioRange.lowerBound,
                optimalHigh: day.chronicLoad * optimalRatioRange.upperBound,
                acwr: acwr
            )
        }

        let latest = series.last
        return TrainingLoadPresentation(
            points: points,
            currentAcuteLoad: latest.map(\.acuteLoad),
            currentChronicLoad: latest.map(\.chronicLoad),
            currentACWR: latest?.acwr,
            status: latest?.status ?? .insufficientData,
            // Counts what is actually plotted, so "day N of M" can never claim
            // more days than the chart shows.
            daysCollected: points.count,
            windowDays: series.count
        )
    }
}
