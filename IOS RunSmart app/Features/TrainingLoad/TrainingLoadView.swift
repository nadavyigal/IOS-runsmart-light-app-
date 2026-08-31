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

    @State private var presentation: TrainingLoadPresentation = .empty
    @State private var isLoading = true

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

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    if presentation.hasChart {
                        chart
                        legend
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
        }
        .task {
            let runs = await services.recentRuns()
            presentation = TrainingLoadPresentation.make(
                from: TrainingLoadCalculator.series(runs: runs, days: Self.windowDays)
            )
            isLoading = false
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var headline: some View {
        if let acute = presentation.currentAcuteLoad, presentation.status != .insufficientData {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.wholeNumber(acute))
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
                Text("Acute load")
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

    private static func wholeNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
