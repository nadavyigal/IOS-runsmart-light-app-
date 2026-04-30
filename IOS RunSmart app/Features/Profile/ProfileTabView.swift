import SwiftUI

struct ProfileTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var runner = RunnerProfile(name: "RunSmart Runner", goal: "Loading", streak: "--", level: "--", totalRuns: 0, totalDistance: 0, totalTime: "0h 0m")
    @State private var achievements: [Achievement] = []
    @State private var deviceStatuses: [ConnectedDeviceStatus] = []
    @State private var navPath: [SecondaryDestination] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    RunSmartHeader(title: "Profile", showSettings: true) {
                        navPath.append(.account)
                    }

                    identityHeader
                    statsBar
                    achievementsGallery
                    settingsSections
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
            async let runnerTask = services.runnerProfile()
            async let achievementsTask = services.achievements()
            async let statusesTask = services.deviceStatuses()
            (runner, achievements, deviceStatuses) = await (runnerTask, achievementsTask, statusesTask)
        }
    }

    private var identityHeader: some View {
        HeroCard(accent: .accentPrimary) {
            HStack(spacing: 16) {
                CoachAvatar(size: 94, showBolt: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(runner.name)
                        .font(.displayMD)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("Level: \(runner.level)")
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.accentPrimary)
                    Text(runner.goal)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var statsBar: some View {
        ContentCard(padding: 0) {
            HStack(spacing: 0) {
                ProfileStat(title: "Runs", value: "\(runner.totalRuns)", detail: "")
                Divider().background(Color.border)
                ProfileStat(title: "Km", value: "\(runner.totalDistance)", detail: "total")
                Divider().background(Color.border)
                ProfileStat(title: "Streak", value: runner.streak.components(separatedBy: " ").first ?? "--", detail: "weeks")
                Divider().background(Color.border)
                ProfileStat(title: "Time", value: runner.totalTime, detail: "")
            }
            .padding(.vertical, 14)
        }
    }

    private var achievementsGallery: some View {
        ContentCard {
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

    private var settingsSections: some View {
        VStack(spacing: 12) {
            ProfileSettingsSection(title: "Coach Settings", rows: [
                .init(title: "Tone", value: session.onboardingProfile.coachingTone, symbol: "sparkles", destination: .coachingTone),
                .init(title: "Voice Coaching", value: session.onboardingProfile.notificationsEnabled ? "On" : "Off", symbol: "speaker.wave.2.fill", destination: .voiceCoaching),
                .init(title: "Goal Focus", value: session.onboardingProfile.goal.isEmpty ? "Not set" : session.onboardingProfile.goal, symbol: "target", destination: .goalWizard),
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
