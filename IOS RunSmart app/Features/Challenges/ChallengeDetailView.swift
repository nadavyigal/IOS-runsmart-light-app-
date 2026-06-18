import SwiftUI

struct ChallengeDetailView: View {
    var challenge: ChallengeItem
    var onEnrolled: () -> Void

    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss
    @State private var isEnrolling = false
    @State private var isEnrolled: Bool
    @State private var errorMessage: String?
    private let repo = ChallengeRepository()

    init(challenge: ChallengeItem, onEnrolled: @escaping () -> Void) {
        self.challenge = challenge
        self.onEnrolled = onEnrolled
        _isEnrolled = State(initialValue: challenge.isEnrolled)
    }

    var body: some View {
        ZStack {
            RunSmartBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(Color.mutedText)
                                .padding(10)
                                .background(.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        Spacer()
                        if isEnrolled {
                            Label("Active", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.lime)
                                .clipShape(Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.lime.opacity(0.18))
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.lime.opacity(0.4), radius: 20)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Color.lime)
                        }

                        Text(challenge.title)
                            .font(.title2.bold())

                        HStack(spacing: 12) {
                            MetricPill(symbol: "calendar", text: "\(challenge.durationDays) days")
                            if let started = challenge.startedAt {
                                MetricPill(symbol: "play.fill", text: "Started \(started.formatted(.relative(presentation: .named)))")
                            }
                        }
                    }

                    GlassCard(cornerRadius: 18, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(title: "About this challenge")
                            Text(challenge.description)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !isEnrolled {
                        Button(action: { Task { await enroll() } }) {
                            HStack {
                                if isEnrolling {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("Adopt Challenge")
                                        .font(.headline)
                                }
                            }
                        }
                        .buttonStyle(NeonButtonStyle())
                        .disabled(isEnrolling)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func enroll() async {
        if challenge.slug.hasPrefix("local-") {
            isEnrolling = true
            errorMessage = nil
            let saved = await saveChallengePlan()
            isEnrolling = false
            if saved {
                isEnrolled = true
                onEnrolled()
                RunSmartHaptics.success()
                dismiss()
            } else {
                errorMessage = "Challenge adopted, but the plan update could not start. Check your connection and try again."
            }
            return
        }
        guard let userID = session.currentUserID else { return }
        isEnrolling = true
        errorMessage = nil
        do {
            try await repo.enroll(challengeID: challenge.id, authUserID: userID)
            let saved = await saveChallengePlan()
            if saved {
                isEnrolled = true
                onEnrolled()
                RunSmartHaptics.success()
                dismiss()
            } else {
                errorMessage = "Challenge adopted, but the plan update could not start. Check your connection and try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnrolling = false
    }

    private func saveChallengePlan() async -> Bool {
        var profile = session.onboardingProfile
        profile.goal = challenge.title
        profile.weeklyRunDays = max(2, min(7, profile.weeklyRunDays))
        if profile.preferredDays.isEmpty {
            let fallbackDays = ["Mon", "Wed", "Fri", "Sun"]
            profile.preferredDays = Array(fallbackDays.prefix(profile.weeklyRunDays))
        }
        await session.completeOnboarding(profile)

        let request = TrainingGoalRequest(
            displayName: profile.displayName,
            goal: challenge.title,
            experience: profile.experience.isEmpty ? "intermediate" : profile.experience,
            age: profile.age,
            averageWeeklyDistanceKm: profile.averageWeeklyDistanceKm,
            trainingDataSource: profile.trainingDataSource,
            weeklyRunDays: profile.weeklyRunDays,
            preferredDays: profile.preferredDays,
            coachingTone: profile.coachingTone.isEmpty ? "Motivating" : profile.coachingTone,
            targetDate: Calendar.current.date(byAdding: .day, value: max(21, challenge.durationDays), to: Date()) ?? Date().addingTimeInterval(21 * 86_400),
            challenge: TrainingChallengeContext(
                slug: challenge.slug,
                name: challenge.title,
                category: challenge.planCategory,
                difficulty: profile.experience.isEmpty ? "intermediate" : profile.experience.lowercased(),
                durationDays: challenge.durationDays,
                workoutPattern: challenge.description,
                coachTone: profile.coachingTone.isEmpty ? "Motivating" : profile.coachingTone,
                targetAudience: "RunSmart iOS runner",
                promise: challenge.description
            )
        )
        return await services.saveTrainingGoal(request)
    }
}

private extension ChallengeItem {
    var planCategory: String {
        let text = "\(slug) \(title) \(description)".lowercased()
        if text.contains("recovery") { return "recovery" }
        if text.contains("mindful") { return "mindful" }
        if text.contains("10k") || text.contains("speed") || text.contains("breakthrough") || text.contains("performance") {
            return "performance"
        }
        return "habit"
    }
}
