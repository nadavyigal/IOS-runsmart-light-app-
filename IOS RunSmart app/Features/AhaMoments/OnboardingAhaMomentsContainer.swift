import SwiftUI

@MainActor
enum OnboardingAhaMomentsFlow {
    enum Step {
        case identity
        case timeline
    }

    static func shouldPresentIdentity(profile: OnboardingProfile) async -> (identity: RunnerIdentityPresentation, timeline: GoalTimelineProjection)? {
        let identity = UserInsightService.getRunningIdentity(
            goal: profile.goal,
            experience: profile.experience,
            paceMinPerKm: nil
        )
        let timeline = UserInsightService.projectGoalTimeline(goal: profile.goal, experience: profile.experience)
        let knowsMeFired = await AhaMomentStore.shared.hasFired(momentId: "knows_me")
        let timelineFired = await AhaMomentStore.shared.hasFired(momentId: "future_vision")
        guard !knowsMeFired || !timelineFired else { return nil }
        return (identity, timeline)
    }
}

struct OnboardingAhaMomentsContainer: View {
    var profile: OnboardingProfile
    var onFinished: () -> Void

    @State private var step: OnboardingAhaMomentsFlow.Step = .identity
    @State private var identity: RunnerIdentityPresentation
    @State private var timeline: GoalTimelineProjection
    @State private var skipIdentity = false
    @State private var skipTimeline = false

    init(profile: OnboardingProfile, onFinished: @escaping () -> Void) {
        self.profile = profile
        self.onFinished = onFinished
        _identity = State(initialValue: UserInsightService.getRunningIdentity(
            goal: profile.goal,
            experience: profile.experience,
            paceMinPerKm: nil
        ))
        _timeline = State(initialValue: UserInsightService.projectGoalTimeline(
            goal: profile.goal,
            experience: profile.experience
        ))
    }

    var body: some View {
        Group {
            switch step {
            case .identity:
                RunnerIdentityMomentView(
                    identity: identity,
                    onCTA: { completeIdentity(ctaClicked: true) },
                    onSkip: { completeIdentity(ctaClicked: false) }
                )
            case .timeline:
                GoalTimelineMomentView(
                    timeline: timeline,
                    identityAccent: identity.accent,
                    onCTA: { completeTimeline(ctaClicked: true) },
                    onSkip: { completeTimeline(ctaClicked: false) }
                )
            }
        }
        .task {
            skipIdentity = await AhaMomentStore.shared.hasFired(momentId: "knows_me")
            skipTimeline = await AhaMomentStore.shared.hasFired(momentId: "future_vision")
            if skipIdentity && skipTimeline {
                onFinished()
            } else if skipIdentity {
                step = .timeline
            }
        }
    }

    private func completeIdentity(ctaClicked: Bool) {
        Task {
            await AhaMomentStore.shared.record(momentId: "knows_me", variant: "C", ctaClicked: ctaClicked)
            if !ctaClicked {
                await AhaMomentStore.shared.updateDismissed(momentId: "knows_me")
            }
            await AhaMomentStore.shared.persistInsightProfile(identity: identity.kind, timeline: timeline)
            await MainActor.run {
                if skipTimeline {
                    onFinished()
                } else {
                    step = .timeline
                }
            }
        }
    }

    private func completeTimeline(ctaClicked: Bool) {
        Task {
            await AhaMomentStore.shared.record(momentId: "future_vision", variant: "C", ctaClicked: ctaClicked)
            if !ctaClicked {
                await AhaMomentStore.shared.updateDismissed(momentId: "future_vision")
            }
            await AhaMomentStore.shared.persistInsightProfile(identity: identity.kind, timeline: timeline)
            await MainActor.run {
                onFinished()
            }
        }
    }
}
