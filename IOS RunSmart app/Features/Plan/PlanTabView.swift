import SwiftUI

struct PlanTabView<Services: PlanProviding>: View {
    let services: Services
    var openCoach: () -> Void
    var openSecondary: (String) -> Void

    @State private var workouts = RunSmartPreviewData.workouts

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                RunSmartHeader(title: "Plan")

                GlassCard(glow: Color.lime) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            CoachAvatar(size: 96)
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(title: "AI Coach Briefing")
                                Text("Strong week ahead, Alex. Your recovery is on point and last week's tempo looked solid. We're building fitness with a tempo focus midweek and a steady long run on Sunday.")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.86))
                                Text("Focus: Tempo • Build Aerobic Endurance")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.lime)
                            }
                        }
                        Button(action: openCoach) {
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
                    Text("Apr 28 – May 4")
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedText)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workouts) { workout in
                            WorkoutDayCard(workout: workout)
                                .onTapGesture { openSecondary(workout.title) }
                        }
                    }
                    .padding(.horizontal, 2)
                }

                GlassCard(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("May Overview")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.left")
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.white.opacity(0.86))

                        HStack {
                            ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                                Text(day)
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.mutedText)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        HStack {
                            ForEach(28...34, id: \.self) { number in
                                VStack(spacing: 7) {
                                    Text(number <= 30 ? "\(number)" : "\(number - 30)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(number == 30 ? Color.black : Color.white)
                                        .frame(width: 25, height: 25)
                                        .background(number == 30 ? Color.lime : Color.clear)
                                        .clipShape(Circle())
                                    Circle()
                                        .fill(number == 30 || number == 28 || number == 29 ? Color.lime : Color.purple)
                                        .frame(width: 4, height: 4)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                GlassCard(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "This Week from Your Coach", trailing: "View all")
                        ForEach(workouts.filter { $0.kind == .tempo || $0.kind == .long }) { workout in
                            PlanCoachRow(workout: workout)
                        }
                    }
                }

                InsightCard(
                    title: "Coach Notes",
                    message: "Great consistency lately. Your aerobic base is improving. Keep stacking quality weeks.",
                    action: { openSecondary("Plan Adjustment") }
                )
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            workouts = await services.weeklyPlan()
        }
    }
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
                Text(workout.kind == .tempo ? "We're targeting threshold. Keep the effort controlled and finish strong." : "Build endurance, not speed. Stay easy, fuel well, and enjoy the rhythm.")
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
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
