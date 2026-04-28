import SwiftUI

struct ProfileTabView<Services: ProfileProviding>: View {
    let services: Services
    var openCoach: () -> Void
    var openSecondary: (String) -> Void

    @State private var runner = RunSmartPreviewData.runner
    @State private var achievements = RunSmartPreviewData.achievements

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                RunSmartHeader(title: "Profile", showSettings: true)

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
                        ProfileStat(title: "Level", value: "14", detail: runner.level)
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
                            HStack {
                                Text("Coach Spark")
                                    .font(.title.weight(.bold))
                                Text("AI")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.lime)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.lime.opacity(0.13))
                                    .clipShape(Capsule())
                            }
                            Text("Adaptive. Motivating. Data-driven.")
                                .font(.subheadline)
                                .foregroundStyle(Color.mutedText)
                            Text("I analyze your data, adapt your plan in real-time, and coach you to be your best.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                            Button(action: openCoach) {
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
                        Spacer()
                        CoachSilhouette()
                            .frame(width: 138, height: 150)
                    }
                }

                GlassCard(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("COACH SETTINGS")
                            .font(.caption.bold())
                            .foregroundStyle(Color.mutedText)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            SettingsTile(title: "Voice Coaching", value: "On", symbol: "speaker.wave.2", action: { openSecondary("Voice Coaching") })
                            SettingsTile(title: "Coaching Tone", value: "Motivating", symbol: "waveform", action: { openSecondary("Coaching Tone") })
                            SettingsTile(title: "Goal Focus", value: "10K Improvement", symbol: "target", action: { openSecondary("Goal Focus") })
                            SettingsTile(title: "Check-in Cadence", value: "Every 3 Days", symbol: "calendar", action: { openSecondary("Reminders") })
                        }
                    }
                }

                GlassCard(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("COACH OPTIMIZING FOR")
                            .font(.caption.bold())
                            .foregroundStyle(Color.mutedText)
                        HStack(spacing: 10) {
                            SmallStatCard(title: "10K Improvement", value: "49:12", unit: "→ 46:30", symbol: "chart.line.uptrend.xyaxis", tint: Color.lime)
                            SmallStatCard(title: "Consistency", value: "92%", unit: "On track", symbol: "chart.bar.fill", tint: Color.lime)
                            SmallStatCard(title: "Recovery", value: "85%", unit: "Optimal", symbol: "heart.circle", tint: Color.lime)
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

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONNECTED")
                            .font(.caption.bold())
                            .foregroundStyle(Color.mutedText)
                        HStack(spacing: 10) {
                            ConnectedServiceCard(name: "Garmin Connect", status: "Connected", action: { openSecondary("Garmin Connect") })
                            ConnectedServiceCard(name: "Strava", status: "Connected", action: { openSecondary("Strava") })
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            runner = await services.runnerProfile()
            achievements = await services.achievements()
        }
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
