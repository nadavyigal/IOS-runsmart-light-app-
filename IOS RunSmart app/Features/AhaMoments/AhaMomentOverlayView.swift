import SwiftUI

struct AhaMomentOverlayView<Visual: View>: View {
    var headline: String
    var subline: String
    var ctaLabel: String
    var skipLabel: String = "Skip for now"
    var onCTA: () -> Void
    var onSkip: () -> Void
    @ViewBuilder var visual: () -> Visual

    @State private var showShell = false
    @State private var showBadge = false
    @State private var showHeadline = false
    @State private var showSubline = false
    @State private var showCTA = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                visual()
                    .opacity(showBadge ? 1 : 0)
                    .scaleEffect(showBadge ? 1 : 0.92)

                VStack(spacing: 12) {
                    Text(headline)
                        .font(.displayMD)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.textPrimary)
                        .opacity(showHeadline ? 1 : 0)
                        .offset(y: showHeadline ? 0 : 8)

                    Text(subline)
                        .font(.bodyLG)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.textSecondary)
                        .opacity(showSubline ? 1 : 0)
                        .offset(y: showSubline ? 0 : 8)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Button(action: onCTA) {
                        Text(ctaLabel)
                    }
                    .buttonStyle(NeonButtonStyle())
                    .opacity(showCTA ? 1 : 0)
                    .offset(y: showCTA ? 0 : 8)

                    Button(action: onSkip) {
                        Text(skipLabel)
                            .font(.bodyMD)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .opacity(showCTA ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .opacity(showShell ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                showShell = true
            }
            withAnimation(.easeOut(duration: 0.3)) {
                showBadge = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.35)) { showHeadline = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.35)) { showSubline = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.35)) { showCTA = true }
            }
        }
    }
}

extension RunnerIdentityAccent {
    var color: Color {
        switch self {
        case .endurance: return .accentSuccess
        case .speed: return .accentPrimary
        case .comeback: return .accentRecovery
        case .firstTimer: return .accentHeart
        case .balanced: return .accentPrimary
        }
    }
}
