import SwiftUI

struct PlanTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var weekWorkouts: [WorkoutSummary] = []
    @State private var nextWorkouts: [WorkoutSummary] = []
    @State private var workoutsByDate: [String: WorkoutSummary] = [:]
    @State private var displayedMonth: Date = Date()
    @State private var isLoadingMonthWorkouts: Bool = true
    @State private var recentRuns: [RecordedRun] = []
    @State private var goal: GoalSummary = .loading
    @State private var challenge: ChallengeSummary = .loading
    @State private var recovery: RecoverySnapshot = .loading
    @State private var trainingLoad: TrainingLoadSnapshot = .loading
    @State private var viewMode: PlanViewMode = .month
    @State private var navPath: [SecondaryDestination] = []

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        let today = Date()
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func monthBounds(for month: Date) -> (start: Date, end: Date) {
        PlanPresentationModels.monthQueryBounds(for: month)
    }

    private var planWeeks: [PlanWeekSummary] {
        let monthWorkouts = Array(workoutsByDate.values)
        let workouts = PlanPresentationModels.uniqueWorkouts([monthWorkouts, weekWorkouts, nextWorkouts])
        return PlanPresentationModels.makeWeeks(displayedMonth: displayedMonth, workouts: workouts)
    }

    private var currentWeek: PlanWeekSummary? {
        planWeeks.first(where: \.isCurrentWeek) ?? planWeeks.first
    }

    private var reviewWeeks: [PlanWeekSummary] {
        let currentID = currentWeek?.id
        return planWeeks.filter { $0.id != currentID }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    PlanBriefingCard(
                        name: session.onboardingProfile.displayName,
                        goal: goal,
                        recovery: recovery,
                        onCoach: { router.openCoach(context: "Plan") }
                    )
                    .runSmartStaggeredAppear(index: 0)

                    if let currentWeek {
                        PlanCurrentWeekSection(week: currentWeek) { workout in
                            navPath.append(.workoutDetail(workout))
                        }
                        .runSmartStaggeredAppear(index: 1)
                    }

                    SegmentedPillPicker(values: PlanViewMode.allCases, selection: $viewMode) { $0.rawValue }
                        .runSmartStaggeredAppear(index: 2)

                    switch viewMode {
                    case .month:
                        MonthlyScheduleCard(
                            displayedMonth: displayedMonth,
                            workoutsByDate: workoutsByDate,
                            onSelectWorkout: { workout in navPath.append(.workoutDetail(workout)) },
                            onPreviousMonth: {
                                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                            },
                            onNextMonth: {
                                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                            }
                        )
                    case .weekly:
                        PlanWeeklyReviewSection(weeks: reviewWeeks.isEmpty ? planWeeks : reviewWeeks) { workout in
                            navPath.append(.workoutDetail(workout))
                        }
                    case .progress:
                        PlanProgressSection(
                            goal: goal,
                            challenge: challenge,
                            trainingLoad: trainingLoad,
                            runs: recentRuns
                        )
                    }

                    PlanCoachNotesCard(workouts: nextWorkouts, goal: goal) { workout in
                        navPath.append(.workoutDetail(workout))
                    } onAll: {
                        viewMode = .weekly
                    }
                    .runSmartStaggeredAppear(index: 3)

                    InsightCard(
                        title: "Coach Notes",
                        message: recovery.recommendation,
                        action: { router.openCoach(context: "Plan") }
                    )
                    .runSmartStaggeredAppear(index: 4)

                    PlanActionGrid(
                        onAdd: { router.open(.addActivity) },
                        onCoach: { router.openCoach(context: "Plan") }
                    )

                    if viewMode == .progress {
                        ChallengePlanCard(challenge: challenge) {
                            navPath.append(.challenges)
                        }

                        RecoveryPlanCard(recovery: recovery, trainingLoad: trainingLoad)

                        RunTrendChartCard(runs: recentRuns)
                    }
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 140)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SecondaryDestination.self) { destination in
                SecondaryFlowView(destination: destination)
            }
        }
        .task {
            await loadPlanData()
        }
        .task(id: displayedMonth) {
            await loadMonthData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanDidChange)) { _ in
            Task {
                await loadPlanData()
                await loadMonthData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            Task {
                await loadPlanData()
                await loadMonthData()
            }
        }
    }

    private func loadPlanData() async {
        async let weekTask = services.weeklyPlan()
        async let nextTask = services.nextWorkouts(limit: 3)
        async let runsTask = services.recentRuns()
        async let goalTask = services.activeGoal()
        async let challengeTask = services.activeChallenge()
        async let recoveryTask = services.recoverySnapshot()
        async let loadTask = services.trainingLoadSnapshot()
        let (ww, nw, runs, g, ch, rec, load) = await (
            weekTask, nextTask, runsTask, goalTask, challengeTask, recoveryTask, loadTask
        )
        weekWorkouts = ww
        nextWorkouts = nw
        recentRuns = runs
        goal = g
        challenge = ch
        recovery = rec
        trainingLoad = load
    }

    private func loadMonthData() async {
        isLoadingMonthWorkouts = true
        let (startDate, endDate) = monthBounds(for: displayedMonth)
        let loaded = await services.planWorkouts(from: startDate, to: endDate)
        workoutsByDate = Dictionary(
            loaded.map { w in (ISO8601DateFormatter.shortDate.string(from: w.scheduledDate), w) },
            uniquingKeysWith: { first, _ in first }
        )
        isLoadingMonthWorkouts = false
    }

    private var header: some View {
        RunSmartTopBar(title: "Plan")
    }
}

private enum PlanViewMode: String, CaseIterable, Hashable, Identifiable {
    case month = "Monthly"
    case weekly = "Weekly"
    case progress = "Progress"
    var id: String { rawValue }
}

private struct PlanBriefingCard: View {
    var name: String
    var goal: GoalSummary
    var recovery: RecoverySnapshot
    var onCoach: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 18, accent: .accentPrimary) {
            HStack(alignment: .top, spacing: 16) {
                CoachAvatar(size: 94, showBolt: false)
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "AI Coach Briefing")
                    Text("Strong week ahead\(name.isEmpty ? "" : ", \(name)"). Your recovery is \(recovery.hrv.lowercased()) and last week's tempo looked solid. We're building fitness with a \(goal.title.lowercased()) focus.")
                        .font(.bodyLG)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Focus: \(goal.trendLabel) - Build Aerobic Endurance")
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.accentPrimary)

                    Button(action: onCoach) {
                        HStack {
                            CoachGlowBadge(size: 34)
                            Text("Ask Coach anything...")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .background(Color.surfaceCard.opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(Color.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PlanWeekStripSection: View {
    var workouts: [WorkoutSummary]
    var weekRange: String
    var onWorkout: (WorkoutSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This Week")
                    .font(.bodyLG.weight(.semibold))
                Spacer()
                Text(weekRange)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workouts) { workout in
                        Button { onWorkout(workout) } label: {
                            WorkoutDayCard(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

private struct PlanMonthOverviewStrip: View {
    var displayedMonth: Date
    var workoutsByDate: [String: WorkoutSummary]
    var onSelectWorkout: (WorkoutSummary) -> Void
    var onPreviousMonth: () -> Void
    var onNextMonth: () -> Void

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM 'Overview'"
        return formatter.string(from: displayedMonth)
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.bodyLG.weight(.semibold))
                    Spacer()
                    Button(action: onPreviousMonth) {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    Button(action: onNextMonth) {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Color.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(days, id: \.self) { date in
                            let key = ISO8601DateFormatter.shortDate.string(from: date)
                            let workout = workoutsByDate[key]
                            PlanOverviewDay(date: date, workout: workout) {
                                if let workout { onSelectWorkout(workout) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PlanOverviewDay: View {
    var date: Date
    var workout: WorkoutSummary?
    var onTap: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(weekday)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.textSecondary)
                Text(day)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(isToday ? Color.black : Color.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(isToday ? Color.accentPrimary : Color.clear, in: Circle())
                Circle()
                    .fill(workout == nil ? Color.textTertiary.opacity(0.5) : (workout?.isComplete == true ? Color.accentPrimary : tint))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 36)
        }
        .buttonStyle(.plain)
        .disabled(workout == nil)
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }

    private var day: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var tint: Color {
        guard let workout else { return .textTertiary }
        switch workout.kind {
        case .tempo, .intervals: return .accentAmber
        case .hills, .strength: return .accentMagenta
        case .long: return .accentRecovery
        default: return .accentPrimary
        }
    }
}

private struct PlanCoachNotesCard: View {
    var workouts: [WorkoutSummary]
    var goal: GoalSummary
    var onWorkout: (WorkoutSummary) -> Void
    var onAll: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Upcoming from Your Coach")
                        .font(.bodyLG.weight(.semibold))
                    Spacer()
                    Button("View all", action: onAll)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.accentPrimary)
                }

                ForEach(Array(workouts.prefix(2))) { workout in
                    Button { onWorkout(workout) } label: {
                        HStack(spacing: 14) {
                            RunSmartIconMark(size: 58, tint: .accentPrimary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(workout.weekday.capitalized): \(workout.title)")
                                    .font(.bodyLG.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Text(workout.detail.isEmpty ? goal.detail : workout.detail)
                                    .font(.bodyMD)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            RunSmartIconMark(size: 28, tint: .textSecondary)
                        }
                        .padding(10)
                        .background(Color.surfaceCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PlanCurrentWeekSection: View {
    var week: PlanWeekSummary
    var onWorkout: (WorkoutSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week")
                    .font(.headingMD)
                Spacer()
                Text(week.dateRangeLabel)
                    .font(.labelSM)
                    .foregroundStyle(Color.textSecondary)
            }

            PlanWeekSummaryCard(week: week, onWorkout: onWorkout)
        }
    }
}

private struct PlanWeeklyReviewSection: View {
    var weeks: [PlanWeekSummary]
    var onWorkout: (WorkoutSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weekly Review")
                    .font(.headingMD)
                Spacer()
                Text("Week by week")
                    .font(.labelSM)
                    .foregroundStyle(Color.textSecondary)
            }

            if weeks.isEmpty {
                RunSmartPanel(cornerRadius: 20, padding: 16) {
                    Text("Create or sync a plan to see weekly workouts here.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(weeks) { week in
                        PlanWeekSummaryCard(week: week, onWorkout: onWorkout)
                    }
                }
            }
        }
    }
}

private struct PlanWeekSummaryCard: View {
    var week: PlanWeekSummary
    var onWorkout: (WorkoutSummary) -> Void

    private var progressCount: Int {
        max(1, week.totalWorkouts)
    }

    private var weekTitle: String {
        week.isCurrentWeek ? "This Week" : "Week \(week.weekNumber)"
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 0, accent: week.isCurrentWeek ? .accentPrimary : nil) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(week.dateRangeLabel)
                        .font(.labelSM)
                        .foregroundStyle(Color.textSecondary)
                    Text(weekTitle)
                        .font(.displayMD)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                HStack(spacing: 7) {
                    ForEach(0..<progressCount, id: \.self) { _ in
                        Capsule()
                            .fill(Color.textTertiary.opacity(0.45))
                            .frame(height: 5)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Workouts: \(week.totalWorkouts)")
                    Text("Distance: \(week.totalDistanceLabel)")
                }
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)

                VStack(spacing: 12) {
                    ForEach(week.visibleWorkouts) { workout in
                        Button { onWorkout(workout) } label: {
                            PlanWeekWorkoutRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(week.isCurrentWeek ? Color.accentPrimary : Color.clear, lineWidth: 2)
        )
    }
}

private struct PlanWeekWorkoutRow: View {
    var workout: WorkoutSummary

    private var tint: Color {
        switch workout.kind {
        case .tempo, .intervals, .hills: return .accentEnergy
        case .long: return .accentMagenta
        case .recovery: return .accentRecovery
        case .strength: return .accentRecovery
        default: return .accentSuccess
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.kind.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Color.accentPrimary, tint], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Text(shortWeekday)
                .font(.bodyLG)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .leading)

            Text("\(workout.title) · \(workout.distance)")
                .font(.bodyLG.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var shortWeekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: workout.scheduledDate)
    }
}

private struct PlanWeekSection: View {
    var workouts: [WorkoutSummary]
    var weekRange: String
    var onWorkout: (WorkoutSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                Text(weekRange)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workouts) { workout in
                        Button { onWorkout(workout) } label: {
                            WorkoutDayCard(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 8)
            }
        }
    }
}

struct WorkoutDayCard: View {
    var workout: WorkoutSummary

    private var tint: Color {
        switch workout.kind {
        case .tempo, .intervals, .hills: return .accentEnergy
        case .long: return .accentMagenta
        case .strength, .recovery: return .accentRecovery
        default: return .accentSuccess
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(workout.weekday)
                .font(.caption2.bold())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Text(workout.date)
                .font(.title3.weight(workout.isToday ? .bold : .semibold))
                .frame(height: 26)
            Image(systemName: workout.kind.symbol)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(workout.isToday ? Color.black : tint)
                .frame(width: 40, height: 40)
                .background(workout.isToday ? Color.accentPrimary : tint.opacity(0.14), in: Circle())
            Text(workout.title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(height: 32, alignment: .top)
            Text(workout.distance)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 0)
            Image(systemName: workout.isComplete ? "checkmark.circle.fill" : "list.bullet.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(workout.isComplete ? Color.accentPrimary : Color.textTertiary)
                .frame(width: 28, height: 24)
        }
        .frame(width: 86, height: 174)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: workout.isToday ? [Color.white.opacity(0.12), Color.accentPrimary.opacity(0.06)] : [Color.white.opacity(0.055), Color.white.opacity(0.025)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(workout.isToday ? Color.accentPrimary : Color.borderSubtle, lineWidth: workout.isToday ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PlanWorkoutDayCard: View {
    var workout: WorkoutSummary

    private var tint: Color {
        switch workout.kind {
        case .tempo, .intervals, .hills: return .accentEnergy
        case .long: return .accentRecovery
        case .recovery: return .textTertiary
        default: return .accentSuccess
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.weekday)
                        .font(.labelSM)
                        .tracking(1.1)
                        .foregroundStyle(Color.textSecondary)
                    Text(workout.date)
                        .font(.headingMD)
                }
                Spacer()
                if workout.isComplete {
                    RunSmartIconMark(size: 24, tint: .accentSuccess, selected: true)
                }
            }
            Spacer(minLength: 0)
            RunSmartIconMark(size: 36, tint: tint)
                .frame(maxWidth: .infinity)
            Text(workout.title)
                .font(.bodyMD.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text(workout.distance)
                .font(.metricSM)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(14)
        .frame(width: 96, height: 180, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(workout.isToday ? tint : Color.border, lineWidth: workout.isToday ? 1.5 : 1)
        )
        .shadow(color: workout.isToday ? tint.opacity(0.24) : .clear, radius: 14)
        .opacity(workout.isComplete ? 0.64 : 1)
    }
}

private struct PlanProgressSection: View {
    var goal: GoalSummary
    var challenge: ChallengeSummary
    var trainingLoad: TrainingLoadSnapshot
    var runs: [RecordedRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassCard(cornerRadius: 20, padding: 14, glow: .accentPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Goal Aligned", trailing: goal.daysRemaining.map { "\($0)d left" })
                    Text(goal.title)
                        .font(.title2.bold())
                    Text(goal.detail)
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                    ProgressView(value: goal.progress)
                        .tint(Color.accentPrimary)
                    HStack {
                        StatusChip(text: goal.target, symbol: "flag.checkered")
                        StatusChip(text: goal.trendLabel, symbol: "chart.line.uptrend.xyaxis", tint: .accentSuccess)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ParityMetricCard(title: "Challenge", value: challenge.dayLabel, detail: challenge.title, symbol: "trophy.fill", tint: .accentAmber, values: [2, 4, 5, 7, 9, 11])
                ParityMetricCard(title: "Compliance", value: "\(trainingLoad.consistency)%", detail: "planned workouts", symbol: "checkmark.seal.fill", tint: .accentSuccess, values: [60, 72, 80, 92])
                ParityMetricCard(title: "Load", value: trainingLoad.loadLabel, detail: "ACWR \(trainingLoad.acwr)", symbol: "waveform.path.ecg", tint: .accentRecovery, values: [50, 62, 58, 72])
                ParityMetricCard(title: "Runs", value: "\(runs.count)", detail: trainingLoad.weeklyRecap, symbol: "figure.run", tint: .accentPrimary, values: [4, 6, 5, 8])
            }
        }
    }
}

private struct PlanActionGrid: View {
    var onAdd: () -> Void
    var onCoach: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PlanActionTile(title: "Add Run", detail: "Manual or synced", symbol: "plus.circle.fill", action: onAdd)
            PlanActionTile(title: "Coach", detail: "Ask about the week", symbol: "sparkles", action: onCoach)
        }
    }
}

private struct PlanActionTile: View {
    var title: String
    var detail: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ContentCard {
                HStack(spacing: 10) {
                    RunSmartIconMark(size: 38, tint: .accentPrimary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 58)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ChallengePlanCard: View {
    var challenge: ChallengeSummary
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HeroCard(accent: .accentAmber, cornerRadius: 20, padding: 14) {
                HStack(spacing: 14) {
                    OrganicProgressRing(value: challenge.progress, title: "\(Int(challenge.progress * 100))%", subtitle: "done", tint: .accentAmber)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(title: "Active Challenge", trailing: challenge.dayLabel)
                        Text(challenge.title)
                            .font(.title3.bold())
                        Text(challenge.detail)
                            .font(.callout)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    RunSmartIconMark(size: 24, tint: .textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecoveryPlanCard: View {
    var recovery: RecoverySnapshot
    var trainingLoad: TrainingLoadSnapshot

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Recovery Recommendations", trailing: trainingLoad.loadLabel)
                Text(recovery.recommendation)
                    .font(.callout)
                    .foregroundStyle(Color.textPrimary.opacity(0.86))
                HStack(spacing: 8) {
                    StatusChip(text: "Sleep \(recovery.sleep)", symbol: "moon.fill", tint: .accentMagenta)
                    StatusChip(text: "HRV \(recovery.hrv)", symbol: "heart.fill", tint: .accentSuccess)
                }
            }
        }
    }
}
