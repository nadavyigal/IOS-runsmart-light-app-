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

    var id: Date { date }

    /// True when the acute load sits inside the optimal band for that day.
    var isInsideOptimalRange: Bool {
        acuteLoad >= optimalLow && acuteLoad <= optimalHigh
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
        let scored = series.filter { $0.status != .insufficientData }

        let points = scored.map { day in
            TrainingLoadChartPoint(
                date: day.date,
                acuteLoad: day.acuteLoad,
                optimalLow: day.chronicLoad * optimalRatioRange.lowerBound,
                optimalHigh: day.chronicLoad * optimalRatioRange.upperBound
            )
        }

        let latest = series.last
        return TrainingLoadPresentation(
            points: points,
            currentAcuteLoad: latest.map(\.acuteLoad),
            currentChronicLoad: latest.map(\.chronicLoad),
            currentACWR: latest?.acwr,
            status: latest?.status ?? .insufficientData,
            daysCollected: scored.count,
            windowDays: series.count
        )
    }
}
