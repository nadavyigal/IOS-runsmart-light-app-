import SwiftUI

struct LiveRunView: View {
    var metrics: [MetricTile]
    var routePoints: [RunRoutePoint]
    var phase: RunRecordingPhase
    var coachCue: String
    var onPauseResume: () -> Void
    var onLap: () -> Void
    var onLock: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(phase == .paused ? "Paused" : "Live Run")
                    .font(.headingLG)
                Spacer()
                Text("GPS")
                    .font(.labelSM)
                    .tracking(1.1)
                    .foregroundStyle(Color.accentRecovery)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(metrics) { metric in
                    LiveMetricCard(metric: metric, isPrimary: metric.title == "Distance")
                }
            }
            .padding(.horizontal, 18)

            ContentCard(padding: 8) {
                RouteMapView(points: routePoints, title: routePoints.isEmpty ? "GPS route" : "Live route")
                    .frame(height: 128)
            }
            .padding(.horizontal, 18)

            ContentCard {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentPrimary)
                    Text(coachCue)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)

            HStack(spacing: 28) {
                LiveControlButton(title: "Lap", symbol: "flag.fill", tint: .accentRecovery, action: onLap)
                LiveControlButton(title: phase == .paused ? "Resume" : "Pause", symbol: phase == .paused ? "play.fill" : "pause.fill", tint: .accentPrimary, prominent: true, action: onPauseResume)
                LiveControlButton(title: "Lock", symbol: "lock.fill", tint: .textSecondary, action: onLock)
            }

            Button(action: onFinish) {
                Label("Finish Run", systemImage: "stop.fill")
            }
            .buttonStyle(NeonButtonStyle(isDestructive: true))
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .foregroundStyle(Color.textPrimary)
        .background(Color.black.opacity(0.52).ignoresSafeArea())
    }
}

private struct LiveMetricCard: View {
    var metric: MetricTile
    var isPrimary: Bool

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(metric.title.uppercased(), systemImage: metric.symbol)
                    .font(.labelSM)
                    .tracking(1.1)
                    .foregroundStyle(Color.textSecondary)
                Text(metric.value)
                    .font(isPrimary ? .displayLG : .metric)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(metric.unit)
                    .font(.labelSM)
                    .foregroundStyle(metric.tint)
            }
            .frame(maxWidth: .infinity, minHeight: isPrimary ? 136 : 104, alignment: .leading)
        }
    }
}

private struct LiveControlButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 24 : 18, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : tint)
                    .frame(width: prominent ? 72 : 56, height: prominent ? 72 : 56)
                    .background(prominent ? tint : Color.surfaceCard)
                    .clipShape(Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
    }
}
