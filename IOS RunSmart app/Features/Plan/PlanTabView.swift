import SwiftUI

struct PlanTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var workouts: [WorkoutSummary] = []
    @State private var recentRuns: [RecordedRun] = []
    @State private var navPath: [SecondaryDestination] = []

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: weekEnd))"
    }

    private var planSummary: String {
        let goal = session.onboardingProfile.goal
        let days = session.onboardingProfile.weeklyRunDays
        let goalText = goal.isEmpty ? "Build consistency" : goal
        return "Goal: \(goalText) · \(days) runs/week. Sync Garmin or record GPS runs to sharpen each weekly update."
    }

    private var weekOverviewTitle: String {
        let days = currentWeekDays
        guard let first = days.first, let last = days.last else { return "Week Overview" }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = calendar.isDate(first, equalTo: last, toGranularity: .month) ? "MMMM 'Overview'" : "MMM-MMM 'Overview'"

        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return formatter.string(from: first)
        }
        return "\(DateFormatter.monthAbbreviation.string(from: first))-\(DateFormatter.monthAbbreviation.string(from: last)) Overview"
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    RunSmartHeader(title: "Plan")

                    GlassCard(glow: Color.lime) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 16) {
                                CoachAvatar(size: 96)
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionLabel(title: "Your Plan")
                                    Text(planSummary)
                                        .font(.body)
                                        .foregroundStyle(.white.opacity(0.86))
                                }
                            }
                            Button(action: { router.openCoach(context: "Plan") }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.lime)
                                    Text("Ask Coach anything...")
                                        .foregroundStyle(Color.mutedText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.mutedText)
                                }
                                .padding(12)
                                .background(.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("This Week")
                            .font(.headline)
                        Spacer()
                        Text(weekRangeLabel)
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedText)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(workouts) { workout in
                                WorkoutDayCard(workout: workout)
                                    .onTapGesture { navPath.append(.workoutDetail(workout)) }
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    Button(action: { router.open(.addActivity) }) {
                        Label("Add Run", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(NeonButtonStyle())

                    MonthlyScheduleCard(workouts: workouts) { workout in
                        navPath.append(.workoutDetail(workout))
                    }

                    RunTrendChartCard(runs: recentRuns)

                    GlassCard(cornerRadius: 18, padding: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(weekOverviewTitle)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.left")
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(.white.opacity(0.86))

                            HStack {
                                ForEach(Array(currentWeekDays.enumerated()), id: \.offset) { _, date in
                                    Text(DateFormatter.weekdayInitial.string(from: date))
                                        .font(.caption2.bold())
                                        .foregroundStyle(Color.mutedText)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            HStack {
                                ForEach(Array(currentWeekDays.enumerated()), id: \.offset) { _, date in
                                    let workout = workout(on: date)
                                    let isToday = Calendar.current.isDateInToday(date)
                                    VStack(spacing: 7) {
                                        Text(DateFormatter.dayNumber.string(from: date))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isToday ? Color.black : Color.white)
                                            .frame(width: 25, height: 25)
                                            .background(isToday ? Color.lime : Color.clear)
                                            .clipShape(Circle())
                                        if let workout {
                                            Circle()
                                                .fill(workout.isComplete ? Color.lime : Color.purple)
                                                .frame(width: 4, height: 4)
                                        } else {
                                            Circle()
                                                .fill(Color.clear)
                                                .frame(width: 4, height: 4)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }

                    GlassCard(cornerRadius: 18, padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Run Breakthrough", trailing: "This week")
                            BreakthroughFocusRow(
                                title: breakthroughTitle,
                                detail: breakthroughDetail,
                                symbol: "sparkles"
                            )
                            ForEach(workouts.filter { $0.kind == .tempo || $0.kind == .long }) { workout in
                                PlanCoachRow(workout: workout)
                                    .onTapGesture { navPath.append(.workoutDetail(workout)) }
                            }
                        }
                    }

                    Button(action: { navPath.append(.challenges) }) {
                        GlassCard(cornerRadius: 18, padding: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "trophy.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.lime)
                                    .padding(12)
                                    .background(Color.lime.opacity(0.15))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    SectionLabel(title: "Challenges")
                                    Text("Adopt a challenge to stay motivated and build consistency.")
                                        .font(.callout)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.mutedText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
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

    private func workout(on date: Date) -> WorkoutSummary? {
        let calendar = Calendar.current
        let day = String(calendar.component(.day, from: date))
        return workouts.first { $0.date == day }
    }

    private var breakthroughTitle: String {
        if recentRuns.isEmpty { return "Start your first logged week" }
        if let longest = recentRuns.max(by: { $0.distanceMeters < $1.distanceMeters }) {
            return "Longest run to beat: \(String(format: "%.1f", longest.distanceMeters / 1_000)) km"
        }
        return "Build consistency"
    }

    private var breakthroughDetail: String {
        if recentRuns.isEmpty {
            return "Add a run or record GPS to unlock trend coaching and better schedule adjustments."
        }
        let weeklyKm = recentRuns
            .filter { Calendar.current.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0.0) { $0 + $1.distanceMeters / 1_000 }
        return String(format: "You have %.1f km this week. Keep the next quality run controlled and let the long run do the work.", weeklyKm)
    }
}

private extension DateFormatter {
    static let weekdayInitial: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static let monthAbbreviation: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

struct WorkoutDayCard: View {
    var workout: WorkoutSummary

    var body: some View {
        VStack(spacing: 7) {
            Text(workout.weekday)
                .font(.caption2.bold())
                .foregroundStyle(Color.mutedText)
            Text(workout.date)
                .font(.title3.weight(workout.isToday ? .bold : .semibold))
            Image(systemName: workout.kind.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(workout.isToday ? Color.lime : Color.green.opacity(0.68))
            Text(workout.title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)
            Text(workout.distance)
                .font(.caption2)
                .foregroundStyle(Color.mutedText)
            Spacer(minLength: 2)
            HStack(spacing: 5) {
                if workout.isToday {
                    Capsule()
                        .fill(Color.lime)
                        .frame(width: 24, height: 5)
                }
                Image(systemName: workout.isComplete ? "checkmark" : "text.bubble")
                    .font(.caption.bold())
                    .foregroundStyle(workout.isComplete ? Color.lime : Color.mutedText)
            }
        }
        .frame(width: 70, height: 142)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: workout.isToday ? [Color.white.opacity(0.12), Color.lime.opacity(0.045)] : [Color.white.opacity(0.065), Color.white.opacity(0.025)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(workout.isToday ? Color.lime : Color.hairline, lineWidth: workout.isToday ? 1.5 : 1)
        )
        .shadow(color: workout.isToday ? Color.lime.opacity(0.24) : .clear, radius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PlanCoachRow: View {
    var workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .font(.title2.bold())
                .foregroundStyle(Color.lime)
                .frame(width: 44, height: 44)
                .background(Color.lime.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(workout.weekday.capitalized): \(workout.title)")
                    .font(.headline)
                if !workout.detail.isEmpty {
                    Text(workout.detail)
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                } else {
                    Text(workout.distance)
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                }
            }
            Spacer()
            Image(systemName: "text.bubble")
                .foregroundStyle(Color.mutedText)
        }
        .padding(10)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct BreakthroughFocusRow: View {
    var title: String
    var detail: String
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.bold())
                .foregroundStyle(Color.black)
                .frame(width: 48, height: 48)
                .background(Color.lime)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.lime.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.lime.opacity(0.22)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
