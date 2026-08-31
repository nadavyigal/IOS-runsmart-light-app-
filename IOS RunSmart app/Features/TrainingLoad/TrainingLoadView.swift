import Charts
import SwiftUI

/// The Acute Load timeline: how hard the last four weeks have been, against the
/// range that is optimal for the training history behind them.
///
/// This is computed by RunSmart from session-RPE, not imported from a watch.
/// Garmin does not expose acute load or training status through its partner
/// APIs at any scope, and computing it here means it works for runners with no
/// wearable at all. Do not attach Garmin attribution to this screen.
struct TrainingLoadView: View {
    @Environment(\.runSmartServices) private var services

    static let windowDays = 28

    static let acuteWindowDays = 7

    @State private var presentation: TrainingLoadPresentation = .empty
    @State private var sessions: [ExerciseLoadEntry] = []
    @State private var isLoading = true
    @State private var mode: TrainingLoadMode = .acuteLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Training load")
                    Text("\(Self.windowDays)-day timeline")
                        .font(.headingLG)
                    headline
                }
            }

            Picker("Series", selection: $mode) {
                Text("Acute Load").tag(TrainingLoadMode.acuteLoad)
                Text("Load Ratio").tag(TrainingLoadMode.loadRatio)
            }
            .pickerStyle(.segmented)

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    if presentation.hasChart {
                        switch mode {
                        case .acuteLoad: chart
                        case .loadRatio: ratioChart
                        }
                        legend
                        if mode == .loadRatio {
                            ratioFooter
                        }
                    }
                    if !isLoading {
                        progressNote
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            if !isLoading, presentation.status != .insufficientData {
                ContentCard {
                    VStack(alignment: .leading, spacing: 6) {
                        statusTitle
                            .font(.headingMD)
                        recommendation
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !isLoading, !sessions.isEmpty {
                exerciseLoadSection
            }
        }
        .task {
            let runs = await services.recentRuns()
            presentation = TrainingLoadPresentation.make(
                from: TrainingLoadCalculator.series(runs: runs, days: Self.windowDays)
            )
            sessions = ExerciseLoadEntry.acuteWindow(runs: runs, days: Self.acuteWindowDays)
            isLoading = false
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var headline: some View {
        if let value = headlineValue, presentation.status != .insufficientData {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.metricSM)
                    .monospacedDigit()
                statusTitle
                    .font(.headingMD)
                    .foregroundStyle(Color.textSecondary)
            }
        } else {
            Text("Not enough history yet")
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(presentation.points) { point in
                AreaMark(
                    x: .value("Day", point.date),
                    yStart: .value("Optimal low", point.optimalLow),
                    yEnd: .value("Optimal high", point.optimalHigh)
                )
                .foregroundStyle(Color.accentSuccess.opacity(0.25))
            }
            ForEach(presentation.points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Acute load", point.acuteLoad)
                )
                .foregroundStyle(Color.textPrimary)
                .interpolationMethod(.monotone)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 200)
        .accessibilityLabel(Text("Acute load over the last \(presentation.windowDays) days"))
    }

    /// The ratio view of the same data. The band is the ratio range itself
    /// (0.8...1.3) rather than a load figure, so it is a flat rail here while
    /// the acute-load chart's band moves with chronic load.
    private var ratioChart: some View {
        Chart {
            RectangleMark(
                xStart: .value("Start", presentation.points.first?.date ?? Date()),
                xEnd: .value("End", presentation.points.last?.date ?? Date()),
                yStart: .value("Optimal low", TrainingLoadPresentation.optimalRatioRange.lowerBound),
                yEnd: .value("Optimal high", TrainingLoadPresentation.optimalRatioRange.upperBound)
            )
            .foregroundStyle(Color.accentSuccess.opacity(0.25))

            ForEach(presentation.points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Load ratio", point.acwr)
                )
                .foregroundStyle(Color.textPrimary)
                .interpolationMethod(.monotone)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 200)
        .accessibilityLabel(Text("Load ratio over the last \(presentation.windowDays) days"))
    }

    /// Mirrors the Acute / Chronic pair Garmin prints under its ratio chart.
    @ViewBuilder
    private var ratioFooter: some View {
        if let acute = presentation.currentAcuteLoad, let chronic = presentation.currentChronicLoad {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.wholeNumber(acute))
                        .font(.headingLG)
                        .monospacedDigit()
                    Text("Acute Load")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.wholeNumber(chronic))
                        .font(.headingLG)
                        .monospacedDigit()
                    Text("Chronic Load")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    /// The runs behind the acute number, newest first — Garmin's Exercise Load
    /// tab, kept on this screen rather than split off, so the input sits next
    /// to the total it produces.
    private var exerciseLoadSection: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Exercise load")
                Text("The runs behind your \(Self.acuteWindowDays)-day acute load.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                ForEach(sessions) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.bodyMD)
                            Spacer()
                            Text(Self.wholeNumber(entry.load))
                                .font(.headingMD)
                                .monospacedDigit()
                        }
                        HStack(spacing: 6) {
                            Text("\(entry.distanceKm, specifier: "%.1f") km · \(entry.durationMinutes) min")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                            effortSourceLabel(entry.effortSource)
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    if entry.id != sessions.last?.id {
                        Divider().background(Color.border)
                    }
                }
            }
        }
    }

    /// Names where the effort estimate came from. An assumed-moderate run still
    /// contributes real load from a guess, so saying so is the honest default.
    @ViewBuilder
    private func effortSourceLabel(_ source: TrainingLoadCalculator.EffortSource) -> some View {
        switch source {
        case .reportedRPE: Text("your effort rating")
        case .heartRate: Text("from heart rate")
        case .assumedModerate: Text("assumed moderate")
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Label {
                Text("Optimal range")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } icon: {
                Circle().fill(Color.accentSuccess.opacity(0.45)).frame(width: 10, height: 10)
            }
            Label {
                Group {
                    switch mode {
                    case .acuteLoad: Text("Acute load")
                    case .loadRatio: Text("Load ratio")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            } icon: {
                Circle().fill(Color.textPrimary).frame(width: 10, height: 10)
            }
        }
    }

    /// Same contract as the wellness trends panel: never a bare "no data".
    /// Say why the window is thin and how far along it is.
    @ViewBuilder
    private var progressNote: some View {
        if presentation.daysCollected == 0 {
            Text("Log four runs in a month and your load timeline starts here.")
        } else if presentation.daysCollected < presentation.windowDays {
            Text("Day \(presentation.daysCollected) of \(presentation.windowDays) — this fills in as you run.")
        } else {
            Text("Based on your last \(presentation.windowDays) days of running.")
        }
    }

    @ViewBuilder
    private var statusTitle: some View {
        switch presentation.status {
        case .detraining: Text("Low")
        case .optimal: Text("Optimal")
        case .elevated: Text("Elevated")
        case .highRisk: Text("High")
        case .insufficientData: Text("Building")
        }
    }

    @ViewBuilder
    private var recommendation: some View {
        switch presentation.status {
        case .detraining:
            Text("Your acute load is below your optimal range. There is room to add a little volume.")
        case .optimal:
            Text("Your acute load is inside your optimal range. Keep it steady.")
        case .elevated:
            Text("Your acute load is above your optimal range. Consider adding more time to recover.")
        case .highRisk:
            Text("Your acute load is well above your optimal range. Back off and recover before the next hard session.")
        case .insufficientData:
            Text("Keep logging runs to see where your load sits.")
        }
    }

    /// Acute load reads as a whole number, the ratio to one decimal — matching
    /// how each is conventionally quoted ("500" vs "1.5").
    private var headlineValue: String? {
        switch mode {
        case .acuteLoad:
            return presentation.currentAcuteLoad.map(Self.wholeNumber)
        case .loadRatio:
            return presentation.currentACWR.map(Self.ratioNumber)
        }
    }

    private static func wholeNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func ratioNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
