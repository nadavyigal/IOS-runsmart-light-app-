import SwiftUI

struct MorningCheckinView: View {
    @State private var energy = 7.0
    @State private var soreness = 3.0
    @State private var mood = "Steady"

    private let moods = ["Strong", "Steady", "Tired", "Stressed"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Morning check-in")
                    Text("How ready do you feel before today’s training?")
                        .font(.headingLG)
                    Text("This adjusts workout intensity without storing medical records.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            CheckinSlider(title: "Energy", value: $energy, tint: .accentSuccess)
            CheckinSlider(title: "Soreness", value: $soreness, tint: .accentEnergy)

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Mood")
                    HStack(spacing: 8) {
                        ForEach(moods, id: \.self) { option in
                            Button { mood = option } label: {
                                Text(option)
                                    .font(.labelSM)
                                    .tracking(1.0)
                                    .foregroundStyle(mood == option ? Color.black : Color.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(mood == option ? Color.accentPrimary : Color.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                RunSmartHaptics.success()
            } label: {
                Label("Save Check-In", systemImage: "checkmark")
            }
            .buttonStyle(NeonButtonStyle())
        }
    }
}

private struct CheckinSlider: View {
    var title: String
    @Binding var value: Double
    var tint: Color

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: title)
                    Text("\(Int(value))/10")
                        .font(.metricSM)
                        .foregroundStyle(tint)
                }
                Slider(value: $value, in: 1...10, step: 1)
                    .tint(tint)
            }
        }
    }
}
