import SwiftUI

struct ZoneAnalysisView: View {
    private let zones: [(String, Double, Color, String)] = [
        ("Z1 Recovery", 0.18, .accentRecovery, "18%"),
        ("Z2 Easy", 0.46, .accentSuccess, "46%"),
        ("Z3 Tempo", 0.22, .accentPrimary, "22%"),
        ("Z4 Hard", 0.11, .accentEnergy, "11%"),
        ("Z5 Max", 0.03, .accentHeart, "3%")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentHeart) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Zone analysis")
                    Text("Effort distribution")
                        .font(.headingLG)
                    Text("Most training is easy, with enough tempo stimulus to move the goal forward.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(zones, id: \.0) { zone in
                        ZoneRow(title: zone.0, value: zone.1, tint: zone.2, label: zone.3)
                    }
                }
            }
        }
    }
}

private struct ZoneRow: View {
    var title: String
    var value: Double
    var tint: Color
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.bodyMD.weight(.semibold))
                Spacer()
                Text(label)
                    .font(.metricXS)
                    .foregroundStyle(tint)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceElevated)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(8, proxy.size.width * value))
                }
            }
            .frame(height: 9)
        }
    }
}
