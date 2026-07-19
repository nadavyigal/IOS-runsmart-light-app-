import SwiftUI

/// Production Adaptive Coach card: proactively proposes a Flex Week reshape
/// when AdaptiveCoachPolicy fires. Visibility is governed entirely by
/// AdaptiveCoachPresentation (feature flag AND prompt) — no DEBUG gate; the
/// flag ships OFF via RUNSMART_ADAPTIVE_COACH_ENABLED = NO.
struct AdaptiveCoachCard: View {
    let prompt: AdaptiveCoachPrompt
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 18, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("ADAPTIVE COACH")
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss adaptive coach suggestion")
                    .accessibilityIdentifier("adaptiveCoach.dismiss")
                }
                .foregroundStyle(Color.accentPrimary)

                Text(prompt.headline)
                    .font(.headingMD.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Text(prompt.detail)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onReview) {
                    HStack {
                        Text("Review adjusted week")
                            .font(.bodyMD.weight(.bold))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.bodyMD.weight(.bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("adaptiveCoach.review")

                Label("Nothing changes until you approve it", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityIdentifier("adaptiveCoach.card")
    }
}

#Preview("Adaptive Coach Card") {
    ZStack {
        RunSmartBackground(context: .today(readiness: 72))
            .ignoresSafeArea()
        AdaptiveCoachCard(
            prompt: AdaptiveCoachPrompt(
                trigger: .missedWorkout,
                headline: "Missed Tempo Run?",
                detail: "I can reshape the rest of this week so you stay on track — nothing changes until you approve it.",
                reason: .tired
            ),
            onReview: {},
            onDismiss: {}
        )
        .padding(18)
    }
    .preferredColorScheme(.dark)
}
