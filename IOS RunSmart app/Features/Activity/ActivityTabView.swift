import SwiftUI

struct ReportTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @State private var runs: [RecordedRun] = []
    @State private var filter = "All"
    @State private var runPendingRemoval: RecordedRun?
    @State private var removalFailed = false
    @State private var savedRoutes: [SavedRoute] = []
    @State private var benchmarkRoutes: [BenchmarkRoute] = []

    private var totalDistanceKm: Double {
        runs.reduce(0) { $0 + $1.distanceMeters / 1_000 }
    }

    private var totalMovingTime: TimeInterval {
        runs.reduce(0) { $0 + $1.movingTimeSeconds }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                RunSmartHeader(title: "Report")

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
                        SectionLabel(title: "Last 14 days")
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
                            ActivityMetricPill(title: "Source", value: "Real", tint: .accentPrimary)
                        }
                    }
                }
                .runSmartStaggeredAppear(index: 0)

                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Running activities", trailing: "\(runs.count)")
                        if runs.isEmpty {
                            Text("No verified runs yet. Start a GPS run, add a manual run, or connect Garmin to import real activity.")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(runs) { run in
                                ActivityRow(
                                    run: run,
                                    onTap: { router.open(.runReportDetail(SupabaseRunSmartServices.reportSkeleton(for: run))) },
                                    onDelete: { runPendingRemoval = run }
                                )
                                if run.id != runs.last?.id {
                                    Divider()
                                        .background(Color.border)
                                }
                            }
                        }

                        if removalFailed {
                            Text("Could not remove that run. Check your connection and try again.")
                                .font(.bodyMD)
                                .foregroundStyle(Color.accentHeart)
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

                routeLibrarySection
                    .runSmartStaggeredAppear(index: 4)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            await reloadRuns()
            await reloadRoutes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            Task {
                await reloadRuns()
                await reloadRoutes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRoutesDidChange)) { _ in
            Task { await reloadRoutes() }
        }
        .confirmationDialog("Remove this run?", isPresented: Binding(
            get: { runPendingRemoval != nil },
            set: { if !$0 { runPendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Run", role: .destructive) {
                guard let run = runPendingRemoval else { return }
                Task { await remove(run) }
            }
            Button("Cancel", role: .cancel) {
                runPendingRemoval = nil
            }
        } message: {
            Text("RunSmart/manual runs are deleted from RunSmart. Garmin runs are hidden in RunSmart but stay in Garmin.")
        }
    }

    private func reloadRuns() async {
        runs = await services.recentRuns()
    }

    private func remove(_ run: RecordedRun) async {
        removalFailed = false
        runPendingRemoval = nil
        let removed = await services.removeRun(run)
        if removed {
            runs.removeAll { existing in
                existing.id == run.id ||
                (existing.providerActivityID != nil && existing.providerActivityID == run.providerActivityID && existing.source == run.source)
            }
            RunSmartHaptics.success()
        } else {
            removalFailed = true
            await reloadRuns()
        }
    }

    private func reloadRoutes() async {
        savedRoutes = await services.savedRoutes()
        benchmarkRoutes = await services.benchmarkRoutes()
    }

    private var benchmarkSavedRoutes: [SavedRoute] {
        let benchmarkIDs = Set(benchmarkRoutes.map(\.savedRouteID))
        return savedRoutes.filter { benchmarkIDs.contains($0.id) }
    }

    private var nonBenchmarkSavedRoutes: [SavedRoute] {
        let benchmarkIDs = Set(benchmarkRoutes.map(\.savedRouteID))
        return savedRoutes.filter { !benchmarkIDs.contains($0.id) }
    }

    private func benchmarkRoute(for route: SavedRoute) -> BenchmarkRoute? {
        benchmarkRoutes.first { $0.savedRouteID == route.id }
    }

    @ViewBuilder
    private var routeLibrarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !benchmarkSavedRoutes.isEmpty {
                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Benchmark routes", trailing: "\(benchmarkSavedRoutes.count)")
                        ForEach(benchmarkSavedRoutes) { route in
                            RouteCardView(
                                route: route,
                                isBenchmark: true,
                                benchmarkRoute: benchmarkRoute(for: route),
                                onTap: { router.open(.routeDetail(route)) }
                            )
                        }
                    }
                }
            } else {
                RouteEmptyStateView(
                    title: "No benchmark routes yet",
                    message: "Mark a saved route as a benchmark to track your progress over repeated runs.",
                    symbol: "flag.checkered"
                )
            }

            if !nonBenchmarkSavedRoutes.isEmpty {
                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Saved routes", trailing: "\(nonBenchmarkSavedRoutes.count)")
                        ForEach(nonBenchmarkSavedRoutes) { route in
                            RouteCardView(
                                route: route,
                                isBenchmark: false,
                                benchmarkRoute: nil,
                                onTap: { router.open(.routeDetail(route)) }
                            )
                        }
                    }
                }
            } else if savedRoutes.isEmpty {
                RouteEmptyStateView(
                    title: "No saved routes",
                    message: "Record a GPS run or review a Garmin activity to save your first route.",
                    symbol: "map"
                )
            }
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
