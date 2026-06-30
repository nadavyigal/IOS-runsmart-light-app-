import SwiftUI

struct ReportTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @State private var runs: [RecordedRun] = []
    @State private var segment: ReportSegment = .runs
    @State private var runReports: [RunReportSummary] = []
    @State private var trainingLoad: TrainingLoadSnapshot = .loading
    @State private var recovery: RecoverySnapshot = .loading
    @State private var garminDeviceName: String?
    @State private var runPendingRemoval: RecordedRun?
    @State private var removalFailed = false
    @State private var refreshDebounceTask: Task<Void, Never>?

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
            async let runsTask = services.recentRuns()
            async let reportsTask = services.latestRunReports(limit: 50)
            async let loadTask = services.trainingLoadSnapshot()
            async let recoveryTask = services.recoverySnapshot()
            async let statusesTask = services.deviceStatuses()
            let (freshRuns, reports, load, rec, statuses) = await (runsTask, reportsTask, loadTask, recoveryTask, statusesTask)
            runs = freshRuns
            runReports = reports
            trainingLoad = load
            recovery = rec
            garminDeviceName = statuses.first { $0.provider == "Garmin Connect" }?.deviceName
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            scheduleDebouncedRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartReportsDidChange)) { _ in
            scheduleDebouncedRefresh()
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


    private func scheduleDebouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            refreshRuns()
            async let reportsTask = services.latestRunReports(limit: 50)
            async let statusesTask = services.deviceStatuses()
            let (reports, statuses) = await (reportsTask, statusesTask)
            runReports = reports
            garminDeviceName = statuses.first { $0.provider == "Garmin Connect" }?.deviceName
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
                            fallbackGarminDeviceName: garminDeviceName,
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

    private func openZoneAnalysis() {
        router.open(.zoneAnalysis)
    }

    private func openReportDetail(_ report: RunReportDetail) {
        router.open(.runReportDetail(report))
    }

    private func openReport(for run: RecordedRun) {
        Task {
            let fallbackDeviceName = garminDeviceName
            let report = await services.runReport(for: run) ?? SupabaseRunSmartServices.reportSkeleton(for: run, fallbackGarminDeviceName: fallbackDeviceName)
            let displayReport = report.withGarminDeviceFallback(for: run, fallbackGarminDeviceName: fallbackDeviceName)
            await MainActor.run {
                openReportDetail(displayReport)
            }
        }
    }

    private func openReportSummary(_ report: RunReportSummary) {
        if let detail = report.toDetail() {
            router.open(.runReportDetail(detail))
        } else {
            router.openCoach(context: .report)
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
