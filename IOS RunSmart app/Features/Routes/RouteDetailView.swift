import SwiftUI

struct RouteDetailScaffold: View {
    @Environment(\.runSmartServices) private var services
    var route: SavedRoute

    @State private var benchmarkRoute: BenchmarkRoute?
    @State private var isTogglingBenchmark = false
    @State private var isTogglingFavorite = false
    @State private var currentRoute: SavedRoute

    init(route: SavedRoute) {
        self.route = route
        _currentRoute = State(initialValue: route)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(padding: 8, glow: Color.lime) {
                RouteMapView(points: currentRoute.points, title: currentRoute.name)
                    .frame(height: 220)
            }

            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Route Info")
                    Text(currentRoute.name)
                        .font(.title2.bold())

                    HStack(spacing: 14) {
                        routeMetric(label: "Distance", value: String(format: "%.1f km", currentRoute.distanceKm))
                        routeMetric(label: "Elevation", value: "\(currentRoute.elevationGainMeters) m")
                        routeMetric(label: "Source", value: currentRoute.source.displayLabel)
                    }

                    if !currentRoute.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(currentRoute.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.lime)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.lime.opacity(0.1))
                                    .clipShape(Capsule(style: .continuous))
                            }
                        }
                    }

                    if !currentRoute.notes.isEmpty {
                        Text(currentRoute.notes)
                            .font(.callout)
                            .foregroundStyle(Color.mutedText)
                    }
                }
            }

            if let benchmark = benchmarkRoute {
                benchmarkCard(benchmark)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Actions")

                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: currentRoute.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(currentRoute.isFavorite ? .pink : Color.mutedText)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(currentRoute.isFavorite ? "Unfavorite" : "Favorite")
                                    .font(.headline)
                                Text(currentRoute.isFavorite ? "Remove from favorites." : "Mark as a favorite route.")
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedText)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingFavorite)

                    Button {
                        Task { await toggleBenchmark() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: benchmarkRoute != nil ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis")
                                .foregroundStyle(benchmarkRoute != nil ? Color.lime : Color.mutedText)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(benchmarkRoute != nil ? "Remove Benchmark" : "Make Benchmark")
                                    .font(.headline)
                                Text(benchmarkRoute != nil ? "Stop tracking progress on this route." : "Track your progress each time you run this route.")
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedText)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingBenchmark)
                }
            }

            Text("Created \(currentRoute.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(Color.mutedText)
                .padding(.horizontal, 4)
        }
        .task {
            let benchmarks = await services.benchmarkRoutes()
            benchmarkRoute = benchmarks.first(where: { $0.savedRouteID == currentRoute.id })
        }
    }

    private func routeMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mutedText)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func benchmarkCard(_ benchmark: BenchmarkRoute) -> some View {
        GlassCard(glow: Color.lime) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Benchmark Stats")
                if benchmark.historicalRunCount > 0 {
                    HStack(spacing: 14) {
                        routeMetric(label: "Runs", value: "\(benchmark.historicalRunCount)")
                        if let pb = benchmark.personalBestSeconds {
                            routeMetric(label: "Personal Best", value: formatDuration(pb))
                        }
                        if let avgPace = benchmark.averagePaceSecondsPerKm {
                            routeMetric(label: "Avg Pace", value: formatPace(avgPace))
                        }
                    }
                    if let avgDuration = benchmark.averageDurationSeconds {
                        routeMetric(label: "Avg Duration", value: formatDuration(avgDuration))
                    }
                } else {
                    Text("Run this route to start tracking your benchmark progress.")
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
    }

    private func toggleFavorite() async {
        isTogglingFavorite = true
        defer { isTogglingFavorite = false }
        var updated = currentRoute
        updated.isFavorite.toggle()
        let saved = await services.updateRoute(updated)
        if saved { currentRoute = updated }
    }

    private func toggleBenchmark() async {
        isTogglingBenchmark = true
        defer { isTogglingBenchmark = false }
        if benchmarkRoute != nil {
            let removed = await services.disableBenchmark(for: currentRoute.id)
            if removed { benchmarkRoute = nil }
        } else {
            let enabled = await services.enableBenchmark(for: currentRoute.id)
            if enabled {
                let benchmarks = await services.benchmarkRoutes()
                benchmarkRoute = benchmarks.first(where: { $0.savedRouteID == currentRoute.id })
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func formatPace(_ secondsPerKm: Int) -> String {
        String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
    }
}

private extension RouteSource {
    var displayLabel: String {
        switch self {
        case .recorded: "Recorded"
        case .garmin: "Garmin"
        case .generated: "Generated"
        case .manual: "Manual"
        }
    }
}

#if DEBUG
#Preview("Route Detail") {
    ZStack {
        RunSmartBackground()
        ScrollView {
            RouteDetailScaffold(route: RunSmartPreviewData.savedRoutes[0])
                .padding(20)
        }
    }
    .preferredColorScheme(.dark)
    .environment(\.runSmartServices, MockRunSmartServices())
}
#endif
