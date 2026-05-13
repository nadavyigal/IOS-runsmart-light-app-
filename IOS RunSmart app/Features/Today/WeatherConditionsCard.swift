import SwiftUI

struct WeatherConditionsCard: View {
    var body: some View {
        ContentCard {
            HStack(spacing: 14) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(Color.surfaceElevated, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "Weather & conditions")
                    Text("20°C · 11 km/h wind · 54% humidity")
                        .font(.metricXS)
                        .foregroundStyle(Color.textPrimary)
                    Text("Good conditions for a controlled tempo run.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }
}
