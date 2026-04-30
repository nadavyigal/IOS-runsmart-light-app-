import SwiftUI

struct PostRunSummaryView: View {
    var run: RecordedRun?
    var onDone: () -> Void
    @State private var rpe = 6

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HeroCard(accent: .accentSuccess) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(title: "Run complete")
                        Text(distanceLabel)
                            .font(.displayXL)
                            .monospacedDigit()
                            .displayTightTracking()
                        Text("Saved with route, pace, time, and effort context.")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                        RouteMapView(points: run?.routePoints ?? [], title: "Completed route")
                            .frame(height: 150)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SummaryMetric(title: "Time", value: timeLabel, tint: .accentPrimary)
                    SummaryMetric(title: "Pace", value: paceLabel, tint: .accentEnergy)
                    SummaryMetric(title: "Heart", value: heartLabel, tint: .accentHeart)
                    SummaryMetric(title: "Source", value: run?.source.rawValue ?? "GPS", tint: .accentRecovery)
                }

                RPESelector(value: $rpe)

                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Coach analysis")
                        Text("RPE \(rpe)/10 gives the coach a useful effort signal. If this felt harder than planned, the next run should stay easy.")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onDone) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(NeonButtonStyle())
                }
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
    }

    private var distanceLabel: String {
        guard let run else { return "5.2 km" }
        return String(format: "%.2f km", run.distanceMeters / 1_000)
    }

    private var timeLabel: String {
        guard let run else { return "26:54" }
        let minutes = Int(run.movingTimeSeconds) / 60
        let seconds = Int(run.movingTimeSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var paceLabel: String {
        guard let run else { return "5:10" }
        let minutes = Int(run.averagePaceSecondsPerKm) / 60
        let seconds = Int(run.averagePaceSecondsPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var heartLabel: String {
        guard let bpm = run?.averageHeartRateBPM else { return "--" }
        return "\(bpm)"
    }
}

private struct SummaryMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 7) {
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
