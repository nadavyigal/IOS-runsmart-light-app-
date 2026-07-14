import SwiftUI

struct GoalTimelineMomentView: View {
    var timeline: GoalTimelineProjection
    var identityAccent: RunnerIdentityAccent
    var onCTA: () -> Void
    var onSkip: () -> Void

    @State private var lineProgress: CGFloat = 0

    private var headline: String { Self.headlineText(for: timeline) }

    private var subline: String { Self.sublineText }

    /// Headline copy for the goal-timeline aha moment. Single-sources the
    /// duration from `timeline.weeks` so the headline can never disagree with
    /// the timeline graphic's own week count (audit §4 Risk 6 / §10 B2 — a 5K
    /// headline hardcoded "Six weeks" while the graphic showed "in 8 weeks").
    static func headlineText(for timeline: GoalTimelineProjection) -> String {
        switch timeline.normalizedGoal {
        case .distance:
            if timeline.goalLabel.lowercased().contains("5k") {
                return "In \(timeline.weeks) weeks, you could be lining up at your first 5K."
            }
            return "In \(timeline.weeks) weeks, you could be ready for \(timeline.goalLabel.lowercased())."
        case .speed:
            return "In \(timeline.weeks) weeks, you could be running faster than today."
        case .habit:
            return "In \(timeline.weeks) weeks, running 3 times a week will start to feel normal."
        }
    }

    /// Credible framing instead of a guarantee — the old copy promised
    /// "we know you'll finish", which the product cannot honestly assure.
    static let sublineText = "Runners who stick with this plan usually get there."

    var body: some View {
        AhaMomentOverlayView(
            headline: headline,
            subline: subline,
            ctaLabel: "Let's do this",
            skipLabel: "Skip to app",
            onCTA: {
                Analytics.trackAhaMomentCTAClicked(momentId: "future_vision")
                onCTA()
            },
            onSkip: {
                Analytics.trackAhaMomentDismissed(momentId: "future_vision")
                onSkip()
            }
        ) {
            GoalTimelineGraphic(
                timeline: timeline,
                accent: identityAccent.color,
                lineProgress: lineProgress
            )
            .padding(.horizontal, 12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.35)) {
                    lineProgress = 1
                }
            }
        }
        .onAppear {
            Analytics.trackAhaMomentFired(
                momentId: "future_vision",
                context: timeline.normalizedGoal.rawValue
            )
        }
    }
}

private struct GoalTimelineGraphic: View {
    var timeline: GoalTimelineProjection
    var accent: Color
    var lineProgress: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.border)
                        .frame(height: 3)
                        .padding(.horizontal, 20)

                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, (width - 40) * lineProgress), height: 3)
                        .padding(.leading, 20)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 24)

            HStack(alignment: .top) {
                timelineNode(title: "Today", subtitle: "now", size: 14, fill: Color.textSecondary)

                Spacer()

                timelineNode(
                    title: timeline.milestoneLabel,
                    subtitle: "Wk \(timeline.milestoneWeek)",
                    size: 12,
                    fill: Color.textTertiary
                )

                Spacer()

                timelineNode(
                    title: timeline.goalLabel,
                    subtitle: "in \(timeline.weeks) weeks",
                    size: 18,
                    fill: accent,
                    emphasized: true
                )
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func timelineNode(title: String, subtitle: String, size: CGFloat, fill: Color, emphasized: Bool = false) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(fill.opacity(emphasized ? 1 : 0.85))
                .frame(width: size, height: size)
                .shadow(color: emphasized ? fill.opacity(0.35) : .clear, radius: 8)

            Text(title)
                .font(.caption.weight(emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? fill : Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 92)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }
}
