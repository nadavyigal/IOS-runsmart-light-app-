import SwiftUI

enum PostRunSuggestedWorkoutSaveCopy {
    static let failureMessage = "Your run report is saved. Could not add the suggested workout to your plan; try again later."
    static let reviewMessage = "Your run report is saved. This suggestion needs a distance before RunSmart can add it to your plan."
}

/// Bar heights for the per-km pace chart. Pure so it can be tested.
enum SplitPaceChart {
    static let slowestFraction = 0.35
    static let uniformFraction = 0.8

    /// Faster pace (fewer seconds per km) gives a taller bar, from `slowestFraction` for the slowest
    /// split up to 1 for the fastest. Equal paces all get `uniformFraction`. A pace that is not a
    /// positive number gets 0 and is left out of the range.
    static func barFractions(paces: [Double]) -> [Double] {
        let valid = paces.filter { $0.isFinite && $0 > 0 }
        guard let fastest = valid.min(), let slowest = valid.max() else {
            return paces.map { _ in 0 }
        }
        return paces.map { pace in
            guard pace.isFinite, pace > 0 else { return 0 }
            if slowest - fastest < 0.5 { return uniformFraction }
            let t = (slowest - pace) / (slowest - fastest)
            return slowestFraction + (1 - slowestFraction) * t
        }
    }
}

struct PostRunSummaryView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession
    @ObservedObject private var strava = StravaConnectionService.shared
    @ObservedObject private var stravaUploads = StravaUploadCoordinator.shared
    var run: RecordedRun?
    var outcome: PostActivityOutcome? = nil
    var isProcessing: Bool = false
    var onSave: () -> Void
    var onDelete: () -> Void

    private enum EditField: Hashable {
        case title
        case notes
    }

    @State private var rpe: Int?
    @State private var ratedRun: RecordedRun?
    @State private var showDeleteConfirmation = false
    @State private var showSaveRouteSheet = false
    @State private var showFullMap = false
    @State private var achievementContext: AchievementContext?
    @State private var showAchievementMoment = false
    @State private var noticeContext: NoticeContextKind?
    @State private var titleText = ""
    @State private var notesText = ""
    @FocusState private var focusedField: EditField?

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard

                    RPESelector(value: $rpe)

                    if displayRun != nil {
                        notesCard
                    }

                    if isShortActivity {
                        ShortActivityNotice()
                    }

                    if let noticeContext {
                        NoticedMomentCard(context: noticeContext)
                    }

                    coachSection
                    SplitPreviewCard(splits: splitRows)
                    BenchmarkComparisonLoaderView(run: outcome?.canonicalRun ?? run)
                    stravaStatusLine
                    shareSection
                    actionButtons
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
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
            ratedRun = outcome?.canonicalRun ?? run
            rpe = ratedRun?.rpe
            if let seeded = ratedRun {
                titleText = RunTitle.displayTitle(for: seeded)
                notesText = seeded.notes ?? ""
            }
            await loadAhaMoments()
        }
        .onChange(of: rpe) { _, newValue in
            Task { await persistRPE(newValue) }
        }
        .onChange(of: focusedField) { oldValue, _ in
            if oldValue != nil {
                Task { await persistDetails() }
            }
        }
        // WP-38 S11: source-neutral delete copy (old Garmin wording preserved in
        // tasks/garmin-deferred-copy-restore.md for when Garmin reconnects).
        // Prefer .alert over confirmationDialog so Cancel stays visible on iOS 26
        // (same WP-37 S4 lesson as Finish/Discard).
        .alert("Delete this run?", isPresented: $showDeleteConfirmation) {
            Button("Delete Run", role: .destructive, action: onDelete)
            Button("Keep Run", role: .cancel) {}
        } message: {
            Text("This removes the run from your RunSmart history.")
        }
        .sheet(isPresented: $showSaveRouteSheet) {
            if let run {
                SaveRouteSheet(run: run)
                    .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            PostRunFullMapView(points: displayRun?.routePoints ?? [])
                .preferredColorScheme(.dark)
        }
    }

    // MARK: Sections

    private var heroCard: some View {
        HeroCard(accent: .accentSuccess) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    SectionLabel(title: isShortActivity ? "Activity saved" : "Run saved")
                    if let chipText = heroStatusText {
                        StatusChip(text: chipText, tint: .accentEnergy)
                    }
                    overflowMenu
                }

                if let current = displayRun {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("Run title", text: $titleText)
                                .font(.headingMD)
                                .foregroundStyle(Color.textPrimary)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .focused($focusedField, equals: .title)
                                .onSubmit { focusedField = nil }
                                .accessibilityLabel("Run title")
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                                .accessibilityHidden(true)
                        }
                        Text(current.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Text(distanceLabel)
                    .font(.displayXL)
                    .monospacedDigit()
                    .displayTightTracking()

                if !heroStats.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(heroStats, id: \.title) { stat in
                            PostRunStatPill(title: stat.title, value: stat.value, tint: stat.tint)
                                .accessibilityLabel(stat.accessibilityLabel)
                        }
                    }
                }

                routeMap
            }
        }
    }

    private var overflowMenu: some View {
        Menu {
            if canSaveRoute {
                Button {
                    showSaveRouteSheet = true
                } label: {
                    Label("Save route", systemImage: "map")
                }
            }
            stravaMenuItem
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete run", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions")
        .accessibilityHint("Save route, send to Strava, or delete this run.")
    }

    // MARK: Strava

    /// Strava UI exists only when the build has a client id and the runner is signed in.
    private var showsStrava: Bool {
        strava.availability(isSignedIn: session.isAuthenticated) == .available && strava.isConnected
    }

    private var stravaStatus: StravaUploadStatus {
        guard let current = displayRun ?? run else { return .notEligible }
        return stravaUploads.status(for: current)
    }

    @ViewBuilder
    private var stravaMenuItem: some View {
        if showsStrava, let current = displayRun ?? run {
            switch stravaStatus {
            case .ready, .failed:
                Button {
                    Task { await stravaUploads.upload(current) }
                } label: {
                    Label("Send to Strava", systemImage: "arrow.up.right.circle")
                }
            case .sending:
                Button {} label: { Label("Sending to Strava...", systemImage: "arrow.up.right.circle") }
                    .disabled(true)
            case .onStrava:
                Button {} label: { Label("On Strava", systemImage: "checkmark.circle") }
                    .disabled(true)
            case .notEligible:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var stravaStatusLine: some View {
        if showsStrava, let line = stravaStatus.statusLine, let current = displayRun ?? run {
            HStack(spacing: 8) {
                switch stravaStatus {
                case .sending:
                    ProgressView().controlSize(.small)
                case .onStrava:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentSuccess)
                default:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.accentEnergy)
                }
                Text(line)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if stravaStatus == .failed {
                    Button("Retry") { Task { await stravaUploads.upload(current) } }
                        .font(.buttonLabel)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var routeMap: some View {
        let points = displayRun?.routePoints ?? []
        let canExpand = points.count >= 2
        return RouteMapView(points: points, title: "Completed route")
            .frame(height: 220)
            .overlay(alignment: .topTrailing) {
                if canExpand {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if canExpand {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showFullMap = true }
                        .accessibilityElement()
                        .accessibilityLabel("Route map")
                        .accessibilityHint("Opens the route map full screen.")
                        .accessibilityAddTraits(.isButton)
                }
            }
    }

    private var notesCard: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                TextField("How did it feel? Add a note.", text: $notesText, axis: .vertical)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2...6)
                    .focused($focusedField, equals: .notes)
                    .accessibilityLabel("Run notes")
                if StravaCopy.showsNotesHint(
                    stravaAvailable: showsStrava,
                    autoUploadEnabled: stravaUploads.autoUploadEnabled
                ) {
                    Text(StravaCopy.notesHint)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var coachSection: some View {
        if hasPlanUpdate {
            PostRunLearningCard(
                run: run,
                outcome: outcome,
                report: outcome?.report,
                isProcessing: isProcessing,
                debrief: outcome?.debrief,        // E6: AI debrief from processCompletedActivity
                title: "COACH",
                showsSaveAction: false
            ) {
                PostActivityPlanCard(outcome: outcome, isShortActivity: isShortActivity, hasDebrief: outcome?.debrief != nil)
            }
        } else {
            PostRunLearningCard(
                run: run,
                outcome: outcome,
                report: outcome?.report,
                isProcessing: isProcessing,
                debrief: outcome?.debrief,
                title: "COACH"
            )
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        if let report = outcome?.report {
            RunShareSection(payload: .runReport(report), routePoints: displayRun?.routePoints ?? [], run: displayRun)
        } else if let run {
            RunShareSection(payload: fallbackSharePayload(for: run), routePoints: displayRun?.routePoints ?? run.routePoints, run: displayRun ?? run)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 6) {
            Button {
                Task { await leave(openingReport: false) }
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(NeonButtonStyle())
            .accessibilityHint("Returns to the Run tab.")

            Button {
                Task { await leave(openingReport: true) }
            } label: {
                Text("View full report")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Report tab.")
        }
    }

    // MARK: Derived values

    private struct HeroStat {
        var title: String
        var value: String
        var tint: Color
        var accessibilityLabel: String
    }

    private var heroStats: [HeroStat] {
        guard let current = displayRun else { return [] }
        var stats = [
            HeroStat(
                title: "Moving time",
                value: timeLabel,
                tint: .accentPrimary,
                accessibilityLabel: "Moving time, \(timeLabel)"
            )
        ]
        // WP-44 S3: "Avg Pace", not "Pace" - the live HUD shows current pace.
        if paceLabel != "--" {
            stats.append(HeroStat(title: "Avg pace", value: paceLabel, tint: .accentEnergy, accessibilityLabel: "Average pace, \(paceLabel) per kilometer"))
        }
        if let gain = RunRecorder.elevationGainMeters(from: current.routePoints) {
            let meters = Int(gain.rounded())
            stats.append(HeroStat(title: "Elev gain", value: "\(meters) m", tint: .accentRecovery, accessibilityLabel: "Elevation gain, \(meters) meters"))
        }
        if let energy = current.estimatedActiveKilocalories, energy.isFinite, energy > 0 {
            let kcal = Int(energy.rounded())
            stats.append(HeroStat(title: "Calories (est.)", value: "\(kcal) kcal", tint: .accentEnergy, accessibilityLabel: "Estimated active calories, \(kcal) kilocalories"))
        }
        return stats
    }

    private var distanceLabel: String {
        guard let run = displayRun else { return "-- km" }
        return String(format: "%.2f km", run.distanceMeters / 1_000)
    }

    private var timeLabel: String {
        guard let run = displayRun else { return "--" }
        return RunRecorder.timeLabel(run.movingTimeSeconds)
    }

    private var paceLabel: String {
        guard let run = displayRun else { return "--" }
        return RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)
    }

    private var isShortActivity: Bool {
        guard let run = displayRun else { return false }
        return run.distanceMeters < 100 || run.movingTimeSeconds < 60
    }

    private var heroStatusText: String? {
        if run == nil { return "Draft" }
        return isShortActivity ? "Review" : nil
    }

    private var canSaveRoute: Bool {
        guard let run else { return false }
        return run.routePoints.count >= RouteMatchingService.minimumRoutePoints
    }

    /// The plan section is worth showing when there is a plan match, a short-activity note or a suggested next run.
    private var hasPlanUpdate: Bool {
        PostActivityPlanCard.planFitText(outcome: outcome, isShortActivity: isShortActivity) != nil || outcome?.report != nil
    }

    private var splitRows: [SplitRow] {
        guard let run = displayRun else { return [] }
        return RunRecorder.kilometerSplits(from: run.routePoints).map { split in
            SplitRow(
                km: split.km,
                pace: RunRecorder.paceLabel(secondsPerKm: split.paceSecondsPerKm),
                paceSeconds: split.paceSecondsPerKm,
                partialDistanceLabel: split.isPartial ? String(format: "%.2f km", split.distanceMeters / 1_000) : nil
            )
        }
    }

    private var displayRun: RecordedRun? {
        ratedRun ?? outcome?.canonicalRun ?? run
    }

    // MARK: Actions

    private func persistRPE(_ value: Int?) async {
        guard let run = displayRun else { return }
        let updated = await services.updateRunRPE(run, rpe: value)
        await MainActor.run {
            ratedRun = updated
        }
    }

    /// Saves the title and notes when they changed. The run itself is already saved at Finish.
    private func persistDetails() async {
        guard let current = displayRun else { return }
        let newTitle = RunTitle.updatedTitle(input: titleText, for: current)
        let newNotes = RunTitle.updatedNotes(input: notesText)
        guard newTitle != current.title || newNotes != current.notes else { return }
        let updated = await services.updateRunDetails(current, title: newTitle, notes: newNotes)
        await MainActor.run {
            ratedRun = updated
            if focusedField != .title {
                titleText = RunTitle.displayTitle(for: updated)
            }
        }
        // A run that is already on Strava gets the new title and notes there too. Best effort.
        await stravaUploads.syncDetailsIfOnStrava(updated)
    }

    private func leave(openingReport: Bool) async {
        focusedField = nil
        await persistDetails()
        await MainActor.run {
            onSave()
            if openingReport {
                router.selectedTab = .report
            }
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
                ProgressShareMetric(title: "Moving time", value: timeLabel),
                ProgressShareMetric(title: "Avg Pace", value: paceLabel)
            ],
            insight: "RunSmart saved this activity for private progress tracking.",
            privacyNote: "Private share: no map, GPS points, or exact route are included."
        )
    }
}

private struct PostRunFullMapView: View {
    @Environment(\.dismiss) private var dismiss
    var points: [RunRoutePoint]

    var body: some View {
        NavigationStack {
            RouteMapView(points: points, title: nil)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle("Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityLabel("Close map")
                    }
                }
        }
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
                    Text("Short activity")
                        .font(.bodyMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("This looks too short for meaningful training analysis. Tap Done to keep it in your history, or delete it from the menu if it was a test or accidental stop.")
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
    var isShortActivity = false
    /// The coach debrief above already covers "tomorrow", so the report's next-run nudge is skipped.
    var hasDebrief = false

    @State private var isSavingSuggestedWorkout = false
    @State private var saveState: SaveState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PLAN UPDATE")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                StatusChip(text: statusText, tint: statusTint)
            }

            if let planFit = Self.planFitText(outcome: outcome, isShortActivity: isShortActivity) {
                Text(planFit)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let report = outcome?.report {
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
                } else if !hasDebrief {
                    PostRunDetailLine(label: "Next Run", value: report.notes.nextSessionNudge)
                }
            }
        }
    }

    private var statusText: String {
        if isShortActivity { return "Review" }
        if outcome?.didCompletePlannedWorkout == true { return "Plan complete" }
        return "Extra run"
    }

    private var statusTint: Color {
        if isShortActivity { return .accentEnergy }
        return outcome?.didCompletePlannedWorkout == true ? Color.accentSuccess : Color.accentPrimary
    }

    /// Nil when there is nothing specific to say yet (no processed outcome).
    static func planFitText(outcome: PostActivityOutcome?, isShortActivity: Bool) -> String? {
        if isShortActivity {
            return "This short activity is in your history, but RunSmart will not use it as a meaningful training signal."
        }
        guard let outcome else { return nil }
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

private struct SplitPreviewCard: View {
    var splits: [SplitRow]

    private var splitCountLabel: String {
        let count = splits.filter { $0.partialDistanceLabel == nil }.count
        return count == 1 ? "1 split" : "\(count) splits"
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("KM SPLITS", systemImage: "speedometer")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    Text(splitCountLabel)
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
                    SplitPaceBars(splits: splits)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)

                    ForEach(splits) { split in
                        HStack {
                            Text(split.partialDistanceLabel == nil ? "\(split.km)" : "-")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 28, alignment: .leading)
                            Text(split.pace)
                                .font(.metricSM)
                                .monospacedDigit()
                            Spacer()
                            Text(split.partialDistanceLabel ?? "km \(split.km)")
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
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Pace per kilometer as bars: a taller bar is a faster split. The partial last split is dimmer.
private struct SplitPaceBars: View {
    var splits: [SplitRow]
    private let chartHeight: CGFloat = 64

    var body: some View {
        let fractions = SplitPaceChart.barFractions(paces: splits.map(\.paceSeconds))
        // The partial last split is drawn but never named fastest or slowest.
        let fullSplits = splits.filter { $0.partialDistanceLabel == nil && $0.paceSeconds > 0 }
        let fastest = fullSplits.min(by: { $0.paceSeconds < $1.paceSeconds })
        let slowest = fullSplits.max(by: { $0.paceSeconds < $1.paceSeconds })
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: splits.count > 16 ? 2 : 4) {
                ForEach(Array(splits.enumerated()), id: \.element.id) { index, split in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor(for: split, isFastest: split.id == fastest?.id))
                            .frame(height: max(4, chartHeight * fractions[index]))
                        if splits.count <= 12 {
                            Text(split.partialDistanceLabel == nil ? "\(split.km)" : "+")
                                .font(.labelSM)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .frame(maxWidth: splits.count < 8 ? 36 : .infinity)
                }
                Spacer(minLength: 0)
            }
            .frame(height: chartHeight + (splits.count <= 12 ? 20 : 0))

            if let fastest, let slowest, fastest.id != slowest.id {
                Text("Fastest \(fastest.pace) at km \(fastest.km). Slowest \(slowest.pace) at km \(slowest.km). Taller bar is faster.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(fastest: fastest, slowest: slowest))
    }

    private func barColor(for split: SplitRow, isFastest: Bool) -> Color {
        if split.partialDistanceLabel != nil { return Color.accentPrimary.opacity(0.4) }
        return isFastest ? Color.accentSuccess : Color.accentPrimary.opacity(0.8)
    }

    private func accessibilitySummary(fastest: SplitRow?, slowest: SplitRow?) -> String {
        guard let fastest, let slowest, fastest.id != slowest.id else {
            return "Pace per kilometer chart, \(splits.count) bars."
        }
        return "Pace per kilometer chart. Fastest is kilometer \(fastest.km) at \(fastest.pace). Slowest is kilometer \(slowest.km) at \(slowest.pace)."
    }
}

private struct SplitRow: Identifiable {
    var id: Int { km }
    var km: Int
    var pace: String
    var paceSeconds: Double = 0
    /// Set only for the partial final split, e.g. "0.43 km". Pace is still per km.
    var partialDistanceLabel: String? = nil
}
