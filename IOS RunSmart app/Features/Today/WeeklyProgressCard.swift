// IOS RunSmart app/Features/Today/WeeklyProgressCard.swift
import SwiftUI

struct WeeklyProgressCard: View {
    let summary: WeeklyProgressSummary
    var onTapCoach: (() -> Void)? = nil

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Label("WEEK IN REVIEW", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    StatusChip(
                        text: summary.source == .ai ? "AI" : "Summary",
                        tint: summary.source == .ai ? .accentPrimary : .textSecondary
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.weekLabel)
                        .font(.labelSM)
                        .foregroundStyle(Color.textSecondary)
                    Text(summary.headline)
                        .font(.title3.bold())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                Text(summary.narrative)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT WEEK")
                        .font(.labelSM)
                        .foregroundStyle(Color.textTertiary)
                    Text(summary.forwardLook)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onTapCoach {
                    Button(action: onTapCoach) {
                        Label("Ask Coach", systemImage: "bubble.left")
                            .font(.buttonLabel)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview("With coach button") {
    WeeklyProgressCard(
        summary: WeeklyProgressSummary(
            headline: "3 runs · 18.5 km",
            narrative: "You held easy pace across all three runs this week even as total distance stepped up 15%. Your aerobic base is absorbing the load.",
            forwardLook: "Next week's long run is where this base starts to pay off.",
            weekLabel: "Week 4 of your plan",
            generatedDate: Date(),
            isoWeekKey: "2026-W21",
            source: .ai
        ),
        onTapCoach: {}
    )
    .padding()
}

#Preview("Without coach button") {
    WeeklyProgressCard(
        summary: WeeklyProgressSummary(
            headline: "2 runs · 11.2 km",
            narrative: "A quieter week — two solid runs logged. Quality over quantity.",
            forwardLook: "Keep the easy effort and let the aerobic base compound.",
            weekLabel: "This week",
            generatedDate: Date(),
            isoWeekKey: "2026-W21",
            source: .fallback
        )
    )
    .padding()
}
