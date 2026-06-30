import SwiftUI

struct FirstRunActivationContext: Identifiable, Hashable {
    let id = UUID()
    var workout: WorkoutSummary
}

struct FirstRunActivationSheet: View {
    var workout: WorkoutSummary
    var onStartNow: () -> Void
    var onRemindMe: () -> Void

    var body: some View {
        ZStack {
            RunSmartBackground(context: .today(readiness: 82))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        RunSmartLogoMark(size: 76, filled: false, glow: true)
                        Image(systemName: "figure.run")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(Color.black)
                            .frame(width: 52, height: 52)
                            .background(Color.accentPrimary, in: Circle())
                            .shadow(color: Color.accentPrimary.opacity(0.36), radius: 18)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your first run is ready")
                            .font(.displayMD)
                            .displayTightTracking(-0.8)
                        Text("Start \(workout.title) now, or get a calm reminder tomorrow morning.")
                            .font(.bodyLG)
                            .foregroundStyle(Color.textSecondary)
                    }

                    ContentCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(workout.title, systemImage: "figure.run")
                                .font(.bodyMD.weight(.semibold))
                            HStack(spacing: 12) {
                                Text(workout.distance)
                                    .font(.metricSM)
                                    .foregroundStyle(Color.accentPrimary)
                                if !workout.detail.isEmpty {
                                    Text(workout.detail)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(2)
                                }
                            }

                            Button(action: onStartNow) {
                                Label("Start Now", systemImage: "play.fill")
                            }
                            .buttonStyle(NeonButtonStyle())

                            Button(action: onRemindMe) {
                                Label("Remind Me Tomorrow", systemImage: "bell.fill")
                                    .font(.buttonLabel)
                                    .foregroundStyle(Color.accentPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                                    .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.55), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Text("Reminders are local, low-frequency, and can be turned off from Profile.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .foregroundStyle(Color.textPrimary)
                .padding(24)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            Analytics.trackFirstRunCTAViewed(
                workoutType: workout.kind.rawValue,
                scheduledToday: Calendar.current.isDateInToday(workout.scheduledDate)
            )
        }
    }
}
