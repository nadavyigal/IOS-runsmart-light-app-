import SwiftUI

struct WeeklyRecapView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentSuccess) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "Weekly recap", trailing: "Week 4")
                    HStack(alignment: .firstTextBaseline) {
                        Text("31.4")
                            .font(.displayLG)
                            .monospacedDigit()
                            .foregroundStyle(Color.textPrimary)
                        Text("km")
                            .font(.labelLG)
                            .foregroundStyle(Color.accentPrimary)
                        Spacer()
                        Text("+12%")
                            .font(.metricSM)
                            .foregroundStyle(Color.accentSuccess)
                    }
                    Text("You completed 4 of 5 planned sessions. The missed strength day is not critical; keep Sunday easy.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            RecapRow(title: "Best session", value: "Tempo Builder", detail: "Strong control through the middle block.", tint: .accentEnergy)
            RecapRow(title: "Load", value: "Productive", detail: "Weekly distance rose inside a safe range.", tint: .accentSuccess)
            RecapRow(title: "Next move", value: "Absorb", detail: "Next week starts with recovery and strides.", tint: .accentRecovery)
        }
    }
}

private struct RecapRow: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color

    var body: some View {
        ContentCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
                    .frame(width: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.labelSM)
                        .tracking(1.1)
                        .foregroundStyle(Color.textSecondary)
                    Text(value)
                        .font(.headingMD)
                    Text(detail)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}
