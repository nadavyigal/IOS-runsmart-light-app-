import SwiftUI

struct GarminWellnessViews: View {
    private let panels: [(String, String, String, Color, String)] = [
        ("HRV Status", "Balanced", "64 ms avg over 7 days", .accentHeart, "waveform.path.ecg"),
        ("Sleep Analytics", "82%", "Deep sleep improved 14%", .accentRecovery, "bed.double.fill"),
        ("Body Battery", "76", "Enough reserve for tempo", .accentSuccess, "battery.75percent"),
        ("Stress", "Low", "Best window: before 10 AM", .accentPrimary, "brain.head.profile")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentRecovery) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Garmin wellness")
                    Text("Connected health signals")
                        .font(.headingLG)
                    Text("Panels mirror the web wellness dashboard and keep coaching recommendations explainable.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            ForEach(panels, id: \.0) { panel in
                WellnessPanel(title: panel.0, value: panel.1, detail: panel.2, tint: panel.3, symbol: panel.4)
            }
        }
    }
}

private struct WellnessPanel: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color
    var symbol: String

    var body: some View {
        ContentCard {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headingMD)
                    Text(detail)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text(value)
                    .font(.metricSM)
                    .foregroundStyle(tint)
            }
        }
    }
}
