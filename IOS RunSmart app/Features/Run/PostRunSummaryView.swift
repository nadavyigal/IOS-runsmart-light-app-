import SwiftUI

enum PostRunSuggestedWorkoutSaveCopy {
    static let failureMessage = "Your run report is saved. Could not add the suggested workout to your plan; try again later."
    static let reviewMessage = "Your run report is saved. This suggestion needs a distance before RunSmart can add it to your plan."
}

struct PostRunSummaryView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    var run: RecordedRun?
    var outcome: PostActivityOutcome? = nil
    var isProcessing: Bool = false
    var onSave: () -> Void
    var onDelete: () -> Void

    @State private var rpe = 6
    @State private var showDeleteConfirmation = false
    @State private var showSaveRouteSheet = false
    @State private var achievementContext: AchievementContext?
    @State private var showAchievementMoment = false
    @State private var noticeContext: NoticeContextKind?

    var body: some View {
        ZStack {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HeroCard(accent: .accentSuccess) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionLabel(title: isShortActivity ? "Activity Saved" : "Run Saved")
                            Spacer()
                            StatusChip(text: heroStatusText, tint: heroStatusTint)
                        }

                        Text(distanceLabel)
                            .font(.displayXL)
                            .monospacedDigit()
                            .displayTightTracking()

                        HStack(spacing: 8) {
                            PostRunStatPill(title: "Time", value: timeLabel, tint: .accentPrimary)
                            PostRunStatPill(title: "Pace", value: paceLabel, tint: .accentEnergy)
                            PostRunStatPill(title: "Route", value: routeLabel, tint: .accentRecovery)
                        }

                        RouteMapView(points: run?.routePoints ?? [], title: "Completed route")
                            .frame(height: 142)
                    }
                }

                RPESelector(value: $rpe)

                if isShortActivity {
                    ShortActivityNotice()
                }

                if let noticeContext {
                    NoticedMomentCard(context: noticeContext)
                }

                CoachAnalysisCard(run: run, rpe: rpe, isShortActivity: isShortActivity)
                Button {
                    onSave()
                    router.selectedTab = .report
                } label: {
                    Label("View Report", systemImage: "chart.xyaxis.line")
                        .font(.buttonLabel)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                if let report = outcome?.report {
                    ProgressShareCard(payload: .runReport(report))
                    ProgressShareButton(payload: .runReport(report))
                } else if let run {
                    ProgressShareCard(payload: fallbackSharePayload(for: run))
                    ProgressShareButton(payload: fallbackSharePayload(for: run))
                }
                PostRunLearningCard(
                    run: run,
                    outcome: outcome,
                    report: outcome?.report,
                    isProcessing: isProcessing,
                    debrief: outcome?.debrief        // E6: AI debrief from processCompletedActivity
                )
                PostActivityPlanCard(outcome: outcome, isProcessing: isProcessing, isShortActivity: isShortActivity)
                BenchmarkComparisonLoaderView(run: outcome?.canonicalRun ?? run)
                SplitPreviewCard(splits: splitRows)
                RecoveryPlanCard()

                if let run, run.routePoints.count >= RouteMatchingService.minimumRoutePoints {
                    Button {
                        showSaveRouteSheet = true
                    } label: {
                        Label("Save Route", systemImage: "map.fill")
                            .font(.buttonLabel)
                            .foregroundStyle(Color.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Save the route from this run to your route library.")
                }

                HStack(spacing: 10) {
                    Button(action: onSave) {
                        Label("Keep Activity", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(NeonButtonStyle())

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.buttonLabel)
                            .foregroundStyle(Color.accentHeart)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentHeart.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(Color.accentHeart.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.52).ignoresSafeArea())

            if showAchievementMoment, let achievementContext {
                AchievementMomentView(
                    context: achievementContext,
                    recordContext: achievementRecordContext(for: achievementContext)
                ) {
                    showAchievementMoment = false
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .task(id: run?.id) {
            await loadAhaMoments()
        }
        .confirmationDialog("Delete this activity?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Activity", role: .destructive, action: onDelete)
            Button("Keep Activity", role: .cancel) {}
        } message: {
            Text("This removes the run from RunSmart. It will not delete anything from Garmin.")
        }
        .sheet(isPresented: $showSaveRouteSheet) {
            if let run {
                SaveRouteSheet(run: run)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private var distanceLabel: String {
        guard let run else { return "-- km" }
        return String(format: "%.2f km", run.distanceMeters / 1_000)
    }

    private var timeLabel: String {
        guard let run else { return "--" }
        return RunRecorder.timeLabel(run.movingTimeSeconds)
    }

    private var paceLabel: String {
        guard let run else { return "--" }
        return RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)
    }

    private var routeLabel: String {
        guard let run else { return "--" }
        return run.routePoints.isEmpty ? "No map" : "\(run.routePoints.count) pts"
    }

    private var isShortActivity: Bool {
        guard let run else { return false }
        return run.distanceMeters < 100 || run.movingTimeSeconds < 60
    }

    private var heroStatusText: String {
        if run == nil { return "Draft" }
        return isShortActivity ? "Review" : "GPS"
    }

    private var heroStatusTint: Color {
        isShortActivity ? .accentEnergy : .accentPrimary
    }

    private var splitRows: [SplitRow] {
        guard let run else { return [] }
        return RunRecorder.kilometerSplits(from: run.routePoints).map { split in
            SplitRow(km: split.km, pace: RunRecorder.paceLabel(secondsPerKm: split.paceSecondsPerKm))
        }
    }

    private func loadAhaMoments() async {
        guard let run else { return }
        guard !isShortActivity else {
            achievementContext = nil
            showAchievementMoment = false
            noticeContext = nil
            return
        }
        let recentRuns = await services.recentRuns()
        let priorRuns = recentRuns.filter { $0.id != run.id }

        if let achievement = AchievementDetector.detect(currentRun: run, priorRuns: priorRuns) {
            let contextKey = achievementRecordContext(for: achievement)
            let alreadyFired = await AhaMomentStore.shared.hasFired(momentId: "achievement", context: contextKey)
            if !alreadyFired {
                achievementContext = achievement
                showAchievementMoment = true
            }
        }

        let onCooldown = await AhaMomentStore.shared.isNoticedOnCooldown()
        if let candidate = ContextDetector.detect(
            currentRun: run,
            allRuns: recentRuns.contains(where: { $0.id == run.id }) ? recentRuns : priorRuns + [run],
            noticedOnCooldown: onCooldown
        ) {
            let fired = await AhaMomentStore.shared.hasFired(momentId: "noticed", context: candidate.contextKey)
            if !fired {
                noticeContext = candidate
                await AhaMomentStore.shared.record(
                    momentId: "noticed",
                    context: candidate.contextKey,
                    variant: "C"
                )
            }
        }
    }

    private func achievementRecordContext(for context: AchievementContext) -> String {
        switch context {
        case .firstRun:
            return "first_run"
        case .showedUp:
            return "showed_up"
        case .personalBest(let distanceKm, _):
            return String(format: "pb_%.2f", locale: Locale(identifier: "en_US_POSIX"), distanceKm)
        }
    }

    private func fallbackSharePayload(for run: RecordedRun) -> ProgressSharePayload {
        ProgressSharePayload(
            kind: .runReport,
            title: "Run saved",
            subtitle: run.startedAt.formatted(date: .abbreviated, time: .omitted),
            metrics: [
                ProgressShareMetric(title: "Distance", value: distanceLabel),
                ProgressShareMetric(title: "Time", value: timeLabel),
                ProgressShareMetric(title: "Avg Pace", value: paceLabel)
            ],
            insight: "RunSmart saved this activity for private progress tracking.",
            privacyNote: "Private share: no map, GPS points, or exact route are included."
        )
    }
}

private struct ShortActivityNotice: View {
    var body: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14, accent: .accentEnergy) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(Color.accentEnergy)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Short activity saved")
                        .font(.bodyMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("This looks too short for meaningful training analysis. Keep it for your history, or delete it if it was a test or accidental stop.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PostActivityPlanCard: View {
    @Environment(\.runSmartServices) private var services
    var outcome: PostActivityOutcome?
    var isProcessing: Bool
    var isShortActivity = false

    @State private var isSavingSuggestedWorkout = false
    @State private var saveState: SaveState = .idle

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("PLAN UPDATE", systemImage: "calendar.badge.checkmark")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    StatusChip(text: statusText, tint: statusTint)
                }

                if isProcessing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.accentPrimary)
                        Text("Building your report and matching this run to your plan...")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    Text(planFitText)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let report = outcome?.report {
                    PostRunDetailLine(label: "Coach Report", value: report.notes.summary)

                    if let next = report.structuredNextWorkout {
                        let needsReview = TrainingPlanRepository.suggestedWorkoutNeedsReview(next)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recommended Next Run")
                                .font(.bodyMD.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            PostRunDetailLine(label: "Workout", value: next.title)
                            if let date = next.dateLabel { PostRunDetailLine(label: "Date", value: date) }
                            if let distance = next.distance { PostRunDetailLine(label: "Distance", value: distance) }
                            if let target = next.target { PostRunDetailLine(label: "Target", value: target) }
                            if let notes = next.notes { PostRunDetailLine(label: "Notes", value: notes) }

                            Button {
                                Task { await save(next, report: report) }
                            } label: {
                                Label(needsReview ? "Review Needed" : saveState.buttonTitle(isSaving: isSavingSuggestedWorkout), systemImage: needsReview ? "exclamationmark.triangle.fill" : saveState.symbol)
                                    .font(.buttonLabel)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .foregroundStyle(needsReview ? Color.textSecondary : Color.black)
                                    .background(needsReview ? Color.surfaceCard : Color.accentPrimary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(needsReview || isSavingSuggestedWorkout || saveState == .saved)

                            if needsReview {
                                Text(PostRunSuggestedWorkoutSaveCopy.reviewMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentEnergy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if saveState == .failed {
                                Text(saveFailureMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentHeart)
                            }
                        }
                    } else {
                        PostRunDetailLine(label: "Next Run", value: report.notes.nextSessionNudge)
                    }
                }
            }
        }
    }

    private var statusText: String {
        if isProcessing { return "Updating" }
        if isShortActivity { return "Review" }
        if outcome?.didCompletePlannedWorkout == true { return "Plan Complete" }
        if outcome?.report != nil { return "Reported" }
        return "Saved"
    }

    private var statusTint: Color {
        if isShortActivity { return .accentEnergy }
        return outcome?.didCompletePlannedWorkout == true ? Color.accentSuccess : Color.accentPrimary
    }

    private var planFitText: String {
        if isShortActivity {
            return "This short activity is saved for history, but RunSmart will avoid using it as a meaningful training signal unless you keep it intentionally."
        }
        guard let outcome else {
            return "RunSmart will use this activity to update recent load, report context, and the next recommendation."
        }
        if let workout = outcome.completedWorkout {
            return "Matched to \(workout.title) on your training plan and marked complete. Future suggested workouts still wait for your approval."
        }
        return "No scheduled workout was close enough to mark complete, so this stays as an extra run in your training history."
    }

    private var saveFailureMessage: String {
        PostRunSuggestedWorkoutSaveCopy.failureMessage
    }

    private func save(_ next: StructuredNextWorkout, report: RunReportDetail) async {
        isSavingSuggestedWorkout = true
        saveState = .idle
        let saved = await services.saveSuggestedWorkout(next, from: report)
        isSavingSuggestedWorkout = false
        saveState = saved ? .saved : .failed
        if saved { RunSmartHaptics.success() }
    }

    private enum SaveState {
        case idle
        case saved
        case failed

        var symbol: String {
            switch self {
            case .idle: "calendar.badge.plus"
            case .saved: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

        func buttonTitle(isSaving: Bool) -> String {
            if isSaving { return "Saving..." }
            switch self {
            case .idle: return "Save to Training Plan"
            case .saved: return "Saved to Plan"
            case .failed: return "Try Saving Again"
            }
        }
    }
}

private struct PostRunDetailLine: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.labelSM)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PostRunStatPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.labelSM)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.metricXS)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.surfaceCard.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

private struct CoachAnalysisCard: View {
    var run: RecordedRun?
    var rpe: Int
    var isShortActivity = false

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("COACH ANALYSIS", systemImage: "sparkles")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    StatusChip(text: effortLabel, tint: effortTint)
                }

                Text(headline)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(3)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    CoachInsightTile(title: "Training Benefit", text: benefitText, symbol: "sparkles", tint: .accentPrimary)
                    CoachInsightTile(title: "Plan Fit", text: planFitText, symbol: "target", tint: .accentRecovery)
                    CoachInsightTile(title: "Recovery", text: recoveryText, symbol: "heart", tint: .accentRecovery)
                    CoachInsightTile(title: "Pacing", text: paceText, symbol: "waveform.path.ecg", tint: .accentEnergy)
                }

                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.accentPrimary)
                        .frame(width: 3)
                    Text(loadText)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(minHeight: 46)

                Text("AI - GPS - RunSmart")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var effortLabel: String {
        if isShortActivity { return "Review" }
        switch rpe {
        case 1...4: return "Easy"
        case 5...7: return "Steady"
        default: return "Hard"
        }
    }

    private var effortTint: Color {
        if isShortActivity { return .accentEnergy }
        switch rpe {
        case 1...4: return .accentPrimary
        case 5...7: return .accentEnergy
        default: return .accentHeart
        }
    }

    private var headline: String {
        guard let run else { return "No run data was available for analysis." }
        if isShortActivity {
            return "This activity was saved, but it is too short for a reliable run analysis."
        }
        let km = run.distanceMeters / 1_000
        return String(format: "You completed %.2f km at %@ /km average pace.", km, RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm))
    }

    private var benefitText: String {
        if isShortActivity { return "Training benefit is not calculated for this short activity." }
        return rpe <= 6 ? "This supports aerobic consistency without adding unnecessary strain." : "This was a stronger effort. Keep the next run controlled."
    }

    private var planFitText: String {
        if isShortActivity { return "Saved for history, but not treated like a full plan signal." }
        return "This GPS run updates your recent load and helps the next plan decision."
    }

    private var recoveryText: String {
        if isShortActivity { return "No recovery adjustment needed unless this was part of a longer effort." }
        return rpe >= 7 ? "Hydrate, refuel, and keep the next 24h lighter." : "Rehydrate and refuel. Easy movement later is enough."
    }

    private var paceText: String {
        guard let run, run.averagePaceSecondsPerKm > 0 else { return "Pace trend appears after more GPS distance." }
        return "Average pace: \(RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)) /km."
    }

    private var loadText: String {
        guard let run else { return "Save or delete this activity before leaving the summary." }
        if isShortActivity {
            return "Keep this only if you want it in your history. RunSmart will avoid treating it like a full training run."
        }
        return String(format: "%.1f km at %@ effort contributes to your weekly load.", run.distanceMeters / 1_000, effortLabel.lowercased())
    }
}

private struct CoachInsightTile: View {
    var title: String
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.labelSM)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Color.surfaceCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

private struct SplitPreviewCard: View {
    var splits: [SplitRow]

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("KM SPLITS", systemImage: "speedometer")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    Text("\(splits.count) splits")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)

                if splits.isEmpty {
                    Text("Splits appear once you complete 1 km of GPS distance.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else {
                    ForEach(splits) { split in
                        HStack {
                            Text("\(split.km)")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 28, alignment: .leading)
                            Text(split.pace)
                                .font(.metricSM)
                                .monospacedDigit()
                            Spacer()
                            Text("km \(split.km)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}

private struct RecoveryPlanCard: View {
    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentRecovery) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.accentPrimary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "Recovery Plan")
                    Text("Now: rehydrate and refuel with a light snack.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }
}

private struct SplitRow: Identifiable {
    var id: Int { km }
    var km: Int
    var pace: String
}
