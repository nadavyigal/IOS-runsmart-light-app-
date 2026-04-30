import SwiftUI

struct PlanTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var workouts: [WorkoutSummary] = []
    @State private var recentRuns: [RecordedRun] = []
    @State private var navPath: [SecondaryDestination] = []
    @State private var calendarMode = "Week"

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "" }
        return "\(DateFormatter.monthDay.string(from: start)) - \(DateFormatter.monthDay.string(from: end))"
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    planSummary
                        .runSmartStaggeredAppear(index: 0)

                    weekView
                        .runSmartStaggeredAppear(index: 1)

                    modeToggle

                    if calendarMode == "Month" {
                        MonthlyScheduleCard(workouts: workouts) { workout in
                            navPath.append(.workoutDetail(workout))
                        }
                        .runSmartStaggeredAppear(index: 2)
                    }

                    RunTrendChartCard(runs: recentRuns)
                        .runSmartStaggeredAppear(index: 3)

                    breakthroughFocus
                        .runSmartStaggeredAppear(index: 4)

                    challengeEntry
                        .runSmartStaggeredAppear(index: 5)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SecondaryDestination.self) { destination in
                SecondaryFlowView(destination: destination)
            }
        }
        .task {
            async let workoutsTask = services.weeklyPlan()
            async let runsTask = services.recentRuns()
            (workouts, recentRuns) = await (workoutsTask, runsTask)
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

    private var planSummary: some View {
        ContentCard {
            HStack(spacing: 12) {
                Text(session.onboardingProfile.goal.isEmpty ? "10K" : session.onboardingProfile.goal)
                    .font(.labelLG)
                    .tracking(1.2)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.accentPrimary, in: Capsule())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Week 4 of 12")
                        .font(.headingMD)
                    Text("\(session.onboardingProfile.weeklyRunDays) runs this week · adaptive load")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var weekView: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Week view", trailing: "Tap workout")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(workouts) { workout in
                        PlanWorkoutDayCard(workout: workout)
                            .onTapGesture { navPath.append(.workoutDetail(workout)) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(["Week", "Month"], id: \.self) { mode in
                Button { calendarMode = mode } label: {
                    Text(mode.uppercased())
                        .font(.labelSM)
                        .tracking(1.2)
                        .foregroundStyle(calendarMode == mode ? Color.black : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(calendarMode == mode ? Color.accentPrimary : Color.surfaceElevated)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var breakthroughFocus: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Breakthrough focus", trailing: "This week")
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.black)
                        .frame(width: 46, height: 46)
                        .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(breakthroughTitle)
                            .font(.headingMD)
                        Text(breakthroughDetail)
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    private var challengeEntry: some View {
        Button { navPath.append(.challenges) } label: {
            ContentCard {
                HStack(spacing: 14) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(width: 46, height: 46)
                        .background(Color.accentPrimary.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Challenges")
                            .font(.headingMD)
                        Text("Adopt a challenge to add accountability.")
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
    }

    private var breakthroughTitle: String {
        if recentRuns.isEmpty { return "Start your first logged week" }
        let longest = recentRuns.max(by: { $0.distanceMeters < $1.distanceMeters })
        return String(format: "Longest run to beat: %.1f km", (longest?.distanceMeters ?? 0) / 1_000)
    }

    private var breakthroughDetail: String {
        let weeklyKm = recentRuns
            .filter { Calendar.current.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0.0) { $0 + $1.distanceMeters / 1_000 }
        return String(format: "%.1f km logged this week. Keep quality controlled and let the long run build endurance.", weeklyKm)
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

private extension DateFormatter {
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
