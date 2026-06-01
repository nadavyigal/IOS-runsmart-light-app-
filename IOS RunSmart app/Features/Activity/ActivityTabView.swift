import SwiftUI

struct ReportTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @State private var runs: [RecordedRun] = []
    @State private var segment: ReportSegment = .runs
    @State private var runReports: [RunReportSummary] = []
    @State private var trainingLoad: TrainingLoadSnapshot = .loading
    @State private var recovery: RecoverySnapshot = .loading
    @State private var runPendingRemoval: RecordedRun?
    @State private var removalFailed = false
    @State private var savedRoutes: [SavedRoute] = []
    @State private var benchmarkRoutes: [BenchmarkRoute] = []

    private enum ReportSegment: String, CaseIterable, Hashable, Identifiable {
        case runs = "Runs"
        case reports = "Reports"
        case progress = "Progress"
        var id: String { rawValue }
    }

    private var totalDistanceKm: Double {
        runs.reduce(0) { $0 + $1.distanceMeters / 1_000 }
    }

    private var totalMovingTime: TimeInterval {
        runs.reduce(0) { $0 + $1.movingTimeSeconds }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                RunSmartHeader(title: "Report")

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

                SegmentedPillPicker(values: ReportSegment.allCases, selection: $segment) { $0.rawValue }
                    .runSmartStaggeredAppear(index: 1)

                switch segment {
                case .runs:
                    runsContent
                case .reports:
                    reportsContent
                case .progress:
                    progressContent
                }
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 140)
        }
        .task {
            await reloadRuns()
            await reloadRoutes()
            runReports = await services.latestRunReports(limit: 50)
            trainingLoad = await services.trainingLoadSnapshot()
            recovery = await services.recoverySnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            refreshRunsAndRoutes()
            Task { runReports = await services.latestRunReports(limit: 50) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartReportsDidChange)) { _ in
            refreshRuns()
            Task { runReports = await services.latestRunReports(limit: 50) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRoutesDidChange)) { _ in
            refreshRoutes()
        }
        .confirmationDialog("Remove this run?", isPresented: Binding(
            get: { runPendingRemoval != nil },
            set: { if !$0 { runPendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Run", role: .destructive) {
                guard let run = runPendingRemoval else { return }
                Task { await remove(run) }
            }
            Button("Cancel", role: .cancel) { runPendingRemoval = nil }
        } message: {
            Text("RunSmart/manual runs are deleted from RunSmart. Garmin runs are hidden in RunSmart but stay in Garmin.")
        }
    }

    @ViewBuilder
    private var runsContent: some View {
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
                            onTap: { openReport(for: run) },
                            onDelete: { runPendingRemoval = run }
                        )
                        if run.id != runs.last?.id {
                            Divider().background(Color.border)
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
        .runSmartStaggeredAppear(index: 2)
    }

    @ViewBuilder
    private var reportsContent: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Run Reports", trailing: "\(runReports.count)")
                if runReports.isEmpty {
                    Text("Complete a run and tap Generate to get your first AI coach report.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(runReports) { report in
                        VStack(alignment: .leading, spacing: 6) {
                            Button { openReportSummary(report) } label: {
                                HStack(spacing: 12) {
                                    RunSmartIconMark(size: 32, tint: .accentPrimary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(report.title)
                                            .font(.bodyMD.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                        Text("\(report.dateLabel) · \(report.distance) · \(report.pace)")
                                            .font(.labelSM)
                                            .foregroundStyle(Color.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if report.hasGeneratedReport, report.score > 0 {
                                        Text("\(report.score)")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.black)
                                            .frame(width: 30, height: 30)
                                            .background(Color.accentPrimary, in: Circle())
                                    } else if !report.hasGeneratedReport {
                                        Text("Generate")
                                            .font(.caption2.bold())
                                            .foregroundStyle(Color.accentPrimary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button { router.openCoach(context: .report) } label: {
                                Label("Explain this run ✦", systemImage: "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                            .buttonStyle(.plain)

                            if report.id != runReports.last?.id {
                                Divider().background(Color.border)
                            }
                        }
                    }
                }
            }
        }
        .runSmartStaggeredAppear(index: 2)
    }

    @ViewBuilder
    private var progressContent: some View {
        Button(action: openZoneAnalysis) {
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

        RecoveryInsightPlanCard(recovery: recovery, trainingLoad: trainingLoad)
            .runSmartStaggeredAppear(index: 3)

        RunTrendChartCard(runs: runs)
            .runSmartStaggeredAppear(index: 4)
    }

    private func reloadRuns() async {
        runs = await services.recentRuns()
    }

    private func refreshRuns() {
        Task { await reloadRuns() }
    }

    private func refreshRoutes() {
        Task { await reloadRoutes() }
    }

    private func refreshRunsAndRoutes() {
        Task {
            await reloadRuns()
            await reloadRoutes()
        }
    }

    private func openZoneAnalysis() {
        router.open(.zoneAnalysis)
    }

    private func openReportDetail(_ report: RunReportDetail) {
        router.open(.runReportDetail(report))
    }

    private func openRouteDetail(_ route: SavedRoute) {
        router.open(.routeDetail(route))
    }

    private func openReport(for run: RecordedRun) {
        Task {
            let report = await services.runReport(for: run) ?? SupabaseRunSmartServices.reportSkeleton(for: run)
            await MainActor.run {
                openReportDetail(report)
            }
        }
    }

    private func openReportSummary(_ report: RunReportSummary) {
        if let detail = report.toDetail() {
            router.open(.runReportDetail(detail))
        }
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
                                onTap: { openRouteDetail(route) }
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
                                onTap: { openRouteDetail(route) }
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
