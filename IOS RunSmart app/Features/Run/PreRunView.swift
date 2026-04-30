import SwiftUI

struct PreRunView: View {
    var metrics: [MetricTile]
    var onStart: () -> Void
    var onRoute: () -> Void
    var onAudio: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                RunSmartHeader(title: "Run")

                HeroCard(accent: .accentEnergy) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(title: "Ready to run")
                        Text("Tempo Builder")
                            .font(.headingLG)
                        Text("8.2 km · 45-55 min · controlled threshold")
                            .font(.metricSM)
                            .foregroundStyle(Color.accentPrimary)
                        RouteMapView(points: [], title: "Select route")
                            .frame(height: 142)
                        Button(action: onStart) {
                            VStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30, weight: .black))
                                Text("START RUN")
                                    .font(.labelLG)
                                    .tracking(1.5)
                            }
                            .foregroundStyle(Color.black)
                            .frame(width: 92, height: 92)
                            .background(
                                Circle()
                                    .fill(LinearGradient(colors: [.accentPrimary, .accentEnergy], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: Color.accentPrimary.opacity(0.42), radius: 24)
                            .frame(maxWidth: .infinity)
                            .runSmartPulse(scale: 1.035)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    RunOptionButton(title: "Route", symbol: "map.fill", tint: .accentRecovery, action: onRoute)
                    RunOptionButton(title: "Audio", symbol: "speaker.wave.2.fill", tint: .accentPrimary, action: onAudio)
                }

                WeatherConditionsCard()

                if !metrics.isEmpty {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Last run")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                                ForEach(metrics.prefix(4)) { metric in
                                    MetricTileView(metric: metric)
                                        .padding(12)
                                }
                            }
                        }
                    }
                }
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
    }
}

private struct RunOptionButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ContentCard {
                HStack {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.bodyMD.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
