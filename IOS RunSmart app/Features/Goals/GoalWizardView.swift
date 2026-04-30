import SwiftUI

struct GoalWizardView: View {
    @State private var goal = "10K PR"
    @State private var weeklyRuns = 4.0
    @State private var targetDate = Date().addingTimeInterval(60 * 60 * 24 * 84)

    private let goals = ["First 5K", "10K PR", "Half Marathon", "Marathon", "Just Run More"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentEnergy) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Goal setting wizard")
                    Text("Choose the next training block")
                        .font(.headingLG)
                    Text("The coach uses this to tune weekly load, workout mix, and reminders.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(goals, id: \.self) { option in
                    Button { goal = option } label: {
                        GoalChoiceCard(title: option, selected: goal == option)
                    }
                    .buttonStyle(.plain)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Weekly rhythm")
                    Stepper(value: $weeklyRuns, in: 2...7, step: 1) {
                        HStack {
                            Text("Runs per week")
                            Spacer()
                            Text("\(Int(weeklyRuns))")
                                .font(.metricSM)
                                .foregroundStyle(Color.accentPrimary)
                        }
                    }
                    .tint(Color.accentPrimary)
                    DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                        .tint(Color.accentPrimary)
                }
            }

            Button { RunSmartHaptics.success() } label: {
                Label("Create Goal", systemImage: "target")
            }
            .buttonStyle(NeonButtonStyle())
        }
    }
}

private struct GoalChoiceCard: View {
    var title: String
    var selected: Bool

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentPrimary : Color.textTertiary)
                Text(title)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous)
                .stroke(selected ? Color.accentPrimary : .clear, lineWidth: 1.5)
        )
    }
}
