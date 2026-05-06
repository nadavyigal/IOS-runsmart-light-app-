import SwiftUI

struct LiveRunView: View {
    var metrics: [MetricTile]
    var routePoints: [RunRoutePoint]
    var phase: RunRecordingPhase
    var gpsStatus: String
    var gpsDetail: String
    var onPauseResume: () -> Void
    var onFinish: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                RunSmartTopBar(title: "Run")

                GPSStatusPill(status: gpsStatus, detail: gpsDetail, phase: phase)

                RunSmartPanel(cornerRadius: 22, padding: 0, accent: .accentPrimary) {
                    if let primaryMetric = metrics.first {
                        VStack(spacing: 0) {
                            LiveMetricCard(metric: primaryMetric, isPrimary: true)
                                .padding(.horizontal, 18)
                                .padding(.top, 16)
                                .padding(.bottom, 12)

                            HStack(spacing: 0) {
                                ForEach(Array(metrics.dropFirst().enumerated()), id: \.element.id) { index, metric in
                                    LiveMetricCard(metric: metric, isPrimary: false)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, minHeight: 94)
                                        .overlay(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.border.opacity(0.72))
                                                .frame(width: index == 0 ? 0 : 1)
                                        }
                                }
                            }
                        }
                    }
                }
                .frame(height: max(208, min(260, proxy.size.height * 0.31)))

                if routePoints.isEmpty {
                    RunSmartRoutePreview(title: "GPS", showGPS: true, height: max(112, min(154, proxy.size.height * 0.18)))
                } else {
                    RunSmartPanel(cornerRadius: 20, padding: 8) {
                        RouteMapView(points: routePoints, title: "GPS")
                            .frame(height: max(104, min(146, proxy.size.height * 0.17)))
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 18) {
                    LiveControlButton(title: phase == .paused ? "Resume" : "Pause", symbol: phase == .paused ? "play.fill" : "pause.fill", tint: .accentPrimary, prominent: true, action: onPauseResume)
                    LiveControlButton(title: "Finish", symbol: "stop.fill", tint: .accentHeart, prominent: false, action: onFinish)
                }
                .padding(.bottom, 4)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(Color.textPrimary)
        .background(Color.black.opacity(0.52).ignoresSafeArea())
    }
}

private struct LiveMetricCard: View {
    var metric: MetricTile
    var isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(metric.title.uppercased(), systemImage: metric.symbol)
                .font(.labelSM)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(metric.value)
                .font(isPrimary ? .displayXL : .metric)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(metric.unit)
                .font(.labelSM)
                .foregroundStyle(metric.tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: prominent ? 34 : 24, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : tint)
                    .frame(width: prominent ? 128 : 86, height: prominent ? 128 : 86)
                    .background(prominent ? tint : Color.surfaceCard)
                    .clipShape(Circle())
                Text(title)
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
