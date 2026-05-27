import SwiftUI

struct GentleCoachInterventionCard: View {
    var onTalkToCoach: () -> Void
    var onContinue: () -> Void

    var body: some View {
        RunSmartPanel(cornerRadius: 18, padding: 16, accent: .accentRecovery) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentRecovery)
                    Text("This week has needed adjusting a few times")
                        .font(.headingMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                }

                Text("Want to talk through what's going on? Coach can look at the full picture and suggest a more sustainable approach.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: talkToCoach) {
                        Text("Talk to Coach")
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.accentRecovery, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: continueToAdjust) {
                        Text("Just adjust this week")
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.accentRecovery)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().stroke(Color.accentRecovery, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            RunSmartAnalytics.flexWeekInterventionShown()
        }
    }

    private func talkToCoach() {
        RunSmartAnalytics.flexWeekInterventionAction(.talkToCoach)
        onTalkToCoach()
    }

    private func continueToAdjust() {
        RunSmartAnalytics.flexWeekInterventionAction(.continueToPicker)
        onContinue()
    }
}

#if DEBUG
#Preview("Gentle Intervention") {
    GentleCoachInterventionCard(
        onTalkToCoach: {},
        onContinue: {}
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif
