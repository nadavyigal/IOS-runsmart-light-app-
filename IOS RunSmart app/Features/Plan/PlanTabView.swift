import SwiftUI

struct PlanTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var weekWorkouts: [WorkoutSummary] = []
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
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return (month, month)
        }
        let end = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        return (interval.start, end)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    PlanBriefingCard(
                        name: session.onboardingProfile.displayName,
                        goal: goal,
                        recovery: recovery,
                        onCoach: { router.openCoach(context: "Plan") }
                    )

                    SegmentedPillPicker(values: PlanViewMode.allCases, selection: $viewMode) { $0.rawValue }

                    switch viewMode {
                    case .week:
                        PlanWeekSection(workouts: weekWorkouts, weekRange: weekRangeLabel) { workout in
                            navPath.append(.workoutDetail(workout))
                        }
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
                    case .progress:
                        PlanProgressSection(
                            goal: goal,
                            challenge: challenge,
                            trainingLoad: trainingLoad,
                            runs: recentRuns
                        )
                    }

                    PlanActionGrid(
                        onAdd: { router.open(.addActivity) },
                        onAdjust: { router.open(.goalWizard) },
                        onChallenges: { navPath.append(.challenges) },
                        onCoach: { router.openCoach(context: "Plan") }
                    )

                    ChallengePlanCard(challenge: challenge) {
                        navPath.append(.challenges)
                    }

                    RecoveryPlanCard(recovery: recovery, trainingLoad: trainingLoad)

                    RunTrendChartCard(runs: recentRuns)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SecondaryDestination.self) { destination in
                SecondaryFlowView(destination: destination)
            }
        }
        .task {
            async let weekTask = services.weeklyPlan()
            async let runsTask = services.recentRuns()
            async let goalTask = services.activeGoal()
            async let challengeTask = services.activeChallenge()
            async let recoveryTask = services.recoverySnapshot()
            async let loadTask = services.trainingLoadSnapshot()
            (weekWorkouts, recentRuns, goal, challenge, recovery, trainingLoad) = await (
                weekTask, runsTask, goalTask, challengeTask, recoveryTask, loadTask
            )
        }
        .task(id: displayedMonth) {
            isLoadingMonthWorkouts = true
            let (startDate, endDate) = monthBounds(for: displayedMonth)
            let loaded = await services.planWorkouts(from: startDate, to: endDate)
            workoutsByDate = Dictionary(
                loaded.map { w in (ISO8601DateFormatter.shortDate.string(from: w.scheduledDate), w) },
                uniquingKeysWith: { first, _ in first }
            )
            isLoadingMonthWorkouts = false
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Plan")
                    .font(.headingLG)
                Text(weekRangeLabel)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button { router.open(.goalWizard) } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

private enum PlanViewMode: String, CaseIterable, Hashable, Identifiable {
    case week = "Week"
    case month = "Month"
    case progress = "Progress"
    var id: String { rawValue }
}

private struct PlanBriefingCard: View {
    var name: String
    var goal: GoalSummary
    var recovery: RecoverySnapshot
    var onCoach: () -> Void

    var body: some View {
        HeroCard(accent: .accentPrimary, cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    CoachAvatar(size: 88, showBolt: true)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "AI Coach Briefing")
                        Text("Strong week ahead\(name.isEmpty ? "" : ", \(name)"). Recovery is \(recovery.hrv.lowercased()) and the plan is aligned to \(goal.title.lowercased()).")
                            .font(.system(size: 18, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        StatusChip(text: "Focus: \(goal.trendLabel)", symbol: "target", tint: .accentPrimary)
                    }
                }

                Button(action: onCoach) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentPrimary)
                        Text("Ask Coach anything...")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(12)
                    .background(Color.shimmer)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
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
            }
        }
    }
}

struct WorkoutDayCard: View {
    var workout: WorkoutSummary

    var body: some View {
        VStack(spacing: 8) {
            Text(workout.weekday)
                .font(.caption2.bold())
                .foregroundStyle(Color.textSecondary)
            Text(workout.date)
                .font(.title3.weight(workout.isToday ? .bold : .semibold))
            Image(systemName: workout.kind.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(workout.isToday ? Color.accentPrimary : Color.accentSuccess.opacity(0.78))
            Text(workout.title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 30, alignment: .top)
            Text(workout.distance)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 0)
            Image(systemName: workout.isComplete ? "checkmark.circle.fill" : "text.bubble")
                .font(.caption.bold())
                .foregroundStyle(workout.isComplete ? Color.accentPrimary : Color.textTertiary)
        }
        .frame(width: 76, height: 152)
        .padding(.vertical, 10)
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentSuccess)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: workout.kind.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(tint)
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
    var onAdjust: () -> Void
    var onChallenges: () -> Void
    var onCoach: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PlanActionTile(title: "Add Run", detail: "Manual or synced", symbol: "plus.circle.fill", action: onAdd)
            PlanActionTile(title: "Adjust Plan", detail: "Keep load safe", symbol: "slider.horizontal.3", action: onAdjust)
            PlanActionTile(title: "Challenges", detail: "Sync to plan", symbol: "trophy.fill", action: onChallenges)
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
                    Image(systemName: symbol)
                        .font(.headline)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(width: 38, height: 38)
                        .background(Color.accentPrimary.opacity(0.12))
                        .clipShape(Circle())
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
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.textSecondary)
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
