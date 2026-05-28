import SwiftUI

struct RecoveryDashboardView: View {
    @Environment(\.runSmartServices) private var services
    @State private var recovery: RecoverySnapshot = .loading
    @State private var trends: WellnessTrendSeries = .empty

    private var readinessValue: Double {
        min(1.0, max(0.0, Double(recovery.readiness) / 100.0))
    }

    private var readinessLabel: String {
        switch recovery.readiness {
        case 75...: return "READY TO TRAIN"
        case 50..<75: return "MODERATE DAY"
        default: return "RECOVERY FIRST"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentSuccess) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Recovery dashboard", trailing: "Today")
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(recovery.readiness)")
                                .font(.displayXL)
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                                .displayTightTracking()
                            Text(readinessLabel)
                                .font(.labelSM)
                                .tracking(1.2)
                                .foregroundStyle(Color.accentSuccess)
                        }
                        Spacer()
                        ProgressRing(value: readinessValue, lineWidth: 12, icon: "bolt.fill", tint: .accentSuccess)
                            .frame(width: 118, height: 118)
                            .runSmartPulse(scale: 1.018)
                    }
                    Text(recovery.recommendation)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            RecoveryTrendTile(
                title: "HRV",
                value: trends.latestHRVDisplay,
                detail: trends.hrvTrendSummary,
                bars: trends.hrvBars,
                tint: .accentHeart
            )
            RecoveryTrendTile(
                title: "Training Readiness",
                value: trends.latestReadinessDisplay,
                detail: trends.readinessTrendSummary,
                bars: trends.readinessBars,
                tint: .accentPrimary
            )

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach read")
                    RecoveryReadRow(title: "Train", detail: trends.readinessTrendSummary, tint: .accentSuccess)
                    RecoveryReadRow(title: "Watch", detail: "Use the first 10 minutes to check breathing and leg feel.", tint: .accentPrimary)
                    RecoveryReadRow(title: "Recover", detail: "Protect sleep quality and easy-day effort when trend dips.", tint: .accentRecovery)
                }
            }
        }
        .task {
            async let recoveryTask = services.recoverySnapshot()
            async let trendTask = services.wellnessTrendSeries(days: 7)
            (recovery, trends) = await (recoveryTask, trendTask)
        }
    }
}

private struct RecoveryTrendTile: View {
    var title: String
    var value: String
    var detail: String
    var bars: [CGFloat]
    var tint: Color

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(title.uppercased())
                    .font(.labelSM)
                    .tracking(1.1)
                    .foregroundStyle(Color.textSecondary)
                Text(value)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                if bars.isEmpty {
                    Text("Need more synced days")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    MetricBars(values: bars, tint: tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(value), \(detail)")
        }
    }
}

private struct RecoveryReadRow: View {
    var title: String
    var detail: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.1)
                .foregroundStyle(tint)
                .frame(width: 70, alignment: .leading)
            Text(detail)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
