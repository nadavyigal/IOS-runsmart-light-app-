import SwiftUI

struct RecoveryDashboardView: View {
    @Environment(\.runSmartServices) private var services
    @State private var recovery: RecoverySnapshot = .loading
    @State private var trends: WellnessTrendSeries = .empty
    // Drives Garmin attribution: only shown when Garmin Connect is actually a data source,
    // so we never mischaracterize HealthKit-only data as Garmin-sourced.
    @State private var garminConnected = false
    @State private var garminDeviceName: String?

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
                    // Garmin API Brand Guidelines (Health): device-sourced data on primary
                    // displays must carry a "Garmin [device model]" attribution adjacent to the
                    // heading, above the fold. Falls back to "Garmin" if no device name has been
                    // recorded yet (Garmin only reports device identity on activity records).
                    if garminConnected {
                        Text(garminDeviceName ?? "Garmin")
                            .font(.labelSM)
                            .foregroundStyle(Color.textTertiary)
                    }
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
                attribution: trends.latestHRVSource.attributionLabel ?? recovery.hrvSource.attributionLabel,
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

            // Garmin API Brand Guidelines (Health): approved attribution line for AI/derived
            // insights built in part from Garmin device-sourced data.
            if garminConnected {
                Text("Insights derived in part from Garmin device-sourced data.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .task {
            async let recoveryTask = services.recoverySnapshot()
            async let trendTask = services.wellnessTrendSeries(days: 7)
            async let statusTask = services.deviceStatuses()
            let statuses = await statusTask
            (recovery, trends) = await (recoveryTask, trendTask)
            let garminStatus = statuses.first { $0.provider == "Garmin Connect" }
            garminConnected = garminStatus?.state == .connected
            garminDeviceName = garminStatus?.deviceName
        }
    }
}

private struct RecoveryTrendTile: View {
    var title: String
    var value: String
    var attribution: String? = nil
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
                if let attribution {
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
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
            .accessibilityLabel(
                attribution.map { "\(title), \($0), \(value), \(detail)" }
                    ?? "\(title), \(value), \(detail)"
            )
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
