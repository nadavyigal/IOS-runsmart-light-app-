import SwiftUI

struct ProfileTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var runner = RunnerProfile(name: "RunSmart Runner", goal: "Loading", streak: "--", level: "--", totalRuns: 0, totalDistance: 0, totalTime: "0h 0m")
    @State private var achievements: [Achievement] = []
    @State private var deviceStatuses: [ConnectedDeviceStatus] = []
    @State private var runReports: [RunReportSummary] = []
    @State private var recentRuns: [RecordedRun] = []
    @State private var challenge: ChallengeSummary = .loading
    @State private var navPath: [SecondaryDestination] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    RunSmartTopBar(title: "Profile", showSettings: true) {
                        navPath.append(.account)
                    }

                    identityHeader
                    statsBar
                    trainingDataCard
                    coachSparkCard
                    coachSettingsGrid
                    optimizationCards
                    achievementsGallery
                    connectedSection
                    if !runReports.isEmpty {
                        RecentRunReportsCard(reports: runReports) { report in
                            if let detail = report.toDetail() {
                                navPath.append(.runReportDetail(detail))
                            }
                        }
                    }
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 140)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SecondaryDestination.self) { destination in
                SecondaryFlowView(destination: destination)
            }
        }
        .task {
            await loadProfileData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            Task { await loadProfileData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanDidChange)) { _ in
            Task { await loadProfileData() }
        }
    }

    private func loadProfileData() async {
        async let runnerTask = services.runnerProfile()
        async let achievementsTask = services.achievements()
        async let statusesTask = services.deviceStatuses()
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
    }

    private var identityHeader: some View {
        HStack(spacing: 18) {
            CoachAvatar(size: 118, showBolt: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(runner.name)
                        .font(.displayMD)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 7) {
                        Text(runner.goal)
                        Circle()
                            .fill(Color.accentPrimary)
                            .frame(width: 6, height: 6)
                        Text(runner.streak)
                    }
                    .font(.bodyLG.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
        }
    }

    private var statsBar: some View {
        RunSmartPanel(cornerRadius: 18, padding: 0) {
            HStack(spacing: 0) {
                ProfileStat(title: "Level", value: levelNumber, detail: runner.level)
                Divider().background(Color.border)
                ProfileStat(title: "Total Runs", value: "\(runner.totalRuns)", detail: "")
                Divider().background(Color.border)
                ProfileStat(title: "Total Distance", value: "\(runner.totalDistance)", detail: "km")
                Divider().background(Color.border)
                ProfileStat(title: "Total Time", value: runner.totalTime, detail: "")
            }
            .padding(.vertical, 14)
        }
    }

    private var coachSparkCard: some View {
        RunSmartPanel(cornerRadius: 22, padding: 18, accent: .accentPrimary) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Your AI Coach")
                    HStack(spacing: 8) {
                        Text("Coach Spark")
                            .font(.displayMD)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                        StatusChip(text: "AI", tint: .accentPrimary)
                    }
                    Text("Adaptive. Motivating. Data-driven.")
                        .font(.bodyLG)
                        .foregroundStyle(Color.textSecondary)
                    Text("I analyze your data, adapt your plan in real-time, and coach you to be your best.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)

                    Button { router.openCoach(context: "Profile") } label: {
                        Label("Chat with Coach", systemImage: "text.bubble")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(Color.accentPrimary.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(Color.accentPrimary.opacity(0.42), lineWidth: 3)
                        .frame(width: 122, height: 122)
                        .shadow(color: Color.accentPrimary.opacity(0.45), radius: 24)
                    RunSmartLogoMark(size: 82, filled: false, glow: true)
                }
                .frame(width: 128)
            }
        }
    }

    private var coachSettingsGrid: some View {
        RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Coach Settings")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ProfileActionTile(title: "Voice Coaching", value: session.onboardingProfile.notificationsEnabled ? "On" : "Off", symbol: "speaker.wave.2.fill") {
                        navPath.append(.voiceCoaching)
                    }
                    ProfileActionTile(title: "Coaching Tone", value: session.onboardingProfile.coachingTone, symbol: "waveform") {
                        navPath.append(.coachingTone)
                    }
                    ProfileActionTile(title: "Goal & Plan", value: session.onboardingProfile.goal.isEmpty ? "Not set" : session.onboardingProfile.goal, symbol: "target") {
                        navPath.append(.goalWizard)
                    }
                    ProfileActionTile(title: "Challenges", value: challenge.isActive ? challenge.dayLabel : "Adopt", symbol: "trophy.fill") {
                        navPath.append(.challenges)
                    }
                    ProfileActionTile(title: "Training Data", value: weeklyDistanceLabel, symbol: "figure.run") {
                        navPath.append(.trainingData)
                    }
                    ProfileActionTile(title: "Check-in Cadence", value: "Every 3 Days", symbol: "calendar") {
                        navPath.append(.reminders)
                    }
                }
            }
        }
    }

    private var trainingDataCard: some View {
        let profile = session.onboardingProfile
        let estimated = TrainingDataBaseline.averageWeeklyDistanceKm(from: recentRuns)
        let saved = profile.averageWeeklyDistanceKm
        let value = saved ?? estimated
        let source = saved != nil
            ? (profile.trainingDataSource?.displayName ?? "Manual")
            : estimatedTrainingDataSourceLabel

        return RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "Training Data")
                    Spacer()
                    Button { navPath.append(.trainingData) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.bodyMD.weight(.bold))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 34, height: 34)
                            .background(Color.accentPrimary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit training data")
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TrainingDataMetricTile(
                        title: "Experience",
                        value: profile.experience.isEmpty ? "Not set" : profile.experience.capitalized,
                        detail: "Plan progression",
                        symbol: "figure.run",
                        tint: .accentPrimary
                    )
                    TrainingDataMetricTile(
                        title: "Weekly Distance",
                        value: value.map { String(format: "%.1f", $0) } ?? "--",
                        detail: value == nil ? "Needed" : "km / week",
                        symbol: "point.topleft.down.curvedto.point.bottomright.up",
                        tint: .accentRecovery
                    )
                    TrainingDataMetricTile(
                        title: "Age",
                        value: ageLabel,
                        detail: profile.age == nil ? "Needed" : "years",
                        symbol: "person.crop.circle.fill",
                        tint: .accentHeart
                    )
                }

                ConnectedServiceTile(
                    title: source,
                    detail: saved == nil && estimated != nil ? "Review and save estimate" : "Saved training baseline",
                    status: saved == nil && estimated != nil ? "Estimate" : (saved == nil ? "Missing" : "Saved"),
                    symbol: source.lowercased().contains("garmin") ? "link.circle.fill" : "checkmark.seal.fill",
                    tint: saved == nil ? .accentRecovery : .accentPrimary
                ) {
                    navPath.append(.trainingData)
                }
            }
        }
    }

    private var optimizationCards: some View {
        RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Coach Optimizing For")
                HStack(spacing: 10) {
                    ProfileOptimizationTile(title: runner.goal, value: "49:12 -> 46:30", detail: "Target PR", symbol: "chart.line.uptrend.xyaxis", tint: .accentPrimary)
                    ProfileOptimizationTile(title: "Consistency", value: "92%", detail: "On track", symbol: "chart.bar.fill", tint: .accentSuccess)
                    ProfileOptimizationTile(title: "Recovery", value: "85%", detail: "Optimal", symbol: "heart", tint: .accentPrimary)
                }
            }
        }
    }

    private var achievementsGallery: some View {
        RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: "Achievements")
                    Button { navPath.append(.badgeCabinet) } label: {
                        Text("View all")
                            .font(.labelSM)
                            .tracking(1.1)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(achievements) { achievement in
                            AchievementBadge(achievement: achievement)
                        }
                    }
                }
            }
        }
    }

    private var connectedSection: some View {
        RunSmartPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Connected")
                VStack(spacing: 8) {
                    ConnectedServiceTile(title: "Garmin", detail: "Garmin Connect", status: statusLabel("Garmin Connect"), symbol: "link.circle.fill", tint: .accentPrimary) {
                        navPath.append(.connectedService("Garmin Connect"))
                    }
                    ConnectedServiceTile(title: "Health", detail: "HealthKit", status: statusLabel("HealthKit"), symbol: "heart.fill", tint: .accentHeart) {
                        navPath.append(.connectedService("HealthKit"))
                    }
                    ConnectedServiceTile(title: "Prefs", detail: "Reminders", status: session.onboardingProfile.notificationsEnabled ? "On" : "Manage", symbol: "bell.fill", tint: .accentRecovery) {
                        navPath.append(.reminders)
                    }
                    ConnectedServiceTile(title: "Account", detail: "Privacy", status: "Manage", symbol: "lock.shield.fill", tint: .textSecondary) {
                        navPath.append(.account)
                    }
                }
            }
        }
    }

    private var settingsSections: some View {
        VStack(spacing: 12) {
            ProfileSettingsSection(title: "Coach Settings", rows: [
                .init(title: "Tone", value: session.onboardingProfile.coachingTone, symbol: "sparkles", destination: .coachingTone),
                .init(title: "Voice Coaching", value: session.onboardingProfile.notificationsEnabled ? "On" : "Off", symbol: "speaker.wave.2.fill", destination: .voiceCoaching),
                .init(title: "Goal & Plan", value: session.onboardingProfile.goal.isEmpty ? "Not set" : session.onboardingProfile.goal, symbol: "target", destination: .goalWizard),
                .init(title: "Challenges", value: challenge.isActive ? challenge.dayLabel : "Adopt", symbol: "trophy.fill", destination: .challenges),
                .init(title: "Weekly Recap", value: "Ready", symbol: "calendar.badge.checkmark", destination: .weeklyRecap)
            ], onSelect: { navPath.append($0) })

            ProfileSettingsSection(title: "Connected Devices", rows: [
                .init(title: "Garmin", value: statusLabel("Garmin Connect"), symbol: "link.circle.fill", destination: .connectedService("Garmin Connect")),
                .init(title: "HealthKit", value: statusLabel("HealthKit"), symbol: "heart.fill", destination: .connectedService("HealthKit")),
                .init(title: "Wellness Panels", value: "View", symbol: "waveform.path.ecg", destination: .garminWellness)
            ], onSelect: { navPath.append($0) })

            ProfileSettingsSection(title: "Preferences", rows: [
                .init(title: "Units", value: session.onboardingProfile.units, symbol: "ruler", destination: .reminders),
                .init(title: "Notifications", value: session.onboardingProfile.notificationsEnabled ? "On" : "Off", symbol: "bell.fill", destination: .reminders),
                .init(title: "Privacy", value: "Manage", symbol: "lock.shield.fill", destination: .account)
            ], onSelect: { navPath.append($0) })
        }
    }

    private func statusLabel(_ provider: String) -> String {
        deviceStatuses.first(where: { $0.provider == provider })?.state.rawValue.capitalized ?? "Disconnected"
    }

    private var estimatedTrainingDataSourceLabel: String {
        guard TrainingDataBaseline.averageWeeklyDistanceKm(from: recentRuns) != nil else { return "Manual setup needed" }
        return TrainingDataBaseline.inferredSource(from: recentRuns)?.displayName ?? "Recent runs"
    }

    private var weeklyDistanceLabel: String {
        let value = session.onboardingProfile.averageWeeklyDistanceKm
            ?? TrainingDataBaseline.averageWeeklyDistanceKm(from: recentRuns)
        return value.map { String(format: "%.0f km/wk", $0) } ?? "Set baseline"
    }

    private var ageLabel: String {
        session.onboardingProfile.age.map(String.init) ?? "--"
    }

    private var levelNumber: String {
        let digits = runner.level.filter(\.isNumber)
        return digits.isEmpty ? "14" : String(digits)
    }
}

private struct TrainingDataMetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.bodyMD.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.surfaceCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

struct ProfileStat: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.1)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.metricSM)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(detail.isEmpty ? " " : detail)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProfileActionTile: View {
    var title: String
    var value: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(12)
            .frame(minHeight: 110, alignment: .topLeading)
            .background(Color.surfaceCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileOptimizationTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(height: 28)
            RunSmartSparkline(values: [2, 4, 3, 5, 7, 6, 8], tint: tint)
                .frame(height: 28)
            Text(value)
                .font(.bodyMD.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(Color.surfaceCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

private struct ConnectedServiceTile: View {
    var title: String
    var detail: String
    var status: String
    var symbol: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.lowercased().contains("connected") || status == "On" ? Color.accentPrimary : Color.textTertiary)
                        .frame(width: 7, height: 7)
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.lowercased().contains("connected") || status == "On" ? Color.accentPrimary : Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.surfaceCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSettingsSection: View {
    var title: String
    var rows: [ProfileSettingsRowModel]
    var onSelect: (SecondaryDestination) -> Void

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: title)
                ForEach(rows) { row in
                    Button { onSelect(row.destination) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: row.symbol)
                                .foregroundStyle(Color.accentPrimary)
                                .frame(width: 34, height: 34)
                                .background(Color.accentPrimary.opacity(0.10), in: Circle())
                            Text(row.title)
                                .font(.bodyMD.weight(.semibold))
                            Spacer()
                            Text(row.value)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProfileSettingsRowModel: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var symbol: String
    var destination: SecondaryDestination
}

struct AchievementBadge: View {
    var achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: achievement.symbol)
                .font(.title2.bold())
                .foregroundStyle(achievement.tint)
                .frame(width: 58, height: 58)
                .background(achievement.tint.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(achievement.tint.opacity(0.78), lineWidth: 2))
            Text(achievement.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(achievement.subtitle)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: 78)
    }
}

struct RecentActivityRow: View {
    var activity: DBGarminActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 38, height: 38)
                .background(Color.accentPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.sportLabel)
                    .font(.subheadline.weight(.semibold))
                Text(activity.relativeStartLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.distanceKmLabel)
                    .font(.subheadline.weight(.semibold))
                Text(activity.durationLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(10)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var symbol: String {
        let s = (activity.sport ?? "").lowercased()
        if s.contains("run") { return "figure.run" }
        if s.contains("walk") { return "figure.walk" }
        if s.contains("bike") || s.contains("cycle") { return "bicycle" }
        if s.contains("swim") { return "figure.pool.swim" }
        return "figure.mixed.cardio"
    }
}
