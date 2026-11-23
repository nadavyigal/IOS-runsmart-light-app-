import SwiftUI

// C7.16 milestone tags and one-tap praise, under a Coach Today row. Shown only while Coach v2 is on:
// the snapshot has no milestones otherwise, so there is no header and no empty strip.

struct CoachMilestoneStrip: View {
    let athleteName: String
    let milestones: [CoachMilestone]
    let isReacted: (CoachMilestone) -> Bool
    let hasFailed: (CoachMilestone) -> Bool
    let react: (CoachMilestone, CoachReaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(milestones) { milestone in
                CoachMilestoneLine(
                    athleteName: athleteName, milestone: milestone, reacted: isReacted(milestone),
                    failed: hasFailed(milestone), react: { react(milestone, $0) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
    }
}

private struct CoachMilestoneLine: View {
    let athleteName: String
    let milestone: CoachMilestone
    let reacted: Bool
    let failed: Bool
    let react: (CoachReaction) -> Void
    @Environment(\.dynamicTypeSize) private var size

    private var tint: Color { milestone.kind.canPraise ? Color.accentSuccess : Color.textSecondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Icon plus text: the tag never relies on color.
                Label(milestone.kind.tag, systemImage: milestone.kind.icon)
                    .font(.labelLG)
                    .foregroundStyle(tint)
                if reacted {
                    Label("Reacted", systemImage: "checkmark")
                        .font(.labelLG)
                        .foregroundStyle(Color.textSecondary)
                } else if !milestone.kind.canPraise {
                    Text("Only you see this").font(.labelSM).foregroundStyle(Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenTag)
            if milestone.kind.canPraise && !reacted {
                // Three one-tap reactions. Stacked from XXL so each stays a 44 pt target.
                let layout = size >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ForEach(CoachReaction.allCases) { reaction in
                        Button { react(reaction) } label: {
                            Text(reaction.text)
                                .font(.labelLG)
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Color.surfaceCard, in: Capsule())
                                .overlay(Capsule().stroke(Color.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send \(reaction.spoken) to \(athleteName)")
                        .accessibilityHint("Saves a note on \(milestone.kind.tag.lowercased()) that \(athleteName) sees")
                    }
                }
                if failed {
                    Text("Couldn't send. Try again.").font(.labelSM).foregroundStyle(Color.accentHeart)
                }
            }
        }
    }

    private var spokenTag: String {
        if reacted { return "\(milestone.kind.tag). Reacted." }
        return milestone.kind.canPraise ? milestone.kind.tag : "\(milestone.kind.tag). Only you see this."
    }
}
