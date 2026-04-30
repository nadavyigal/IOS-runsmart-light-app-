import SwiftUI

struct ActivityTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @State private var runs: [RecordedRun] = []
    @State private var filter = "All"

    private var totalDistanceKm: Double {
        runs.reduce(0) { $0 + $1.distanceMeters / 1_000 }
    }

    private var totalMovingTime: TimeInterval {
        runs.reduce(0) { $0 + $1.movingTimeSeconds }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                RunSmartHeader(title: "Activity")

                HStack(spacing: 0) {
                    ForEach(["All", "Runs", "Workouts"], id: \.self) { option in
                        Button { filter = option } label: {
                            Text(option.uppercased())
                                .font(.labelSM)
                                .tracking(1.1)
                                .foregroundStyle(filter == option ? Color.black : Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(filter == option ? Color.accentPrimary : Color.surfaceElevated)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HeroCard(accent: .accentSuccess) {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionLabel(title: "This week")
                        HStack(alignment: .firstTextBaseline) {
                            Text(totalDistanceKm, format: .number.precision(.fractionLength(1)))
                                .font(.displayLG)
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                                .displayTightTracking(-1.2)
                            Text("km")
                                .font(.labelLG)
                                .foregroundStyle(Color.accentPrimary)
                            Spacer()
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title2)
                                .foregroundStyle(Color.accentSuccess)
                        }

                        HStack(spacing: 10) {
                            ActivityMetricPill(title: "Runs", value: "\(runs.count)", tint: .accentSuccess)
                            ActivityMetricPill(title: "Time", value: totalMovingTime.activityDurationLabel, tint: .accentRecovery)
                            ActivityMetricPill(title: "Plan", value: "82%", tint: .accentPrimary)
                        }
                    }
                }
                .runSmartStaggeredAppear(index: 0)

                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Recent runs", trailing: "All")
                        ForEach(runs.prefix(6)) { run in
                            ActivityRow(run: run) {
                                router.open(.shareRun(run))
                            }
                            if run.id != runs.prefix(6).last?.id {
                                Divider()
                                    .background(Color.border)
                            }
                        }
                    }
                }
                .runSmartStaggeredAppear(index: 1)

                Button { router.open(.zoneAnalysis) } label: {
                    ContentCard {
                        HStack(spacing: 14) {
                            Image(systemName: "heart.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentHeart)
                                .frame(width: 46, height: 46)
                                .background(Color.accentHeart.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Zone Analysis")
                                    .font(.headingMD)
                                Text("Review effort distribution across recent training.")
                                    .font(.bodyMD)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .runSmartStaggeredAppear(index: 2)

                PersonalRecordsCard()
                .runSmartStaggeredAppear(index: 3)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            runs = await services.recentRuns()
        }
    }
}

private struct ActivityMetricPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(.labelSM)
                    .tracking(1.1)
                    .foregroundStyle(Color.textSecondary)
                Text(value)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension TimeInterval {
    var activityDurationLabel: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
