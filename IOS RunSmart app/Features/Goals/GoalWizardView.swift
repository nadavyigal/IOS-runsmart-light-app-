import SwiftUI

struct GoalWizardView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoal = GoalWizardOption.options[1]
    @State private var weeklyRuns = 4.0
    @State private var targetDate = Date().addingTimeInterval(60 * 60 * 24 * 84)
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            RunSmartBackground(context: .profile)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    hero

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GoalWizardOption.options) { option in
                            Button {
                                selectedGoal = option
                                errorMessage = nil
                            } label: {
                                GoalChoiceCard(option: option, selected: selectedGoal == option)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    rhythmCard
                    primaryActionButton(title: "Continue & Generate Plan")
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 78)
                .padding(.bottom, 148)
            }

            topBar
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: hydrateFromProfile)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.bodyMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal & Plan")
                        .font(.bodyMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(selectedGoal.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button { Task { await saveGoal() } } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text(isSaving ? "Saving" : "Save")
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.black)
                    .frame(minWidth: 82)
                    .frame(height: 40)
                    .background(Color.accentPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Save goal and generate plan")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: 1)
            }

            Spacer()
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.surfaceGreenBlack.opacity(0.82))
                    .frame(width: 94, height: 94)
                    .shadow(color: Color.accentSuccess.opacity(0.32), radius: 34)
                RunSmartLogoMark(size: 62, filled: false, glow: true)
            }
            .padding(.top, 6)

            Text("WELCOME TO RUNSMART")
                .font(.metricXS.weight(.bold))
                .foregroundStyle(Color.accentPrimary)

            Text("What's your\nrunning goal?")
                .font(.displayLG)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.82)

            Text("We'll build your plan around it.")
                .font(.bodyLG)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accentHeart)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.accentHeart.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentHeart.opacity(0.35), lineWidth: 1)
        )
    }

    private var rhythmCard: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: selectedGoal.tint) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Plan rhythm")
                Stepper(value: $weeklyRuns, in: 2...7, step: 1) {
                    HStack {
                        Label("Runs per week", systemImage: "calendar.badge.clock")
                            .font(.bodyMD.weight(.semibold))
                        Spacer()
                        Text("\(Int(weeklyRuns))")
                            .font(.metricSM)
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
                .tint(Color.accentPrimary)

                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                    .font(.bodyMD.weight(.semibold))
                    .tint(Color.accentPrimary)
            }
        }
    }

    private func primaryActionButton(title: String) -> some View {
        Button { Task { await saveGoal() } } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                    Text("Saving goal")
                } else {
                    Label(title, systemImage: "target")
                }
            }
        }
        .buttonStyle(NeonButtonStyle())
        .disabled(isSaving)
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Color.accentHeart)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryActionButton(title: "Save Goal & Generate Plan")
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

    private func hydrateFromProfile() {
        let profile = session.onboardingProfile
        selectedGoal = GoalWizardOption.option(matching: profile.goal) ?? selectedGoal
        weeklyRuns = Double(max(2, min(7, profile.weeklyRunDays)))
    }

    private func saveGoal() async {
        isSaving = true
        errorMessage = nil

        var profile = session.onboardingProfile
        let preferredDays = normalizedPreferredDays(profile.preferredDays, weeklyRuns: Int(weeklyRuns))
        profile.goal = selectedGoal.planGoal
        profile.weeklyRunDays = Int(weeklyRuns)
        profile.preferredDays = preferredDays
        await session.completeOnboarding(profile)

        let request = TrainingGoalRequest(
            displayName: profile.displayName,
            goal: selectedGoal.planGoal,
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

struct GoalWizardOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let planGoal: String
    let symbol: String
    let tint: Color

    static func == (lhs: GoalWizardOption, rhs: GoalWizardOption) -> Bool {
        lhs.id == rhs.id
    }

    static let options: [GoalWizardOption] = [
        .init(id: "first-5k", title: "First 5K", subtitle: "Start strong", planGoal: "First 5K", symbol: "figure.run", tint: .accentRecovery),
        .init(id: "half-marathon", title: "Half Marathon", subtitle: "Go the distance", planGoal: "Half Marathon", symbol: "flag.checkered", tint: .accentMagenta),
        .init(id: "full-marathon", title: "Full Marathon", subtitle: "The full journey", planGoal: "Marathon", symbol: "map.fill", tint: .accentEnergy),
        .init(id: "get-faster", title: "Get Faster", subtitle: "Push your limits", planGoal: "Get Faster", symbol: "bolt.fill", tint: .accentPrimary),
        .init(id: "stay-fit", title: "Stay Fit", subtitle: "Healthy lifestyle", planGoal: "Stay Fit", symbol: "heart.fill", tint: .accentSuccess),
        .init(id: "build-habit", title: "Build Habit", subtitle: "Run consistently", planGoal: "Build Habit", symbol: "repeat", tint: .accentHeart)
    ]

    static func option(matching rawGoal: String) -> GoalWizardOption? {
        let lower = rawGoal.lowercased()
        guard !lower.isEmpty else { return nil }

        if lower == "race" || lower.contains("10k") || lower.contains("pr") || lower.contains("faster") || lower.contains("speed") {
            return options.first { $0.id == "get-faster" }
        }
        if lower.contains("5k") { return options.first { $0.id == "first-5k" } }
        if lower.contains("half") || lower.contains("distance") { return options.first { $0.id == "half-marathon" } }
        if lower.contains("marathon") { return options.first { $0.id == "full-marathon" } }
        if lower.contains("habit") || lower.contains("just") || lower.contains("consistency") {
            return options.first { $0.id == "build-habit" }
        }
        if lower.contains("fitness") || lower.contains("fit") {
            return options.first { $0.id == "stay-fit" }
        }
        return options.first { $0.title.lowercased() == lower || $0.planGoal.lowercased() == lower }
    }
}

private struct GoalChoiceCard: View {
    var option: GoalWizardOption
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(option.tint.opacity(0.16))
                    .frame(width: 48, height: 48)
                    .shadow(color: option.tint.opacity(selected ? 0.45 : 0.24), radius: selected ? 18 : 10)
                Image(systemName: selected ? "checkmark" : option.symbol)
                    .font(.bodyMD.weight(.black))
                    .foregroundStyle(option.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(option.title)
                    .font(.headingMD.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(option.subtitle)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surfaceCard.opacity(selected ? 0.98 : 0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? option.tint.opacity(0.95) : Color.white.opacity(0.12), lineWidth: selected ? 1.6 : 1)
        )
        .shadow(color: option.tint.opacity(selected ? 0.16 : 0), radius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
