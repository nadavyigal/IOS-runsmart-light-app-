import SwiftUI

struct TodayTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: RunSmartAppSession

    @State private var recommendation = TodayRecommendation(readiness: 0, readinessLabel: "Loading", workoutTitle: "Loading workout", distance: "--", pace: "--", elevation: "--", coachMessage: "Loading your real training context.")
    @State private var messages: [CoachMessage] = []
    @State private var routes: [RouteSuggestion] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                RunSmartHeader(showLogo: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Good morning, \(session.onboardingProfile.displayName)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Your coach is ready when you are.")
                        .foregroundStyle(Color.mutedText)
                }

                HStack(alignment: .center, spacing: 16) {
                    CoachAvatar(size: 124)

                    GlassCard(cornerRadius: 18, padding: 14, glow: Color.lime) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Your AI Coach")
                            Text(recommendation.coachMessage)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.86))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button(action: { router.openCoach(context: "Today") }) {
                                Label("Talk to Coach", systemImage: "waveform")
                            }
                            .buttonStyle(NeonButtonStyle())
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ReadinessCard(recommendation: recommendation)
                    WorkoutRecommendationCard(recommendation: recommendation, route: routes.first) {
                        router.startRun()
                    }
                }

                InsightCard(
                    title: "Coach Insight",
                    message: "Your readiness is high and your consistency is paying off. This tempo session will boost your endurance and confidence.",
                    action: {
                        let w = WorkoutSummary(
                            weekday: "",
                            date: "",
                            kind: .tempo,
                            title: recommendation.workoutTitle,
                            distance: recommendation.distance,
                            detail: "",
                            isToday: true,
                            isComplete: false
                        )
                        router.open(.workoutDetail(w))
                    }
                )

                GlassCard(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Coach Conversation", trailing: "See all")
                        ForEach(messages) { message in
                            CoachBubble(message: message)
                        }
                    }
                }

                HStack(spacing: 10) {
                    SmallStatCard(title: "Weekly Progress", value: "31 / 42", unit: "km", symbol: "chart.bar.fill", tint: Color.lime)
                    SmallStatCard(title: "Streak", value: "11", unit: "days", symbol: "flame.fill", tint: .orange)
                    SmallStatCard(title: "Recovery", value: "7h 48m", unit: "sleep", symbol: "moon.fill", tint: .purple)
                    SmallStatCard(title: "HRV Status", value: "Stable", unit: "balanced", symbol: "heart", tint: .green)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            recommendation = await services.todayRecommendation()
            messages = await services.recentMessages()
            routes = await services.routeSuggestions()
        }
    }
}

private struct ReadinessCard: View {
    var recommendation: TodayRecommendation

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 16, glow: Color.lime) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text("READINESS")
                    Image(systemName: "info.circle")
                }
                .font(.caption.bold())
                .foregroundStyle(Color.mutedText)
                Text("\(recommendation.readiness)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text(recommendation.readinessLabel)
                    .foregroundStyle(Color.electricGreen)
                Spacer(minLength: 0)
                ProgressRing(value: Double(recommendation.readiness) / 100)
                    .frame(width: 96, height: 96)
                    .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 260, alignment: .top)
        }
    }
}

private struct WorkoutRecommendationCard: View {
    var recommendation: TodayRecommendation
    var route: RouteSuggestion?
    var action: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 18, padding: 16, glow: Color.lime) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Coach Recommends")
                Text(recommendation.workoutTitle)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(recommendation.distance)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    MetricPill(symbol: "stopwatch", text: recommendation.pace)
                    MetricPill(symbol: "mountain.2", text: recommendation.elevation)
                }
                .lineLimit(1)
                RouteMapView(points: route?.points ?? [], title: route?.name)
                    .frame(height: 76)
                Spacer(minLength: 0)
                Button(action: action) {
                    Label("Start Workout", systemImage: "play.fill")
                }
                .buttonStyle(NeonButtonStyle())
            }
            .frame(minHeight: 260, alignment: .top)
        }
    }
}

struct InsightCard: View {
    var title: String
    var message: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.lime)
                        .padding(14)
                        .background(Color.lime.opacity(0.16))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(title: title)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.76))
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
            if message.isUser { Spacer(minLength: 38) } else { CoachAvatar(size: 28) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(message.isUser ? Color.lime.opacity(0.12) : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(message.time)
                    .font(.caption2)
                    .foregroundStyle(Color.mutedText)
            }
            if message.isUser { CoachAvatar(size: 28) } else { Spacer(minLength: 38) }
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
        GlassCard(cornerRadius: 14, padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(1)
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MiniRouteView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.22))
            Path { path in
                path.move(to: CGPoint(x: 12, y: 58))
                path.addCurve(to: CGPoint(x: 72, y: 40), control1: CGPoint(x: 28, y: 48), control2: CGPoint(x: 44, y: 42))
                path.addCurve(to: CGPoint(x: 132, y: 20), control1: CGPoint(x: 98, y: 40), control2: CGPoint(x: 112, y: 30))
                path.addLine(to: CGPoint(x: 148, y: 8))
            }
            .stroke(Color.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Circle().fill(Color.lime).frame(width: 10, height: 10).offset(x: 58, y: -22)
        }
    }
}
