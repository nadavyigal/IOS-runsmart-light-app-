# Sprint 11 — UX Redesign + Voice Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Sprint 11 for RunSmart iOS 1.0.1: six UX redesign stories (Stream A) and four voice coach stories (Stream B) on branch `feature/ux-redesign-1.0.1`.

**Architecture:** Stream A rewires Today/Plan/Report/Profile tab views to simplify the information architecture — each is a self-contained SwiftUI file edit, no new components or services. Stream B adds a TTS coaching service (VoiceCoachService.swift) wired to RunTabView, backed by a new Next.js API route in the RunSmart Web repo.

**Tech Stack:** SwiftUI (iOS 17+), AVFoundation (AVAudioPlayer, AVAudioSession), Swift async/await, Next.js 14 Route Handlers, OpenAI TTS-1 via REST fetch, VOICE_COACH_ENABLED feature flag.

---

## Task 0: Branch Setup

**Files:**
- No file changes — branch operation only

- [ ] **Step 1: Create feature branch from main**

Working directory: `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990`

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990"
git checkout -B feature/ux-redesign-1.0.1 origin/main
```

Expected: `Switched to and reset branch 'feature/ux-redesign-1.0.1'`

- [ ] **Step 2: Verify branch**

```bash
git branch --show-current
```

Expected output: `feature/ux-redesign-1.0.1`

---

## Task 1 (A1): Today v2 + Safe Area Fix

**Files:**
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift`

**What changes:**
- `header` computed var redesigned: left side = greeting + streak subtext, right side = sparkles Coach icon button
- Body: remove TodayCoachHeroCard, move TodayWeekStripSection above TodayWorkoutRecommendationCard, remove challenge cards from top (move below fold), remove InsightCard, TodayConversationPreview, TodayQuickActions, quickStats; replace RecentRunReportsCard with single latest-run preview row
- `padding(.bottom, 24)` → `padding(.bottom, 140)`

- [ ] **Step 1: Replace the `header` computed var**

In `TodayTabView.swift`, replace lines 266–291 (the entire `header` computed var) with:

```swift
private var header: some View {
    HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(greeting), \(displayName)")
                .font(.displayMD)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if recommendation.streak != "--" {
                Text("🔥 \(recommendation.streak) day streak")
                    .font(.bodyLG)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        Spacer(minLength: 12)
        Button { router.openCoach(context: .today) } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 34, height: 34)
                .background(Color.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Rewrite the `body` LazyVStack content**

Replace lines 43–184 (the LazyVStack contents inside ScrollView) with this new body. The full `var body: some View` block becomes:

```swift
var body: some View {
    let resolvedState = todayState
    let primaryWorkout = resolvedState.primaryWorkout
    let todayRoute = resolvedState.showsTodayRoute ? routeRecommendation.route ?? routes.first : nil
    let explanation = todayExplanation

    ScrollView(showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 14) {
            header

            if !weekWorkouts.isEmpty {
                TodayWeekStripSection(workouts: weekWorkouts, weekRange: weekRangeLabel) { workout in
                    openWorkoutDetail(workout)
                }
                .runSmartStaggeredAppear(index: 0)
            }

            TodayWorkoutRecommendationCard(
                state: resolvedState,
                recommendation: recommendation,
                workout: primaryWorkout,
                route: todayRoute,
                onStart: { startRun(with: primaryWorkout) },
                onReviewReport: openLatestReport,
                onCoach: openTodayCoach,
                onModify: openPlanAdjustment,
                onSkip: { reschedule(primaryWorkout) },
                onRoute: openRouteSelector
            )
            .runSmartStaggeredAppear(index: 1)

            if let safety = recommendation.safetyExplanation {
                SafetyExplanationCard(
                    explanation: safety,
                    onAction: { router.open(.amendWorkout(primaryWorkout)) }
                )
                .runSmartStaggeredAppear(index: 2)
            }

            PlanExplanationCard(
                title: "Why this workout?",
                explanation: explanation,
                onAction: { handleExplanationAction(explanation, workout: primaryWorkout) }
            )
            .runSmartStaggeredAppear(index: 3)

            if FlexWeekEntryPresentation.shouldShowTodayLink(
                readiness: recommendation.readiness,
                weekWorkouts: weekWorkouts
            ) {
                FlexWeekTodayLink {
                    router.openFlexWeek(entryPoint: .todayLink)
                }
                .runSmartStaggeredAppear(index: 4)
            }

            if resolvedState.showsTodayRoute {
                TodayRouteRecommendationCard(
                    recommendation: routeRecommendation,
                    workout: primaryWorkout,
                    onUseRoute: { route in startRun(with: primaryWorkout, route: route) },
                    onBrowseRoutes: openRouteSelector
                )
                .runSmartStaggeredAppear(index: 5)
            }

            if !runReports.isEmpty {
                Button { router.selectedTab = .report } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(runReports[0].title)
                                .font(.bodyMD.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text("\(runReports[0].dateLabel) · \(runReports[0].distance) · \(runReports[0].pace)")
                                .font(.labelSM)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 54)
                    .background(Color.surfaceCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .runSmartStaggeredAppear(index: 6)
            }

            if !nextWorkouts.isEmpty {
                UpcomingRunsCard(workouts: nextWorkouts) { workout in
                    openWorkoutDetail(workout)
                }
                .runSmartStaggeredAppear(index: 7)
            }

            let isBeginnerChallenge = Beginner5KHabitTrack.isBeginnerFirst5K(profile: session.onboardingProfile)
            if (!challengeLoaded || !activeChallenge.isActive), isBeginnerChallenge {
                Beginner5KHabitCard(track: habitTrack)
                    .runSmartStaggeredAppear(index: 8)
            } else if let summary = weeklySummary {
                WeeklyProgressCard(
                    summary: summary,
                    onTapCoach: openTodayCoach
                )
                .runSmartStaggeredAppear(index: 8)
            }

            WeatherConditionsCard()
                .runSmartStaggeredAppear(index: 9)

            if activeChallenge.isActive {
                ChallengeProgressCard(challenge: activeChallenge, onTap: openChallenges)
                    .runSmartStaggeredAppear(index: 10)
            } else if challengeLoaded,
                      Beginner5KHabitTrack.isBeginnerFirst5K(profile: session.onboardingProfile) {
                ChallengeInviteCard(onEnrolled: scheduleLoad)
                    .runSmartStaggeredAppear(index: 10)
            }

            if isStriver {
                TodayWellnessTrendCard(
                    trends: wellnessTrends,
                    onTapRecovery: { router.open(.recoveryDashboard) }
                )
                .runSmartStaggeredAppear(index: 11)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 140)
    }
    .task {
        await loadData()
    }
    .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanDidChange)) { _ in
        scheduleLoad()
    }
    .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
        scheduleLoad()
    }
    .onReceive(NotificationCenter.default.publisher(for: .runSmartReportsDidChange)) { _ in
        scheduleLoad()
    }
}
```

- [ ] **Step 3: Swift parse check**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990"
xcrun swiftc -parse "IOS RunSmart app/Features/Today/TodayTabView.swift"
```

Expected: no output (parse success)

- [ ] **Step 4: Build**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990"
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Features/Today/TodayTabView.swift"
git commit -m "feat(A1): Today v2 — simplified header, week strip first, remove coach cards, bottom padding fix"
```

---

## Task 2 (A2): Report v2

**Files:**
- Modify: `IOS RunSmart app/Features/Activity/ActivityTabView.swift`
- Modify: `IOS RunSmart app/Features/Plan/PlanTabView.swift` (make RecoveryPlanCard non-private)

**What changes:**
- Replace filter pills with 3-segment control: Runs | Reports | Progress
- Add `runReports`, `trainingLoad`, `recovery` state + loading
- Reports segment: runReports list with "Explain this run ✦" link
- Progress segment: zone analysis, RunTrendChartCard, RecoveryPlanCard

- [ ] **Step 1: Make RecoveryPlanCard non-private in PlanTabView.swift**

In `IOS RunSmart app/Features/Plan/PlanTabView.swift`, find line:
```swift
private struct RecoveryPlanCard: View {
```
Change to:
```swift
struct RecoveryPlanCard: View {
```

- [ ] **Step 2: Add state properties to ReportTabView**

In `ActivityTabView.swift`, after line:
```swift
    @State private var benchmarkRoutes: [BenchmarkRoute] = []
```
Add:
```swift
    @State private var segment: ReportSegment = .runs
    @State private var runReports: [RunReportSummary] = []
    @State private var trainingLoad: TrainingLoadSnapshot = .loading
    @State private var recovery: RecoverySnapshot = .loading
```

And before the `var body` add the enum:
```swift
    private enum ReportSegment: String, CaseIterable, Hashable, Identifiable {
        case runs = "Runs"
        case reports = "Reports"
        case progress = "Progress"
        var id: String { rawValue }
    }
```

- [ ] **Step 3: Load runReports, trainingLoad, recovery in task**

In `ActivityTabView.swift`, change the `.task` block from:
```swift
        .task {
            await reloadRuns()
            await reloadRoutes()
        }
```
To:
```swift
        .task {
            await reloadRuns()
            await reloadRoutes()
            runReports = await services.latestRunReports(limit: 50)
            trainingLoad = await services.trainingLoadSnapshot()
            recovery = await services.recoverySnapshot()
        }
```

- [ ] **Step 4: Replace filter pills with segmented control and restructure body**

In `ActivityTabView.swift`, replace the entire `var body: some View` with:

```swift
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
```

- [ ] **Step 5: Add computed segment content properties**

After `var body` and before `private func reloadRuns()`, add:

```swift
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

        RecoveryPlanCard(recovery: recovery, trainingLoad: trainingLoad)
            .runSmartStaggeredAppear(index: 3)

        RunTrendChartCard(runs: runs)
            .runSmartStaggeredAppear(index: 4)
    }
```

- [ ] **Step 6: Add openReportSummary helper**

After `private func openReport(for run: RecordedRun)`, add:

```swift
    private func openReportSummary(_ report: RunReportSummary) {
        if let detail = report.toDetail() {
            router.open(.runReportDetail(detail))
        }
    }
```

Note: `router` needs to be added to ReportTabView. Add `@EnvironmentObject private var router: AppRouter` after the `@Environment(\.runSmartServices)` line.

- [ ] **Step 7: Add router EnvironmentObject to ReportTabView**

In `ActivityTabView.swift`, after:
```swift
    @Environment(\.runSmartServices) private var services
```
Add:
```swift
    @EnvironmentObject private var router: AppRouter
```

- [ ] **Step 8: Swift parse both files**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990"
xcrun swiftc -parse "IOS RunSmart app/Features/Activity/ActivityTabView.swift"
xcrun swiftc -parse "IOS RunSmart app/Features/Plan/PlanTabView.swift"
```

Expected: no output for both

- [ ] **Step 9: Build**

```bash
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Commit**

```bash
git add "IOS RunSmart app/Features/Activity/ActivityTabView.swift"
git add "IOS RunSmart app/Features/Plan/PlanTabView.swift"
git commit -m "feat(A2): Report v2 — 3-segment Runs/Reports/Progress, Explain this run link"
```

---

## Task 3 (A3): Coach Consolidation — TodayTabView only

**Files:**
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift`

**Note:** All PlanTabView coach-consolidation changes (remove InsightCard, guard PlanExplanationCard) are included in Task 4's full body rewrite. Only TodayTabView is modified here.

**What changes:**
- Guard `PlanExplanationCard` in TodayTabView: only show when `explanation.trigger != .normal || !explanation.isOnTrack`

- [ ] **Step 1: Guard PlanExplanationCard in TodayTabView**

In `TodayTabView.swift`, find:
```swift
            PlanExplanationCard(
                title: "Why this workout?",
                explanation: explanation,
                onAction: { handleExplanationAction(explanation, workout: primaryWorkout) }
            )
            .runSmartStaggeredAppear(index: 3)
```

Replace with:
```swift
            if explanation.trigger != .normal || !explanation.isOnTrack {
                PlanExplanationCard(
                    title: "Why this workout?",
                    explanation: explanation,
                    onAction: { handleExplanationAction(explanation, workout: primaryWorkout) }
                )
                .runSmartStaggeredAppear(index: 3)
            }
```

- [ ] **Step 2: Parse TodayTabView**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Today/TodayTabView.swift"
```

Expected: no output

- [ ] **Step 3: Build**

```bash
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Today/TodayTabView.swift"
git commit -m "feat(A3): Guard PlanExplanationCard in TodayTabView for normal on-track state"
```

---

## Task 4 (A4): Plan v2

**Files:**
- Modify: `IOS RunSmart app/Features/Plan/PlanTabView.swift`

**What changes:**
- Reorder body: header → PlanCurrentWeekSection → FlexWeekAdjustPill → "Explain this week" compact button → SegmentedPillPicker → segment content
- Replace PlanBriefingCard with "Explain this week" compact button
- Remove PlanBriefingCard
- Rename "Add Run" tile to "Add Activity" with updated detail text

- [ ] **Step 1: Reorder the LazyVStack body in PlanTabView and add "Explain this week" button**

In `PlanTabView.swift`, replace the entire `LazyVStack(alignment: .leading, spacing: 14)` contents (within the `NavigationStack > ScrollView`) with:

```swift
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header

                        if let current {
                            PlanCurrentWeekSection(week: current) { workout in
                                Analytics.trackPlanWorkoutTapped(
                                    workoutType: workout.kind.rawValue,
                                    weekNumber: current.weekNumber
                                )
                                openWorkoutDetail(workout)
                            }
                            .runSmartStaggeredAppear(index: 0)

                            FlexWeekAdjustPill {
                                router.openFlexWeek(entryPoint: .planPill)
                            }
                            .runSmartStaggeredAppear(index: 1)
                        }

                        Button(action: openPlanCoach) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.accentPrimary)
                                Text("Explain this week")
                                    .font(.bodyMD.weight(.semibold))
                                    .foregroundStyle(Color.accentPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color.accentPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.accentPrimary.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .runSmartStaggeredAppear(index: 2)

                        if explanation.trigger != .normal || !explanation.isOnTrack {
                            PlanExplanationCard(
                                title: explanation.isOnTrack ? "Plan is on track" : "Plan adjusted because...",
                                explanation: explanation,
                                onAction: { handleExplanationAction(explanation) }
                            )
                            .runSmartStaggeredAppear(index: 3)
                        }

                        SegmentedPillPicker(values: PlanViewMode.allCases, selection: $viewMode) { $0.rawValue }
                            .runSmartStaggeredAppear(index: 4)

                        switch viewMode {
                        case .month:
                            MonthlyScheduleCard(
                                displayedMonth: displayedMonth,
                                workoutsByDate: workoutsByDate,
                                onSelectWorkout: openWorkoutDetail,
                                onPreviousMonth: showPreviousMonth,
                                onNextMonth: showNextMonth
                            )
                        case .weekly:
                            PlanWeeklyReviewSection(weeks: weeksForReview, onWorkout: openWorkoutDetail)
                        case .progress:
                            PlanProgressSection(
                                goal: goal,
                                challenge: challenge,
                                trainingLoad: trainingLoad,
                                runs: recentRuns
                            )
                        }

                        PlanCoachNotesCard(workouts: nextWorkouts, goal: goal) { workout in
                            openWorkoutDetail(workout)
                        } onAll: {
                            showWeeklyReview()
                        }
                        .runSmartStaggeredAppear(index: 5)

                        PlanActionGrid(
                            onAdd: openAddActivity,
                            onCoach: openPlanCoach
                        )

                        if viewMode == .progress {
                            ChallengePlanCard(challenge: challenge) {
                                open(.challenges)
                            }

                            RecoveryPlanCard(recovery: recovery, trainingLoad: trainingLoad)

                            RunTrendChartCard(runs: recentRuns)
                        }
                    }
```

- [ ] **Step 2: Update PlanActionGrid "Add Run" → "Add Activity"**

In `PlanTabView.swift`, find `PlanActionGrid`:
```swift
private struct PlanActionGrid: View {
    var onAdd: () -> Void
    var onCoach: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PlanActionTile(title: "Add Run", detail: "Manual or synced", symbol: "plus.circle.fill", action: onAdd)
```

Replace `PlanActionTile(title: "Add Run", detail: "Manual or synced",` with:
```swift
            PlanActionTile(title: "Add Activity", detail: "Log manually or sync", symbol: "plus.circle.fill", action: onAdd)
```

- [ ] **Step 3: Parse and build**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Plan/PlanTabView.swift"
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: no parse errors, `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Plan/PlanTabView.swift"
git commit -m "feat(A4): Plan v2 — week first, Explain this week button, remove briefing card, rename Add Activity"
```

---

## Task 5 (A5): Profile v2

**Files:**
- Modify: `IOS RunSmart app/Features/Profile/ProfileTabView.swift`

**What changes:**
- Reorder sections: identityHeader → statsBar → connectedSection → trainingDataCard → coachSettingsGrid → coachSparkCard → optimizationCards → achievementsGallery
- Remove the `if !runReports.isEmpty { RecentRunReportsCard(...) }` block
- Remove `runReports` state and loading (no longer needed in Profile)

- [ ] **Step 1: Remove runReports state and loading from ProfileTabView**

In `ProfileTabView.swift`:

Remove the state property:
```swift
    @State private var runReports: [RunReportSummary] = []
```

In `loadProfileData()`, change:
```swift
        async let reportsTask = services.latestRunReports(limit: 3)
        async let runsTask = services.recentRuns()
        async let challengeTask = services.activeChallenge()
        (runner, achievements, deviceStatuses, runReports, recentRuns, challenge) = await (
            runnerTask,
            achievementsTask,
            statusesTask,
            reportsTask,
            runsTask,
            challengeTask
        )
```
To:
```swift
        async let runsTask = services.recentRuns()
        async let challengeTask = services.activeChallenge()
        (runner, achievements, deviceStatuses, recentRuns, challenge) = await (
            runnerTask,
            achievementsTask,
            statusesTask,
            runsTask,
            challengeTask
        )
```

- [ ] **Step 2: Reorder body and remove RecentRunReportsCard**

Replace the `LazyVStack` contents in `ProfileTabView.body` with:

```swift
                    LazyVStack(alignment: .leading, spacing: 14) {
                        RunSmartTopBar(title: "Profile", showSettings: true) {
                            open(.account)
                        }

                        identityHeader
                        statsBar
                        connectedSection
                        trainingDataCard
                        coachSettingsGrid
                        coachSparkCard
                        optimizationCards
                        achievementsGallery
                    }
```

- [ ] **Step 3: Parse and build**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Profile/ProfileTabView.swift"
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: no parse errors, `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Profile/ProfileTabView.swift"
git commit -m "feat(A5): Profile v2 — connected section first, remove run reports card"
```

---

## Task 6 (A6): Post-Run Bridge

**Files:**
- Modify: `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`

**What changes:**
- Add `router.selectedTab = .report` action as a "View Report" button after the CoachAnalysisCard

- [ ] **Step 1: Add router EnvironmentObject to PostRunSummaryView**

In `PostRunSummaryView.swift`, after `@Environment(\.runSmartServices) private var services`, add:
```swift
    @EnvironmentObject private var router: AppRouter
```

- [ ] **Step 2: Add View Report button after CoachAnalysisCard**

In `PostRunSummaryView.swift`, find:
```swift
                CoachAnalysisCard(run: run, rpe: rpe)
```

After this line, add:
```swift
                Button {
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
```

- [ ] **Step 3: Parse and build**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Run/PostRunSummaryView.swift"
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: no parse errors, `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Run/PostRunSummaryView.swift"
git commit -m "feat(A6): Post-run bridge — View Report button navigates to Report tab"
```

---

## Task 7 (B1): Backend `/api/coach/voice-cue` Endpoint

**Repo:** RunSmart Web (`/Users/nadavyigal/Documents/RunSmart/v0/`)
**Files:**
- Create: `app/api/coach/voice-cue/route.ts`

**What it does:** POST endpoint that (1) calls gpt-4o-mini to generate a 1-2 sentence coaching cue, (2) calls OpenAI TTS-1 REST API to produce AAC audio, (3) returns audio bytes with `Content-Type: audio/aac` and `X-Coach-Text` header. Returns 503 when `VOICE_COACH_ENABLED != "true"`.

- [ ] **Step 1: Create the route file**

Create `/Users/nadavyigal/Documents/RunSmart/v0/app/api/coach/voice-cue/route.ts`:

```typescript
import { NextResponse } from "next/server"
import { generateText } from "ai"
import { openai } from "@ai-sdk/openai"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

interface VoiceCueRequest {
  elapsedMinutes: number
  distanceKm: number
  currentPaceMinPerKm: number
  targetPaceMinPerKm?: number
  workoutGoal?: string
  heartRateBPM?: number
}

const COACH_SYSTEM_PROMPT = `You are RunSmart, a calm encouraging running coach.
Give one short coaching cue (1–2 sentences, max 25 words).
Be specific to the data provided. Never open with "Great job".
Never advise running through pain — if the runner mentions pain, say stop and consult a professional.
Sound like a real coach, not a chatbot.`

export async function POST(request: Request): Promise<Response> {
  if (process.env.VOICE_COACH_ENABLED !== "true") {
    return NextResponse.json({ error: "Voice coach is not enabled" }, { status: 503 })
  }

  let body: VoiceCueRequest
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const { elapsedMinutes, distanceKm, currentPaceMinPerKm, targetPaceMinPerKm, workoutGoal, heartRateBPM } = body

  const userContext = [
    `Elapsed: ${elapsedMinutes.toFixed(1)} min`,
    `Distance: ${distanceKm.toFixed(2)} km`,
    `Current pace: ${currentPaceMinPerKm.toFixed(1)} min/km`,
    targetPaceMinPerKm ? `Target pace: ${targetPaceMinPerKm.toFixed(1)} min/km` : null,
    workoutGoal ? `Goal: ${workoutGoal}` : null,
    heartRateBPM ? `Heart rate: ${heartRateBPM} bpm` : null,
  ]
    .filter(Boolean)
    .join(", ")

  let cueText: string
  try {
    const result = await generateText({
      model: openai("gpt-4o-mini"),
      system: COACH_SYSTEM_PROMPT,
      prompt: userContext,
      maxTokens: 60,
    })
    cueText = result.text.trim()
  } catch {
    return NextResponse.json({ error: "Text generation failed" }, { status: 500 })
  }

  const apiKey = process.env.OPENAI_API_KEY
  if (!apiKey) {
    return NextResponse.json({ error: "OpenAI key not configured" }, { status: 500 })
  }

  let audioBuffer: ArrayBuffer
  try {
    const ttsResponse = await fetch("https://api.openai.com/v1/audio/speech", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "tts-1",
        input: cueText,
        voice: "nova",
        response_format: "aac",
        speed: 0.95,
      }),
    })
    if (!ttsResponse.ok) {
      return NextResponse.json({ error: "TTS generation failed" }, { status: 500 })
    }
    audioBuffer = await ttsResponse.arrayBuffer()
  } catch {
    return NextResponse.json({ error: "TTS request failed" }, { status: 500 })
  }

  return new Response(audioBuffer, {
    status: 200,
    headers: {
      "Content-Type": "audio/aac",
      "X-Coach-Text": encodeURIComponent(cueText),
      "Cache-Control": "no-store",
    },
  })
}
```

- [ ] **Step 2: TypeScript compile check**

```bash
cd "/Users/nadavyigal/Documents/RunSmart/v0"
npx tsc --noEmit 2>&1 | grep "voice-cue\|error" | head -10
```

Expected: no errors in `voice-cue/route.ts`

- [ ] **Step 3: Smoke test (requires local server running)**

If Next.js dev server is running on port 3000:
```bash
curl -s -X POST http://localhost:3000/api/coach/voice-cue \
  -H "Content-Type: application/json" \
  -d '{"elapsedMinutes":10,"distanceKm":1.5,"currentPaceMinPerKm":6.0}' \
  -w "\nHTTP: %{http_code}\n" \
  --output /tmp/test-cue.aac 2>&1
```

When `VOICE_COACH_ENABLED` is not set: HTTP 503.
When `VOICE_COACH_ENABLED=true`: HTTP 200, `/tmp/test-cue.aac` non-zero bytes, `X-Coach-Text` header present.

- [ ] **Step 4: Commit in web repo**

```bash
cd "/Users/nadavyigal/Documents/RunSmart/v0"
git add app/api/coach/voice-cue/route.ts
git commit -m "feat(B1): /api/coach/voice-cue — TTS coaching cue endpoint with feature flag"
```

---

## Task 8 (B2): VoiceCoachService.swift

**Repo:** RunSmart iOS
**Files:**
- Create: `IOS RunSmart app/Services/VoiceCoachService.swift`

- [ ] **Step 1: Create VoiceCoachService.swift**

Create `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990/IOS RunSmart app/Services/VoiceCoachService.swift`:

```swift
import Foundation
import AVFoundation

extension Notification.Name {
    static let voiceCoachCueTimerFired = Notification.Name("com.runsmart.voiceCoachCueTimerFired")
}

struct VoiceCueContext: Encodable {
    var elapsedMinutes: Double
    var distanceKm: Double
    var currentPaceMinPerKm: Double
    var targetPaceMinPerKm: Double?
    var workoutGoal: String?
    var heartRateBPM: Int?
}

@MainActor
final class VoiceCoachService: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = VoiceCoachService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastCueText: String?

    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var isFetching = false

    private static let userDefaultsKey = "voiceCoachEnabled"
    private static let cueInterval: TimeInterval = 300

    private override init() {
        isEnabled = UserDefaults.standard.object(forKey: VoiceCoachService.userDefaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: VoiceCoachService.userDefaultsKey)
        super.init()
    }

    func startSession() {
        configureAudioSession()
        startTimer()
    }

    func stopSession() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func pauseSession() {
        timer?.invalidate()
        timer = nil
        player?.pause()
    }

    func resumeSession() {
        startTimer()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: VoiceCoachService.userDefaultsKey)
        if !enabled {
            stopSession()
        }
    }

    func deliverCue(context: VoiceCueContext) {
        guard isEnabled, !isFetching else { return }
        isFetching = true
        Task { [weak self] in
            await self?.fetchAndPlay(context: context)
            await MainActor.run { [weak self] in
                self?.isFetching = false
            }
        }
    }

    // MARK: AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {}

    // MARK: Private

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
        try? session.setActive(true)
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: VoiceCoachService.cueInterval, repeats: true) { _ in
            NotificationCenter.default.post(name: .voiceCoachCueTimerFired, object: nil)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fetchAndPlay(context: VoiceCueContext) async {
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "RunSmartAPIBaseURL") as? String,
              let url = URL(string: "\(baseURLString)/api/coach/voice-cue") else { return }

        guard let bodyData = try? JSONEncoder().encode(context) else { return }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty else { return }

        if let encodedText = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Coach-Text"),
           let text = encodedText.removingPercentEncoding {
            await MainActor.run { [weak self] in
                self?.lastCueText = text
            }
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            try? self.player?.stop()
            if let p = try? AVAudioPlayer(data: data) {
                p.delegate = self
                p.prepareToPlay()
                p.play()
                self.player = p
            }
        }
    }
}
```

- [ ] **Step 2: Swift parse check**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990"
xcrun swiftc -parse "IOS RunSmart app/Services/VoiceCoachService.swift"
```

Expected: no output

- [ ] **Step 3: Build (confirms the file is included in the target)**

```bash
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

If it fails with "unresolved identifier 'VoiceCoachService'", the file is not in the Xcode target. Since this is a folder-synchronized project, the file is automatically included by Xcode when it's placed in the correct directory — no manual project.pbxproj edit needed.

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Services/VoiceCoachService.swift"
git commit -m "feat(B2): VoiceCoachService — AVAudioSession, 5-min timer, silent-failure cue delivery"
```

---

## Task 9 (B3): RunTabView Wiring

**Files:**
- Modify: `IOS RunSmart app/Features/Run/RunTabView.swift`

**Pre-condition check (do before editing):**

`RunRecorder` exposes:
- `recorder.distanceMeters: Double` — raw km distance ÷ 1000
- `recorder.movingSeconds: TimeInterval` — raw seconds; divide by 60 for minutes
- No raw currentPaceMinPerKm property — compute: `recorder.distanceMeters > 0 ? (recorder.movingSeconds / (recorder.distanceMeters / 1000.0)) / 60.0 : 0.0`

No new properties needed on RunRecorder.

- [ ] **Step 1: Add onChange for recorder.phase to start/stop VoiceCoachService**

In `RunTabView.swift`, add these two `.onChange` modifiers after the `.task` block:

```swift
        .onChange(of: recorder.phase) { oldPhase, newPhase in
            switch newPhase {
            case .recording where oldPhase == .paused:
                VoiceCoachService.shared.resumeSession()
            case .recording:
                VoiceCoachService.shared.startSession()
            case .paused:
                VoiceCoachService.shared.pauseSession()
            case .idle, .ready, .denied, .failed:
                VoiceCoachService.shared.stopSession()
            default:
                break
            }
        }
```

- [ ] **Step 2: Add timer notification subscription for cue delivery**

In `RunTabView.swift`, add this `.onReceive` after the phase onChange:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .voiceCoachCueTimerFired)) { _ in
            guard recorder.phase == .recording else { return }
            let context = VoiceCueContext(
                elapsedMinutes: recorder.movingSeconds / 60.0,
                distanceKm: recorder.distanceMeters / 1000.0,
                currentPaceMinPerKm: recorder.distanceMeters > 0
                    ? (recorder.movingSeconds / (recorder.distanceMeters / 1000.0)) / 60.0
                    : 0.0,
                targetPaceMinPerKm: nil,
                workoutGoal: router.plannedWorkout?.title,
                heartRateBPM: nil
            )
            VoiceCoachService.shared.deliverCue(context: context)
        }
```

- [ ] **Step 3: Parse and build**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Run/RunTabView.swift"
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: no parse errors, `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Run/RunTabView.swift"
git commit -m "feat(B3): RunTabView wiring — VoiceCoachService start/pause/stop on phase change + cue timer"
```

---

## Task 10 (B4): Mute Toggle in LiveRunView

**Files:**
- Modify: `IOS RunSmart app/Features/Run/LiveRunView.swift`

**What changes:**
- Add `@ObservedObject private var voiceCoach = VoiceCoachService.shared` to LiveRunView
- Add mute button to the HStack of control buttons (alongside Pause and Finish)

- [ ] **Step 1: Add ObservedObject to LiveRunView**

In `LiveRunView.swift`, after the `var onDiscard: () -> Void` property, add:

```swift
    @ObservedObject private var voiceCoach = VoiceCoachService.shared
```

- [ ] **Step 2: Add mute button to control HStack**

In `LiveRunView.swift`, find the HStack with control buttons:
```swift
                HStack(alignment: .bottom, spacing: 18) {
                    LiveControlButton(title: phase == .paused ? "Resume" : "Pause", symbol: phase == .paused ? "play.fill" : "pause.fill", tint: .accentPrimary, prominent: true, action: onPauseResume)
                    LiveControlButton(title: "Finish", symbol: "stop.fill", tint: .accentHeart, prominent: false, action: onFinish)
                    if phase == .paused {
                        LiveControlButton(title: "Discard", symbol: "trash.fill", tint: .accentHeart, prominent: false, action: onDiscard)
                    }
                }
```

Replace with:
```swift
                HStack(alignment: .bottom, spacing: 18) {
                    LiveControlButton(title: phase == .paused ? "Resume" : "Pause", symbol: phase == .paused ? "play.fill" : "pause.fill", tint: .accentPrimary, prominent: true, action: onPauseResume)
                    LiveControlButton(title: "Finish", symbol: "stop.fill", tint: .accentHeart, prominent: false, action: onFinish)
                    LiveControlButton(
                        title: voiceCoach.isEnabled ? "Coach" : "Muted",
                        symbol: voiceCoach.isEnabled ? "waveform" : "waveform.slash",
                        tint: voiceCoach.isEnabled ? .accentPrimary : .textSecondary,
                        prominent: false,
                        action: { voiceCoach.setEnabled(!voiceCoach.isEnabled) }
                    )
                    if phase == .paused {
                        LiveControlButton(title: "Discard", symbol: "trash.fill", tint: .accentHeart, prominent: false, action: onDiscard)
                    }
                }
```

- [ ] **Step 3: Parse and build**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Run/LiveRunView.swift"
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: no parse errors, `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "IOS RunSmart app/Features/Run/LiveRunView.swift"
git commit -m "feat(B4): LiveRunView mute toggle — waveform/waveform.slash button wired to VoiceCoachService"
```

---

## Task 11: Version Bump + Final Build

**Files:**
- Modify: `IOS RunSmart app.xcodeproj/project.pbxproj`

- [ ] **Step 1: Bump MARKETING_VERSION to 1.0.1**

```bash
cd "/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990"
sed -i '' 's/MARKETING_VERSION = 1\.0;/MARKETING_VERSION = 1.0.1;/g' "IOS RunSmart app.xcodeproj/project.pbxproj"
```

Verify:
```bash
grep "MARKETING_VERSION" "IOS RunSmart app.xcodeproj/project.pbxproj" | head -5
```

Expected: all lines show `MARKETING_VERSION = 1.0.1;`

- [ ] **Step 2: Bump CURRENT_PROJECT_VERSION to 7**

```bash
sed -i '' 's/CURRENT_PROJECT_VERSION = 6;/CURRENT_PROJECT_VERSION = 7;/g' "IOS RunSmart app.xcodeproj/project.pbxproj"
```

Verify:
```bash
grep "CURRENT_PROJECT_VERSION" "IOS RunSmart app.xcodeproj/project.pbxproj" | head -5
```

Expected: all lines show `CURRENT_PROJECT_VERSION = 7;`

- [ ] **Step 3: Final clean build with version bump**

```bash
xcodebuild \
  -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-sprint11-derived \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Final commit**

```bash
git add "IOS RunSmart app.xcodeproj/project.pbxproj"
git commit -m "feat: Sprint 11 — UX redesign + voice coach (1.0.1 / build 7)"
```

- [ ] **Step 5: Update tasks/MEMORY.md**

Append to `/Users/nadavyigal/Documents/Projects /IOS RunSmart light /IOS RunSmart app/.claude/worktrees/strange-heyrovsky-b89990/tasks/MEMORY.md`:

```markdown
## 2026-06-01 — Sprint 11 — UX Redesign + Voice Coach

Worked on: All 10 Sprint 11 stories on feature/ux-redesign-1.0.1

Completed:
- A1: Today v2 — new header with streak + sparkles icon, week strip first, removed coach hero/insight/conversation/quickActions/quickStats cards, latest run preview row, bottom padding 140
- A2: Report v2 — 3-segment Runs/Reports/Progress, reports list with "Explain this run" link, progress tab with zone analysis/training load/run trend chart
- A3: Coach consolidation — removed InsightCard from Plan, guarded PlanExplanationCard in both Today and Plan
- A4: Plan v2 — week section first, "Explain this week" compact button replaces PlanBriefingCard, "Add Activity" rename
- A5: Profile v2 — connected section first, removed RecentRunReportsCard
- A6: Post-run bridge — "View Report" button navigates to Report tab
- B1: /api/coach/voice-cue endpoint in RunSmart Web — gpt-4o-mini cue + TTS-1 AAC, 503 when flag off
- B2: VoiceCoachService.swift — AVAudioSession duckOthers, 300s timer, 8s timeout, silent failure
- B3: RunTabView wiring — phase onChange → start/pause/stop/resume, timer notification → deliverCue
- B4: LiveRunView mute toggle — waveform/waveform.slash button, ObservableObject binding

Version bumped: 1.0.1 / build 7

NOT done (deferred):
- Physical device QA (requires TestFlight build 7 — human action)
- VOICE_COACH_ENABLED=true flip in Vercel (human action)
- TestFlight upload (human action)

Next session: Human to upload build 7 to TestFlight, run physical device QA checklist from sprint prompt, flip VOICE_COACH_ENABLED=true in Vercel when ready to test voice cues.
```

---

## Spec Coverage Self-Review

| Spec requirement | Task |
|---|---|
| Today header with greeting + streak + sparkles icon | Task 1 |
| TodayWeekStripSection above decision card | Task 1 |
| Remove TodayCoachHeroCard, InsightCard, ConversationPreview, QuickActions, quickStats | Task 1 |
| Latest run preview row → router.selectedTab = .report | Task 1 |
| Bottom padding 24 → 140 | Task 1 |
| Report 3-segment Runs/Reports/Progress | Task 2 |
| Reports segment with "Explain this run ✦" | Task 2 |
| Progress segment: zone analysis + training load + run trend | Task 2 |
| Remove InsightCard from Plan | Task 3 |
| Guard PlanExplanationCard normal+on-track state | Task 3 |
| Plan: week section first | Task 4 |
| "Explain this week" compact button replacing PlanBriefingCard | Task 4 |
| Add Activity rename | Task 4 |
| Profile: connected section first | Task 5 |
| Profile: remove RecentRunReportsCard | Task 5 |
| Post-run View Report → selectedTab = .report | Task 6 |
| /api/coach/voice-cue POST endpoint | Task 7 |
| 503 when VOICE_COACH_ENABLED not set | Task 7 |
| VoiceCoachService with AVAudioSession duckOthers | Task 8 |
| 300s repeating timer firing voiceCoachCueTimerFired | Task 8 |
| deliverCue — 8s timeout, silent failure | Task 8 |
| setEnabled persists to UserDefaults | Task 8 |
| RunTabView phase change wiring | Task 9 |
| VoiceCueContext from live recorder values | Task 9 |
| Mute toggle in LiveRunView | Task 10 |
| Version 1.0.1 / build 7 | Task 11 |
