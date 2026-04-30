import SwiftUI

struct ProfileTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession

    @State private var runner = RunnerProfile(name: "RunSmart Runner", goal: "Loading", streak: "--", level: "--", totalRuns: 0, totalDistance: 0, totalTime: "0h 0m")
    @State private var achievements: [Achievement] = []
    @State private var deviceStatuses: [ConnectedDeviceStatus] = []
    @State private var recentActivities: [DBGarminActivity] = []
    @State private var recentRuns: [RecordedRun] = []
    @State private var plannedWorkouts: [WorkoutSummary] = []
    @State private var navPath: [SecondaryDestination] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    RunSmartHeader(title: "Profile", showSettings: true) {
                        navPath.append(.account)
                    }

                    HStack(spacing: 16) {
                        CoachAvatar(size: 92, showBolt: true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(runner.name)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            HStack(spacing: 7) {
                                Text(runner.goal)
                                Circle()
                                    .fill(Color.lime)
                                    .frame(width: 5, height: 5)
                                Text(runner.streak)
                            }
                            .foregroundStyle(Color.mutedText)
                        }
                    }

                    GlassCard(cornerRadius: 16, padding: 0) {
                        HStack(spacing: 0) {
                            ProfileStat(title: "Level", value: runner.level, detail: "")
                            Divider().background(Color.hairline)
                            ProfileStat(title: "Total Runs", value: "\(runner.totalRuns)", detail: "")
                            Divider().background(Color.hairline)
                            ProfileStat(title: "Total Distance", value: "\(runner.totalDistance)", detail: "km")
                            Divider().background(Color.hairline)
                            ProfileStat(title: "Total Time", value: runner.totalTime, detail: "")
                        }
                        .padding(.vertical, 14)
                    }

                    GlassCard(glow: Color.lime) {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(title: "Your AI Coach")
                                HStack(spacing: 8) {
                                    Text("RunSmart Coach")
                                        .font(.title3.weight(.bold))
                                    Text("AI")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.lime)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Color.lime.opacity(0.13))
                                        .clipShape(Capsule())
                                }
                                Text("Tone: \(session.onboardingProfile.coachingTone)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.mutedText)
                                Button(action: { router.openCoach(context: "Profile") }) {
                                    Label("Chat with Coach", systemImage: "text.bubble")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.lime)
                                .background(Color.lime.opacity(0.11))
                                .overlay(Capsule().stroke(Color.lime.opacity(0.7)))
                                .clipShape(Capsule(style: .continuous))
                            }
                            Spacer(minLength: 8)
                            CoachSilhouette()
                                .frame(width: 110, height: 120)
                        }
                    }

                    GlassCard(cornerRadius: 18, padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COACH SETTINGS")
                                .font(.caption.bold())
                                .foregroundStyle(Color.mutedText)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                SettingsTile(title: "Voice Coaching", value: session.onboardingProfile.notificationsEnabled ? "On" : "Off", symbol: "speaker.wave.2", action: { navPath.append(.voiceCoaching) })
                                SettingsTile(title: "Coaching Tone", value: session.onboardingProfile.coachingTone, symbol: "waveform", action: { navPath.append(.coachingTone) })
                                SettingsTile(title: "Goal Focus", value: session.onboardingProfile.goal.isEmpty ? "Not set" : session.onboardingProfile.goal, symbol: "target", action: { navPath.append(.goalFocus) })
                                SettingsTile(title: "Runs / Week", value: "\(session.onboardingProfile.weeklyRunDays)", symbol: "calendar", action: { navPath.append(.reminders) })
                            }
                        }
                    }

                    MomentumSnapshotCard(runs: recentRuns, plannedWorkouts: plannedWorkouts)

                    RunTrendChartCard(runs: recentRuns)

                    GlassCard(cornerRadius: 18, padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COACH OPTIMIZING FOR")
                                .font(.caption.bold())
                                .foregroundStyle(Color.mutedText)
                            HStack(spacing: 10) {
                                SmallStatCard(title: runner.goal.capitalized, value: "--", unit: "goal", symbol: "chart.line.uptrend.xyaxis", tint: Color.lime)
                                SmallStatCard(title: "Experience", value: runner.level, unit: "", symbol: "chart.bar.fill", tint: Color.lime)
                                SmallStatCard(title: "Total km", value: "\(runner.totalDistance)", unit: "km", symbol: "figure.run", tint: Color.lime)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Achievements", trailing: "View all")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(achievements) { achievement in
                                        AchievementBadge(achievement: achievement)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard(cornerRadius: 18, padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Recent Activities", trailing: recentActivities.isEmpty ? nil : "From Garmin")
                            if recentActivities.isEmpty {
                                Text("No Garmin activities yet. Tap Sync Now under Connected → Garmin Connect to pull your latest runs.")
                                    .font(.callout)
                                    .foregroundStyle(Color.mutedText)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(recentActivities.prefix(5), id: \.id) { activity in
                                        Button {
                                            navPath.append(.runReport(activity))
                                        } label: {
                                            RecentActivityRow(activity: activity)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CONNECTED")
                                .font(.caption.bold())
                                .foregroundStyle(Color.mutedText)
                            HStack(spacing: 10) {
                                ConnectedServiceCard(name: "Garmin Connect", status: statusLabel("Garmin Connect"), action: { navPath.append(.connectedService("Garmin Connect")) })
                                ConnectedServiceCard(name: "HealthKit", status: statusLabel("HealthKit"), action: { navPath.append(.connectedService("HealthKit")) })
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
                                    Text("View and adopt active running challenges.")
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
            async let runnerTask = services.runnerProfile()
            async let achievementsTask = services.achievements()
            async let statusesTask = services.deviceStatuses()
            async let runsTask = services.recentRuns()
            async let planTask = services.weeklyPlan()
            async let activitiesTask: [DBGarminActivity] = {
                guard let userID = await session.currentUserID else { return [] }
                return await GarminBridge.shared.recentActivities(authUserID: userID, limit: 10)
            }()
            (runner, achievements, deviceStatuses, recentRuns, plannedWorkouts, recentActivities) = await (runnerTask, achievementsTask, statusesTask, runsTask, planTask, activitiesTask)
        }
    }

    private func statusLabel(_ provider: String) -> String {
        deviceStatuses.first(where: { $0.provider == provider })?.state.rawValue.capitalized ?? "Disconnected"
    }
}

struct CoachSilhouette: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.lime.opacity(0.65), lineWidth: 3)
                .frame(width: 118, height: 118)
                .blur(radius: 0.2)
                .shadow(color: Color.lime.opacity(0.66), radius: 18)
                .offset(x: 8, y: -6)
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .stroke(Color.lime.opacity(0.11), lineWidth: 1)
                    .frame(width: CGFloat(42 + index * 18), height: CGFloat(42 + index * 18))
                    .offset(x: -18, y: CGFloat(index * 5))
            }
            VStack(spacing: -8) {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.lime.opacity(0.32), Color.inkElevated], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 78, height: 88)
                    .overlay(
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(Color.lime)
                    )
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color.lime.opacity(0.20), Color.inkElevated.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 118, height: 64)
            }
            .shadow(color: Color.lime.opacity(0.34), radius: 18)
        }
        .clipped()
    }
}

struct ProfileStat: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mutedText)
            Text(value)
                .font(.title3.bold())
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.lime)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsTile: View {
    var title: String
    var value: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.title3)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                    Text(value)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.lime)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.mutedText)
            }
            .padding(12)
            .background(.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AchievementBadge: View {
    var achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: achievement.symbol)
                .font(.title2.bold())
                .foregroundStyle(achievement.tint)
                .frame(width: 54, height: 54)
                .background(achievement.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(achievement.tint.opacity(0.7)))
            Text(achievement.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(achievement.subtitle)
                .font(.caption2)
                .foregroundStyle(Color.mutedText)
        }
        .frame(width: 72)
    }
}

struct RecentActivityRow: View {
    var activity: DBGarminActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(Color.lime)
                .frame(width: 38, height: 38)
                .background(Color.lime.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.sportLabel)
                    .font(.subheadline.weight(.semibold))
                Text(activity.relativeStartLabel)
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.distanceKmLabel)
                    .font(.subheadline.weight(.semibold))
                Text(activity.durationLabel)
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
            }
        }
        .padding(10)
        .background(.white.opacity(0.045))
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

struct ConnectedServiceCard: View {
    var name: String
    var status: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.caption.weight(.semibold))
                    Text("• \(status)")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.lime)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.mutedText)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
