import SwiftUI

struct BadgeCabinetView: View {
    private let badges: [Achievement] = [
        .init(title: "Threshold PR", subtitle: "Earned", symbol: "bolt.fill", tint: .accentPrimary),
        .init(title: "Early Riser", subtitle: "Earned", symbol: "sunrise.fill", tint: .accentEnergy),
        .init(title: "Consistency", subtitle: "Earned", symbol: "checkmark.seal.fill", tint: .accentSuccess),
        .init(title: "Long Run", subtitle: "Locked", symbol: "road.lanes", tint: .textTertiary),
        .init(title: "Race Day", subtitle: "Locked", symbol: "flag.checkered", tint: .textTertiary),
        .init(title: "Recovery Pro", subtitle: "Locked", symbol: "moon.fill", tint: .textTertiary)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Badge cabinet")
                    Text("Runner identity, earned over time")
                        .font(.headingLG)
                    Text("Badges are designed for shareable moments and long-term motivation.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(badges) { badge in
                    BadgeCabinetTile(achievement: badge)
                }
            }
        }
    }
}

private struct BadgeCabinetTile: View {
    var achievement: Achievement

    private var isLocked: Bool {
        achievement.subtitle == "Locked"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: achievement.symbol)
                .font(.title2.bold())
                .foregroundStyle(isLocked ? Color.textTertiary : achievement.tint)
                .frame(width: 64, height: 64)
                .background((isLocked ? Color.surfaceElevated : achievement.tint.opacity(0.12)), in: Circle())
                .overlay(Circle().stroke(isLocked ? Color.border : achievement.tint, lineWidth: 2))
            Text(achievement.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(achievement.subtitle.uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(isLocked ? Color.textTertiary : Color.accentPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 136)
    }
}
