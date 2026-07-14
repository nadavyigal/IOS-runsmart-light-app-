import SwiftUI

/// Shown on Today and Plan while the coach builds a plan, and when that build
/// fails. Replaces the old behaviour where both screens sat blank for ~30-45s
/// and the only failure signal was a transient banner pointing at a
/// Profile-buried screen (audit §4 Risk 1 / WP-43 S1).
struct PlanGenerationStatusCard: View {
    var state: PlanGenerationState
    var onRetry: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 34, height: 34)
                        .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.bodyLG.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(subtitle)
                            .font(.labelSM)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    if state.showsGeneratingCard {
                        ProgressView()
                            .tint(Color.accentPrimary)
                    }
                }

                Text(body_)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.showsInlineRetry {
                    Button(action: onRetry) {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NeonButtonStyle())
                    .accessibilityIdentifier("planGenerationRetryButton")
                }
            }
        }
    }

    private var accent: Color {
        state.showsInlineRetry ? .accentHeart : .accentRecovery
    }

    private var symbol: String {
        state.showsInlineRetry ? "exclamationmark.triangle.fill" : "sparkles"
    }

    private var title: String {
        state.showsInlineRetry ? "We couldn't build your plan" : "Coach is building your plan"
    }

    private var subtitle: String {
        state.showsInlineRetry ? "Nothing was lost" : "This usually takes 30 to 45 seconds"
    }

    private var body_: String {
        state.showsInlineRetry
            ? "Your details are saved. Tap Try again to rebuild your plan without leaving this screen."
            : "We're turning your goal and schedule into a week-by-week plan. You can stay here while it finishes."
    }
}
