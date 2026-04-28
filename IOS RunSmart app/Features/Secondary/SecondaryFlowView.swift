import SwiftUI

struct SecondaryFlowView: View {
    var title: String

    var body: some View {
        ZStack {
            RunSmartBackground()
            VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(width: 46, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Scaffolded Flow")
                        Text(copy)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.84))
                        Button("Ask Coach About This") {}
                            .buttonStyle(NeonButtonStyle())
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next integration step")
                            .font(.headline)
                        Text("Connect this surface to the service protocol named in the integration gaps doc, then replace mock data with live API mapping.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedText)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private var copy: String {
        switch title {
        case "Workout Details":
            "Explain the session purpose, warm-up, target effort, common mistakes, and completion cues."
        case "Plan Adjustment":
            "Collect feedback, recent run data, and recovery context before proposing a safe reshuffle."
        case "Post-Run Summary":
            "Summarize distance, pace, effort, notes, and coach follow-up before saving the run."
        case "Garmin Connect", "Strava":
            "Show connection status, permissions, last sync, reconnect, and disconnect controls."
        default:
            "This native flow is intentionally present as a thin shell so the navigation contract is ready before live integrations land."
        }
    }
}

