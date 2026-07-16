import SwiftUI

#if DEBUG
struct AdaptivePreviewCard: View {
    let missedWorkout: WorkoutSummary
    let onReview: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 18, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("ADAPTIVE PREVIEW")
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                }
                .foregroundStyle(Color.accentPrimary)

                Text("Missed \(missedWorkout.title)?")
                    .font(.headingMD.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Text("RunSmart can reshape the rest of this week without changing your current plan until you approve it.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onReview) {
                    HStack {
                        Text("Review adaptive week")
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
                .accessibilityIdentifier("adaptivePreview.reviewWeek")

                Label("Safe local preview — no production data", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityIdentifier("adaptivePreview.card")
    }
}

#Preview("Adaptive Preview") {
    ZStack {
        RunSmartBackground(context: .today(readiness: 72))
            .ignoresSafeArea()
        AdaptivePreviewCard(
            missedWorkout: RunSmartAdaptivePreviewData.workouts()[0],
            onReview: {}
        )
        .padding(18)
    }
    .preferredColorScheme(.dark)
}
#endif
