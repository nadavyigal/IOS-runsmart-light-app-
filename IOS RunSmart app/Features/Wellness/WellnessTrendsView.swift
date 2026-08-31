import SwiftUI

struct WellnessTrendsView: View {
    /// Single source for the trend window: the fetch, and the "day N of M" note.
    /// The panel titles keep the literal "(7-day)" so their string-catalog keys stay stable.
    static let trendWindowDays = 7

    @Environment(\.runSmartServices) private var services
    @State private var recovery: RecoverySnapshot = .loading
    @State private var wellness: WellnessSnapshot = .empty
    @State private var trends: WellnessTrendSeries = .empty
    @State private var garminConnected = false
    @State private var garminDeviceName: String?

    private var garminAttributionLabel: String? {
        guard garminConnected, recovery.includesGarminDeviceSourcedData || !trends.days.isEmpty else { return nil }
        return RunSmartAttribution.garminDeviceLabel(deviceName: nil, fallbackGarminDeviceName: garminDeviceName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentRecovery) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Wellness trends")
                    // Garmin API Brand Guidelines (Health): device-sourced data must carry a
                    // "Garmin [device model]" attribution adjacent to the heading, above the fold.
                    // This whole view is Garmin wellness data (Body Battery is Garmin-exclusive),
                    // so attribution appears only when the loaded snapshot/trends actually include
                    // Garmin device-sourced data. Falls back to "Garmin" if no device name has
                    // been recorded yet (Garmin only reports device identity on activities).
                    if let garminAttributionLabel {
                        Text(garminAttributionLabel)
                            .font(.labelSM)
                            .foregroundStyle(Color.textTertiary)
                    }
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
                tint: .accentHeart,
                garminConnected: garminConnected,
                windowDays: Self.trendWindowDays
            )
            WellnessTrendPanel(
                title: "Training Readiness (7-day)",
                value: trends.latestReadinessDisplay,
                summary: trends.readinessTrendSummary,
                bars: trends.readinessBars,
                tint: .accentPrimary,
                garminConnected: garminConnected,
                windowDays: Self.trendWindowDays
            )

            // Garmin API Brand Guidelines (Health): approved attribution line for derived insights.
            if garminAttributionLabel != nil {
                Text("Insights derived in part from Garmin device-sourced data.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .task {
            async let recoveryTask = services.recoverySnapshot()
            async let wellnessTask = services.wellnessSnapshot()
            async let trendTask = services.wellnessTrendSeries(days: Self.trendWindowDays)
            async let statusTask = services.deviceStatuses()
            let statuses = await statusTask
            (recovery, wellness, trends) = await (recoveryTask, wellnessTask, trendTask)
            let garminStatus = statuses.first { $0.provider == "Garmin Connect" }
            garminConnected = garminStatus?.state == .connected
            garminDeviceName = garminStatus?.deviceName
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
    var garminConnected: Bool
    var windowDays: Int

    private var showsProgressNote: Bool {
        bars.isEmpty || bars.count < windowDays
    }

    /// Garmin's partner APIs only deliver data recorded *after* the user connects
    /// (Garmin policy, November 2025) — there is no historical backfill. A runner who
    /// connects today therefore sees an empty trend for a week. Say so plainly, with
    /// the day count, so a filling window does not read as a broken feature.
    /// Each branch keeps a literal `Text` so SwiftUI still extracts it into
    /// Localizable.xcstrings; a computed String would silently bypass the catalog.
    @ViewBuilder
    private var progressNote: some View {
        if !garminConnected {
            Text("Connect a Garmin device to start this \(windowDays)-day trend.")
        } else if bars.isEmpty {
            Text("Garmin sends data from the day you connect, so this starts empty. Your first reading appears after the next sync.")
        } else {
            Text("Day \(bars.count) of \(windowDays) — this fills in as you sync.")
        }
    }

    /// Mirrors `progressNote` for VoiceOver, which reads the combined element.
    private var progressNoteAccessibilityText: String {
        if !garminConnected {
            return String(localized: "Connect a Garmin device to start this \(windowDays)-day trend.")
        }
        if bars.isEmpty {
            return String(localized: "Garmin sends data from the day you connect, so this starts empty. Your first reading appears after the next sync.")
        }
        return String(localized: "Day \(bars.count) of \(windowDays) — this fills in as you sync.")
    }

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
                if !bars.isEmpty {
                    MetricBars(values: bars, tint: tint)
                }
                if showsProgressNote {
                    progressNote
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                showsProgressNote
                    ? "\(title), \(value), \(summary), \(progressNoteAccessibilityText)"
                    : "\(title), \(value), \(summary)"
            )
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
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headingMD)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(detail)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(value)
                    .font(.metricSM)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(value), \(detail)")
        }
    }
}
