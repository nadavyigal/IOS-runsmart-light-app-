import SwiftUI

struct GoalWizardView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss

    @State private var goal = "10K PR"
    @State private var weeklyRuns = 4.0
    @State private var targetDate = Date().addingTimeInterval(60 * 60 * 24 * 84)
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let goals = ["First 5K", "10K PR", "Half Marathon", "Marathon", "Just Run More"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HeroCard(accent: .accentEnergy) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(title: "Goal setting wizard")
                            Text("Choose the next training block")
                                .font(.headingLG)
                            Text("The coach uses this to tune weekly load, workout mix, and reminders.")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(goals, id: \.self) { option in
                            Button { goal = option } label: {
                                GoalChoiceCard(title: option, selected: goal == option)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ContentCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Weekly rhythm")
                            Stepper(value: $weeklyRuns, in: 2...7, step: 1) {
                                HStack {
                                    Text("Runs per week")
                                    Spacer()
                                    Text("\(Int(weeklyRuns))")
                                        .font(.metricSM)
                                        .foregroundStyle(Color.accentPrimary)
                                }
                            }
                            .tint(Color.accentPrimary)
                            DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                                .tint(Color.accentPrimary)
                        }
                    }
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(Color.accentHeart)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { Task { await saveGoal() } } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Label("Save Goal & Generate Plan", systemImage: "target")
                        }
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
            }
        }
        .onAppear {
            let profile = session.onboardingProfile
            if !profile.goal.isEmpty { goal = displayGoal(from: profile.goal) }
            weeklyRuns = Double(max(2, min(7, profile.weeklyRunDays)))
        }
    }

    private func saveGoal() async {
        isSaving = true
        errorMessage = nil
        var profile = session.onboardingProfile
        let preferredDays = normalizedPreferredDays(profile.preferredDays, weeklyRuns: Int(weeklyRuns))
        profile.goal = goal
        profile.weeklyRunDays = Int(weeklyRuns)
        profile.preferredDays = preferredDays
        await session.completeOnboarding(profile)

        let request = TrainingGoalRequest(
            displayName: profile.displayName,
            goal: goal,
            experience: profile.experience.isEmpty ? "intermediate" : profile.experience,
            age: profile.age,
            averageWeeklyDistanceKm: profile.averageWeeklyDistanceKm,
            trainingDataSource: profile.trainingDataSource,
            weeklyRunDays: Int(weeklyRuns),
            preferredDays: preferredDays,
            coachingTone: profile.coachingTone.isEmpty ? "Motivating" : profile.coachingTone,
            targetDate: targetDate
        )

        let saved = await services.saveTrainingGoal(request)
        isSaving = false
        if saved {
            RunSmartHaptics.success()
            dismiss()
        } else {
            errorMessage = "Could not save your goal. Check your connection and try again."
        }
    }

    private func displayGoal(from raw: String) -> String {
        switch raw.lowercased() {
        case "habit": return "Just Run More"
        case "speed": return "10K PR"
        case "distance": return "Half Marathon"
        default: return raw
        }
    }

    private func normalizedPreferredDays(_ days: [String], weeklyRuns: Int) -> [String] {
        let fallback = weeklyRuns <= 3 ? ["Mon", "Wed", "Sat"] : ["Mon", "Wed", "Fri", "Sun"]
        let mapped = days.compactMap { day -> String? in
            let lower = day.lowercased()
            if lower.hasPrefix("mon") { return "Mon" }
            if lower.hasPrefix("tue") { return "Tue" }
            if lower.hasPrefix("wed") { return "Wed" }
            if lower.hasPrefix("thu") { return "Thu" }
            if lower.hasPrefix("fri") { return "Fri" }
            if lower.hasPrefix("sat") { return "Sat" }
            if lower.hasPrefix("sun") { return "Sun" }
            return nil
        }
        let resolved = mapped.isEmpty ? fallback : mapped
        return Array(resolved.prefix(max(1, weeklyRuns)))
    }
}

private struct GoalChoiceCard: View {
    var title: String
    var selected: Bool

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentPrimary : Color.textTertiary)
                Text(title)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous)
                .stroke(selected ? Color.accentPrimary : .clear, lineWidth: 1.5)
        )
    }
}
