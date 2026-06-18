import SwiftUI

struct RunnerIdentityMomentView: View {
    var identity: RunnerIdentityPresentation
    var onCTA: () -> Void
    var onSkip: () -> Void

    var body: some View {
        AhaMomentOverlayView(
            headline: identity.headline,
            subline: identity.subline,
            ctaLabel: identity.ctaLabel,
            onCTA: {
                Analytics.trackAhaMomentCTAClicked(momentId: "knows_me")
                onCTA()
            },
            onSkip: {
                Analytics.trackAhaMomentDismissed(momentId: "knows_me")
                onSkip()
            }
        ) {
            VStack(spacing: 14) {
                Image(systemName: identity.symbolName)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(identity.accent.color)
                    .frame(width: 88, height: 88)
                    .background(identity.accent.color.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(identity.accent.color.opacity(0.45), lineWidth: 2))

                Text(identity.label)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(identity.accent.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.surfaceCard.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(identity.accent.color.opacity(0.35), lineWidth: 1))
            }
        }
        .onAppear {
            Analytics.trackAhaMomentFired(momentId: "knows_me", context: identity.kind.rawValue)
        }
    }
}
