import SwiftUI

struct TodayTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var recommendation = TodayRecommendation.placeholder
    @State private var routes: [RouteSuggestion] = []
    @State private var nextWorkouts: [WorkoutSummary] = []
    @State private var runReports: [RunReportSummary] = []
    @State private var coachMessages: [CoachMessage] = []

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
            VStack(alignment: .leading, spacing: 14) {
                header

                TodayCoachHeroCard(
                    message: recommendation.coachMessage,
                    onCoach: { router.openCoach(context: "Today") }
                )
                .runSmartStaggeredAppear(index: 0)

                TodayCommandCenter(
                    recommendation: recommendation,
                    route: routes.first,
                    onReadiness: { router.open(.recoveryDashboard) },
                    onStart: { router.startRun(with: todayWorkout) },
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

                if !coachMessages.isEmpty {
                    TodayConversationPreview(messages: coachMessages) {
                        router.openCoach(context: "Today")
                    }
                    .runSmartStaggeredAppear(index: 3)
                }

                quickStats
                    .runSmartStaggeredAppear(index: 4)

                if !nextWorkouts.isEmpty {
                    UpcomingRunsCard(workouts: nextWorkouts) { workout in
                        router.open(.workoutDetail(workout))
                    }
                    .runSmartStaggeredAppear(index: 5)
                }

                if !runReports.isEmpty {
                    RecentRunReportsCard(reports: runReports) { report in
                        if let detail = report.toDetail() {
                            router.open(.runReportDetail(detail))
                        }
                    }
                    .runSmartStaggeredAppear(index: 6)
                }

                WeatherConditionsCard()
                    .runSmartStaggeredAppear(index: 7)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanDidChange)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        async let recommendationTask = services.todayRecommendation()
        async let routesTask = services.routeSuggestions()
        async let nextWorkoutsTask = services.nextWorkouts(limit: 3)
        async let reportsTask = services.latestRunReports(limit: 3)
        async let messagesTask = services.recentMessages()
        let (rec, rts, nw, reports, messages) = await (recommendationTask, routesTask, nextWorkoutsTask, reportsTask, messagesTask)
        recommendation = rec
        routes = rts
        nextWorkouts = nw
        runReports = reports
        coachMessages = messages
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            RunSmartTopBar(title: nil, showBrand: true)
                .overlay(alignment: .trailing) {
                    Button { router.open(.morningCheckin) } label: {
                        Image(systemName: "checklist.checked")
                            .font(.headline)
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -92)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text("\(greeting), \(displayName)")
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Your coach is ready when you are.")
                    .font(.bodyLG)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var quickStats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                TodayMiniStatCard(title: "Weekly Progress", value: recommendation.weeklyProgress, unit: "km", symbol: "chart.bar.fill", tint: .accentPrimary, values: [0.18, 0.35, 0.55, 0.78, 0.62, 0.44, 0.70])
                TodayMiniStatCard(title: "Streak", value: recommendation.streak, unit: "days", symbol: "flame.fill", tint: .accentAmber, values: [0.35, 0.35, 0.35, 0.35, 0.35])
                TodayMiniStatCard(title: "Recovery", value: recommendation.recovery, unit: "sleep", symbol: "moon.fill", tint: .accentMagenta, values: [0.20, 0.34, 0.46, 0.62, 0.70, 0.55, 0.48])
                TodayMiniStatCard(title: "HRV Status", value: recommendation.hrv, unit: "balanced", symbol: "heart", tint: .accentSuccess, values: [0.40, 0.52, 0.46, 0.72, 0.58, 0.76, 0.62])
            }
            .padding(.vertical, 2)
        }
    }

    private var todayWorkout: WorkoutSummary {
        if let real = nextWorkouts.first(where: { $0.isToday }) ?? nextWorkouts.first {
            return real
        }
        return WorkoutSummary(
            id: UUID(),
            scheduledDate: Date(),
            planID: nil,
            weekday: "",
            date: "",
            kind: .easy,
            title: recommendation.workoutTitle,
            distance: recommendation.distance,
            detail: recommendation.coachMessage,
            isToday: true,
            isComplete: false
        )
    }

    private var displayName: String {
        let name = session.onboardingProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Runner" : name
    }
}

private struct TodayCoachHeroCard: View {
    var message: String
    var onCoach: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CoachAvatar(size: 118, showBolt: false)
                .padding(.leading, 8)

            RunSmartPanel(cornerRadius: 20, padding: 14, accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Your AI Coach")
                    Text(message)
                        .font(.bodyLG.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onCoach) {
                        HStack {
                            Text("Talk to Coach")
                                .font(.buttonLabel)
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.title3.weight(.bold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.accentPrimary.opacity(0.35), radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TodayCommandCenter: View {
    var recommendation: TodayRecommendation
    var route: RouteSuggestion?
    var onReadiness: () -> Void
    var onStart: () -> Void
    var onModify: () -> Void
    var onSkip: () -> Void
    var onRoute: () -> Void

    private var readinessTint: Color {
        switch recommendation.readiness {
        case 80...100: return .accentSuccess
        case 55..<80: return .accentPrimary
        default: return .accentHeart
        }
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 0, accent: .accentPrimary) {
            HStack(spacing: 0) {
                Button(action: onReadiness) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Readiness", trailing: "Info")
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(recommendation.readiness)")
                                .font(.displayXL)
                                .monospacedDigit()
                                .displayTightTracking()
                            Text(recommendation.readinessLabel)
                                .font(.bodyMD.weight(.semibold))
                                .foregroundStyle(readinessTint)
                        }
                        ZStack {
                            ProgressRing(value: Double(recommendation.readiness) / 100, lineWidth: 12, icon: "figure.run", tint: readinessTint)
                            .frame(width: 112, height: 112)
                        }
                    }
                    .frame(width: 132, alignment: .topLeading)
                    .frame(minHeight: 248, alignment: .topLeading)
                    .padding(16)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.border.opacity(0.8))
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach Recommends")
                    Text(recommendation.workoutTitle)
                        .font(.headingLG)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("- \(recommendation.distance)")
                        .font(.headingMD)

                    HStack(spacing: 14) {
                        MetricPill(symbol: "timer", text: recommendation.pace)
                        MetricPill(symbol: "mountain.2", text: recommendation.elevation)
                    }

                    Button(action: onRoute) {
                        RunSmartRoutePreview(title: route?.name, height: 84)
                    }
                    .buttonStyle(.plain)

                    Button(action: onStart) {
                        HStack {
                            Text("Start Workout")
                                .font(.buttonLabel)
                            Spacer()
                            Image(systemName: "play.fill")
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.accentPrimary.opacity(0.35), radius: 14)
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Button("Modify", action: onModify)
                        Spacer()
                        Button("Skip", action: onSkip)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(16)
            }
        }
    }
}

private struct TodayConversationPreview: View {
    var messages: [CoachMessage]
    var onTap: () -> Void

    private var visibleMessages: [CoachMessage] {
        Array(messages.prefix(2))
    }

    var body: some View {
        Button(action: onTap) {
            RunSmartPanel(cornerRadius: 20, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(title: "Coach Conversation")
                        Text("See all")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentPrimary)
                    }
                    ForEach(visibleMessages) { message in
                        CoachBubble(message: message)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TodayMiniStatCard: View {
    var title: String
    var value: String
    var unit: String
    var symbol: String
    var tint: Color
    var values: [CGFloat]

    var body: some View {
        RunSmartPanel(cornerRadius: 16, padding: 12, accent: nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.labelSM)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .frame(height: 28, alignment: .topLeading)
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                MetricBars(values: values, tint: tint)
            }
            .frame(width: 104, height: 138, alignment: .topLeading)
        }
    }
}

struct RecentRunReportsCard: View {
    var reports: [RunReportSummary]
    var onTap: (RunReportSummary) -> Void

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Recent Run Reports")
                ForEach(reports) { report in
                    Button { onTap(report) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.body)
                                .foregroundStyle(Color.accentPrimary)
                                .frame(width: 32, height: 32)
                                .background(Color.surfaceElevated, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(report.title)
                                    .font(.bodyMD.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text("\(report.dateLabel) - \(report.distance) - \(report.pace)")
                                    .font(.labelSM)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Text(report.insight)
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if report.score > 0 {
                                Text("\(report.score)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.black)
                                    .frame(width: 30, height: 30)
                                    .background(Color.accentPrimary, in: Circle())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension RunReportSummary {
    func toDetail() -> RunReportDetail? {
        guard let runID else { return nil }
        return RunReportDetail(
            id: id,
            runID: runID,
            title: title,
            dateLabel: dateLabel,
            source: source.isEmpty ? "RunSmart" : source,
            distance: distance,
            duration: duration,
            averagePace: pace,
            averageHeartRate: averageHeartRate,
            coachScore: score > 0 ? score : nil,
            notes: CoachRunNotes(
                summary: insight,
                effort: "Open the source activity to regenerate detailed effort notes if needed.",
                recovery: "No recovery note stored.",
                nextSessionNudge: "No next-run recommendation stored."
            ),
            structuredNextWorkout: nil
        )
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

struct UpcomingRunsCard: View {
    var workouts: [WorkoutSummary]
    var onTap: (WorkoutSummary) -> Void

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Next Runs")
                ForEach(workouts) { workout in
                    Button { onTap(workout) } label: {
                        UpcomingRunRow(workout: workout)
                    }
                    .buttonStyle(.plain)
                    if workout.id != workouts.last?.id {
                        Divider().background(Color.border)
                    }
                }
            }
        }
    }
}

struct UpcomingRunRow: View {
    var workout: WorkoutSummary

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: workout.scheduledDate)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .font(.body)
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 32, height: 32)
                .background(Color.surfaceElevated, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 6) {
                    Text(dateLabel)
                        .font(.labelSM)
                        .foregroundStyle(Color.textSecondary)
                    Text("-")
                        .foregroundStyle(Color.textTertiary)
                    Text(workout.distance)
                        .font(.labelSM)
                        .foregroundStyle(Color.textSecondary)
                    if let pace = StructuredWorkoutFactory.derivedPaceLabel(workout: workout) {
                        Text("-")
                            .foregroundStyle(Color.textTertiary)
                        Text(pace)
                            .font(.labelSM)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                if !workout.detail.isEmpty {
                    Text(workout.detail)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }
}
