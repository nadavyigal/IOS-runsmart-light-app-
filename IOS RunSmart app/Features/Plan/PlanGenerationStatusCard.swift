import SwiftUI

/// Shown on Today and Plan while the coach builds a plan, when that build
/// fails, and when a signed-in runner has no plan at all. Replaces the old
/// behaviour where both screens sat blank for ~30-45s and the only failure
/// signal was a transient banner pointing at a Profile-buried screen
/// (audit §4 Risk 1 / WP-43 S1).
struct PlanGenerationStatusCard: View {
    var card: PlanGenerationCard
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

                    if card == .generating {
                        ProgressView()
                            .tint(Color.accentPrimary)
                    }
                }

                Text(body_)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch card {
                case .generating:
                    EmptyView()
                case .retry:
                    Button(action: onRetry) {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NeonButtonStyle())
                    .accessibilityIdentifier("planGenerationRetryButton")
                case .buildMissingPlan:
                    Button(action: onRetry) {
                        Label("Build my plan", systemImage: "sparkles")
                    }
                    .buttonStyle(NeonButtonStyle())
                    .accessibilityIdentifier("planGenerationBuildButton")
                }
            }
        }
    }

    private var accent: Color {
        card == .retry ? .accentHeart : .accentRecovery
    }

    private var symbol: String {
        card == .retry ? "exclamationmark.triangle.fill" : "sparkles"
    }

    private var title: String {
        switch card {
        case .generating: "Coach is building your plan"
        case .retry: "We couldn't build your plan"
        case .buildMissingPlan: "You don't have a plan yet"
        }
    }

    private var subtitle: String {
        switch card {
        case .generating, .buildMissingPlan: "This usually takes 30 to 45 seconds"
        case .retry: "Nothing was lost"
        }
    }

    private var body_: String {
        switch card {
        case .generating:
            "We're turning your goal and schedule into a week-by-week plan. You can stay here while it finishes."
        case .retry:
            "Your details are saved. Tap Try again to rebuild your plan without leaving this screen."
        case .buildMissingPlan:
            "Your goal and schedule are saved. Tap Build my plan and the coach will turn them into a week-by-week plan."
        }
    }
}
