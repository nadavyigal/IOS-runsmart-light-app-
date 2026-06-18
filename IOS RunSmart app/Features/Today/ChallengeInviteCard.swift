import SwiftUI

struct ChallengeInviteCard: View {
    var onEnrolled: () -> Void

    @State private var showDetail = false

    private let challenge = ChallengeItem.foundation21Day

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentEnergy) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentEnergy.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.accentEnergy)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEW RUNNER")
                            .font(.labelSM)
                            .tracking(1.4)
                            .foregroundStyle(Color.textSecondary)
                        Text(challenge.title)
                            .font(.bodyLG.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                    }

                    Spacer(minLength: 0)
                }

                Text(challenge.description)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showDetail = true
                } label: {
                    HStack {
                        Text("Start the Challenge")
                            .font(.bodyMD.weight(.bold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color.accentEnergy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showDetail) {
            ChallengeDetailView(challenge: challenge, onEnrolled: {
                showDetail = false
                onEnrolled()
            })
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        RunSmartBackground()
        ChallengeInviteCard(onEnrolled: {})
            .padding(.horizontal, 18)
    }
    .environmentObject(SupabaseSession())
    .environment(\.runSmartServices, MockRunSmartServices())
}
#endif
