import SwiftUI

struct RouteCardView: View {
    var route: SavedRoute
    var isBenchmark: Bool
    var benchmarkRoute: BenchmarkRoute?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                RouteMapView(points: route.points, title: route.name)
                    .frame(height: 120)
                    .clipped()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(route.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        chips
                    }

                    HStack(spacing: 14) {
                        Label(String(format: "%.1f km", route.distanceKm), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        Label("\(route.elevationGainMeters) m", systemImage: "arrow.up.right")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)

                    if let benchmark = benchmarkRoute, benchmark.historicalRunCount > 0 {
                        HStack(spacing: 12) {
                            miniStat(label: "Runs", value: "\(benchmark.historicalRunCount)")
                            if let pb = benchmark.personalBestSeconds {
                                miniStat(label: "PB", value: formatDuration(pb))
                            }
                            if let avgPace = benchmark.averagePaceSecondsPerKm {
                                miniStat(label: "Avg Pace", value: formatPace(avgPace))
                            }
                        }
                        .font(.caption2)
                    }
                }
                .padding(12)
            }
            .background(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var chips: some View {
        HStack(spacing: 6) {
            if route.isFavorite {
                chipLabel(text: "Favorite", symbol: "heart.fill", tint: .pink)
            }
            if isBenchmark {
                chipLabel(text: "Benchmark", symbol: "chart.line.uptrend.xyaxis", tint: Color.lime)
            }
        }
    }

    private func chipLabel(text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule(style: .continuous))
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .foregroundStyle(Color.mutedText)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func formatPace(_ secondsPerKm: Int) -> String {
        String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }

    private var accessibilityDescription: String {
        var parts = [route.name, String(format: "%.1f kilometers", route.distanceKm), "\(route.elevationGainMeters) meters elevation"]
        if route.isFavorite { parts.append("Favorite") }
        if isBenchmark { parts.append("Benchmark route") }
        return parts.joined(separator: ", ")
    }
}

struct RouteEmptyStateView: View {
    var title: String
    var message: String
    var symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(Color.mutedText)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Route Card") {
    ZStack {
        RunSmartBackground()
        ScrollView {
            VStack(spacing: 16) {
                RouteCardView(
                    route: RunSmartPreviewData.savedRoutes[0],
                    isBenchmark: true,
                    benchmarkRoute: RunSmartPreviewData.benchmarkRoutes[0],
                    onTap: {}
                )
                RouteCardView(
                    route: RunSmartPreviewData.savedRoutes[1],
                    isBenchmark: false,
                    benchmarkRoute: nil,
                    onTap: {}
                )
                RouteCardView(
                    route: RunSmartPreviewData.savedRoutes[2],
                    isBenchmark: false,
                    benchmarkRoute: nil,
                    onTap: {}
                )
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    ZStack {
        RunSmartBackground()
        GlassCard {
            RouteEmptyStateView(
                title: "No Saved Routes",
                message: "Record a GPS run or import from Garmin to save your first route.",
                symbol: "map"
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
