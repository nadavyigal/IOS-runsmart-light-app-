import SwiftUI

struct ChallengeProgressCard: View {
    var challenge: ChallengeSummary
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 34, height: 34)
                            .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title.uppercased())
                                .font(.labelSM)
                                .tracking(1.4)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(challenge.dayLabel)
                                .font(.bodyMD.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textSecondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.accentPrimary)
                                .frame(width: geo.size.width * max(0, min(1, challenge.progress)), height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text(motivationLine)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var motivationLine: String {
        switch challenge.progress {
        case 0..<0.25:
            return "Every run is a deposit. Keep building."
        case 0.25..<0.5:
            return "You're through the hardest part. The habit is forming."
        case 0.5..<0.75:
            return "Past the halfway mark. Your body is adapting."
        default:
            return "Almost there. Finish what you started."
        }
    }
}

#Preview {
    ZStack {
        RunSmartBackground()
        ChallengeProgressCard(
            challenge: ChallengeSummary(
                id: "preview",
                title: "21-Day Running Foundation",
                detail: "From zero to 30 minutes.",
                progress: 0.48,
                dayLabel: "Day 10 of 21",
                isActive: true
            ),
            onTap: {}
        )
        .padding(.horizontal, 18)
    }
}
