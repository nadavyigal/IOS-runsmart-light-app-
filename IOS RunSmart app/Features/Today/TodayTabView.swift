import SwiftUI

struct TodayTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var recommendation = TodayRecommendation.placeholder
    @State private var routes: [RouteSuggestion] = []

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Hey"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

                ReadinessHeroView(recommendation: recommendation) {
                    router.open(.recoveryDashboard)
                }
                .runSmartStaggeredAppear(index: 0)

                TodayWorkoutCard(
                    recommendation: recommendation,
                    route: routes.first,
                    onStart: { router.startRun() },
                    onModify: { router.open(.planAdjustment) },
                    onSkip: { router.open(.reschedule(todayWorkout)) },
                    onRoute: { router.open(.routeSelector) }
                )
                .runSmartStaggeredAppear(index: 1)

                InsightCard(
                    title: "Coach Insight",
                    message: recommendation.coachMessage,
                    action: { router.openCoach(context: "Today") }
                )
                .runSmartStaggeredAppear(index: 2)

                quickStats
                    .runSmartStaggeredAppear(index: 3)

                WeatherConditionsCard()
                    .runSmartStaggeredAppear(index: 4)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            async let recommendationTask = services.todayRecommendation()
            async let routesTask = services.routeSuggestions()
            (recommendation, routes) = await (recommendationTask, routesTask)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(greeting), \(displayName)")
                    .font(.headingLG)
                    .foregroundStyle(Color.textPrimary)
                Text("Your next smart decision is ready.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button { router.open(.morningCheckin) } label: {
                Image(systemName: "checklist.checked")
                    .font(.headline)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
            RunSmartHeader(title: nil)
                .frame(width: 88)
        }
    }

    private var quickStats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SmallStatCard(title: "Weekly km", value: recommendation.weeklyProgress, unit: "", symbol: "chart.bar.fill", tint: .accentPrimary)
                SmallStatCard(title: "Streak", value: recommendation.streak, unit: "", symbol: "flame.fill", tint: .accentEnergy)
                SmallStatCard(title: "Recovery", value: recommendation.recovery, unit: "sleep", symbol: "moon.fill", tint: .accentRecovery)
                SmallStatCard(title: "HRV", value: recommendation.hrv, unit: "", symbol: "heart", tint: .accentHeart)
            }
            .padding(.vertical, 2)
        }
    }

    private var todayWorkout: WorkoutSummary {
        WorkoutSummary(
            weekday: "",
            date: "",
            kind: .tempo,
            title: recommendation.workoutTitle,
            distance: recommendation.distance,
            detail: recommendation.pace,
            isToday: true,
            isComplete: false
        )
    }

    private var displayName: String {
        let name = session.onboardingProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Runner" : name
    }
}

struct InsightCard: View {
    var title: String
    var message: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ContentCard {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Color.black)
                        .frame(width: 42, height: 42)
                        .background(Color.accentPrimary, in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(title: title)
                        Text(message)
                            .font(.bodyMD)
                            .foregroundStyle(Color.textPrimary.opacity(0.88))
                            .lineLimit(3)
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

struct CoachBubble: View {
    var message: CoachMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 44) } else { CoachAvatar(size: 30) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.bodyMD)
                    .foregroundStyle(message.isUser ? Color.black : Color.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.accentPrimary : Color.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(message.isUser ? .clear : Color.border)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(message.time)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            if message.isUser { CoachAvatar(size: 30) } else { Spacer(minLength: 44) }
        }
    }
}

struct SmallStatCard: View {
    var title: String
    var value: String
    var unit: String
    var symbol: String
    var tint: Color

    var body: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title.uppercased())
                        .font(.labelSM)
                        .tracking(1.1)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit.isEmpty ? " " : unit)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 104, alignment: .leading)
        }
    }
}

struct MiniRouteView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.22))
            Path { path in
                path.move(to: CGPoint(x: 12, y: 58))
                path.addCurve(to: CGPoint(x: 72, y: 40), control1: CGPoint(x: 28, y: 48), control2: CGPoint(x: 44, y: 42))
                path.addCurve(to: CGPoint(x: 132, y: 20), control1: CGPoint(x: 98, y: 40), control2: CGPoint(x: 112, y: 30))
                path.addLine(to: CGPoint(x: 148, y: 8))
            }
            .stroke(Color.accentPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Circle().fill(Color.accentPrimary).frame(width: 10, height: 10).offset(x: 58, y: -22)
        }
    }
}
