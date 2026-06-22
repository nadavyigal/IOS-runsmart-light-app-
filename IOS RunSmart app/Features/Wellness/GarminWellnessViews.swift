import SwiftUI

struct GarminWellnessViews: View {
    @Environment(\.runSmartServices) private var services
    @State private var recovery: RecoverySnapshot = .loading
    @State private var wellness: WellnessSnapshot = .empty
    @State private var trends: WellnessTrendSeries = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentRecovery) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Garmin wellness")
                    // Garmin API Brand Guidelines (Health): device-sourced data must carry a
                    // "Garmin [device model]" attribution adjacent to the heading, above the fold.
                    // This whole view is Garmin wellness data (Body Battery is Garmin-exclusive),
                    // so attribution is unconditional. Device model not surfaced → list "Garmin".
                    Text("Garmin")
                        .font(.labelSM)
                        .foregroundStyle(Color.textTertiary)
                    Text(sourceTitle)
                        .font(.headingLG)
                    Text(wellness.checkInStatus)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            WellnessPanel(title: "Readiness", value: recovery.readiness > 0 ? "\(recovery.readiness)" : "--", detail: recovery.recommendation, tint: .accentSuccess, symbol: "bolt.heart.fill")
            WellnessPanel(title: "Body Battery", value: recovery.bodyBattery > 0 ? "\(recovery.bodyBattery)" : "--", detail: wellness.hydration, tint: .accentPrimary, symbol: "battery.75percent")
            WellnessPanel(title: "Sleep", value: recovery.sleep, detail: "Latest Garmin sleep value when connected.", tint: .accentRecovery, symbol: "bed.double.fill")
            WellnessPanel(title: "HRV", value: recovery.hrv, detail: "Latest synced HRV value.", tint: .accentHeart, symbol: "waveform.path.ecg")
            WellnessPanel(title: "Manual Check-In", value: wellness.mood, detail: "Soreness \(wellness.soreness)", tint: .accentEnergy, symbol: "checklist.checked")
            WellnessTrendPanel(
                title: "HRV Trend (7-day)",
                value: trends.latestHRVDisplay,
                summary: trends.hrvTrendSummary,
                bars: trends.hrvBars,
                tint: .accentHeart
            )
            WellnessTrendPanel(
                title: "Training Readiness (7-day)",
                value: trends.latestReadinessDisplay,
                summary: trends.readinessTrendSummary,
                bars: trends.readinessBars,
                tint: .accentPrimary
            )

            // Garmin API Brand Guidelines (Health): approved attribution line for derived insights.
            Text("Insights derived in part from Garmin device-sourced data.")
                .font(.caption)
                .italic()
                .foregroundStyle(Color.textTertiary)
        }
        .task {
            async let recoveryTask = services.recoverySnapshot()
            async let wellnessTask = services.wellnessSnapshot()
            async let trendTask = services.wellnessTrendSeries(days: 7)
            (recovery, wellness, trends) = await (recoveryTask, wellnessTask, trendTask)
        }
    }

    private var sourceTitle: String {
        recovery.readiness > 0 ? "Synced health signals" : "No Garmin recovery data yet"
    }
}

private struct WellnessTrendPanel: View {
    var title: String
    var value: String
    var summary: String
    var bars: [CGFloat]
    var tint: Color

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headingMD)
                    Spacer()
                    Text(value)
                        .font(.metricXS)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                if bars.isEmpty {
                    Text("Need more synced days")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    MetricBars(values: bars, tint: tint)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(value), \(summary)")
        }
    }
}

private struct WellnessPanel: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color
    var symbol: String

    var body: some View {
        ContentCard {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headingMD)
                    Text(detail)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(value)
                    .font(.metricSM)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
