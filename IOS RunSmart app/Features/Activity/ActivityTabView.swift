import SwiftUI

struct ActivityTabView: View {
    @Environment(\.runSmartServices) private var services
    @State private var runs: [RecordedRun] = []

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
                            ActivityRunRow(run: run)
                            if run.id != runs.prefix(6).last?.id {
                                Divider()
                                    .background(Color.border)
                            }
                        }
                    }
                }
                .runSmartStaggeredAppear(index: 1)

                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Personal records")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ActivityRecordTile(distance: "5K", time: "23:48", tint: .accentPrimary)
                            ActivityRecordTile(distance: "10K", time: "49:15", tint: .accentEnergy)
                            ActivityRecordTile(distance: "Half", time: "1:51:02", tint: .accentRecovery)
                            ActivityRecordTile(distance: "Marathon", time: "--", tint: .textTertiary)
                        }
                    }
                }
                .runSmartStaggeredAppear(index: 2)
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

private struct ActivityRunRow: View {
    var run: RecordedRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.black)
                .frame(width: 38, height: 38)
                .background(Color.accentPrimary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(run.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.bodyMD)
                    .foregroundStyle(Color.textPrimary)
                Text(run.source.rawValue)
                    .font(.labelSM)
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(run.distanceKmLabel)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(run.paceLabel)
                    .font(.metricXS)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ActivityRecordTile: View {
    var distance: String
    var time: String
    var tint: Color

    var body: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(distance.uppercased())
                        .font(.labelSM)
                        .tracking(1.1)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                }
                Text(time)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

private extension RecordedRun {
    var distanceKmLabel: String {
        String(format: "%.1f km", distanceMeters / 1_000)
    }

    var paceLabel: String {
        let minutes = Int(averagePaceSecondsPerKm) / 60
        let seconds = Int(averagePaceSecondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
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
