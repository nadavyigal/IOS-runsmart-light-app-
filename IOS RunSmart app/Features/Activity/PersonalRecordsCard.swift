import SwiftUI

struct PersonalRecordsCard: View {
    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Personal records", trailing: "PR")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    PersonalRecordTile(distance: "5K", time: "23:48", tint: .accentPrimary)
                    PersonalRecordTile(distance: "10K", time: "49:15", tint: .accentEnergy)
                    PersonalRecordTile(distance: "Half", time: "1:51:02", tint: .accentRecovery)
                    PersonalRecordTile(distance: "Marathon", time: "--", tint: .textTertiary)
                }
            }
        }
    }
}

struct PersonalRecordTile: View {
    var distance: String
    var time: String
    var tint: Color

    var body: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(distance.uppercased())
                        .font(.labelSM)
                        .tracking(1.1)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                }
                Text(time)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}
