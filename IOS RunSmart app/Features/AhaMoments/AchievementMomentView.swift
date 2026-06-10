import SwiftUI

struct AchievementMomentView: View {
    var context: AchievementContext
    var recordContext: String
    var onDismiss: () -> Void

    @State private var visible = false
    @State private var showLabel = false
    @State private var showCopy = false
    @State private var didDismiss = false

    private static let autoDismissSeconds: TimeInterval = 4.5

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if showsCounter {
                    AnimatedCounterText(
                        from: counterFrom,
                        to: counterTo,
                        suffix: " km"
                    )
                    .opacity(showLabel ? 1 : 0)

                    Text(counterLabel)
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                        .opacity(showLabel ? 1 : 0)
                }

                VStack(spacing: 10) {
                    Text(copy.headline)
                        .font(.displayMD)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.textPrimary)
                    Text(copy.subline)
                        .font(.bodyLG)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 28)
                .opacity(showCopy ? 1 : 0)

                Text("Tap anywhere to continue")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 8)
                    .opacity(showCopy ? 1 : 0)
            }
            .opacity(visible ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissMoment() }
        .onAppear {
            Analytics.trackAhaMomentFired(momentId: "achievement", context: analyticsContext)
            withAnimation(.easeOut(duration: 0.3)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.25)) { showLabel = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.25)) { showCopy = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissSeconds) {
                dismissMoment()
            }
        }
    }

    private var showsCounter: Bool {
        switch context {
        case .personalBest, .firstRun: return true
        case .showedUp: return false
        }
    }

    private var counterFrom: Double {
        switch context {
        case .personalBest(_, let previous): return previous
        case .firstRun: return 0
        case .showedUp: return 0
        }
    }

    private var counterTo: Double {
        switch context {
        case .personalBest(let distanceKm, _): return distanceKm
        case .firstRun(let distanceKm): return distanceKm
        case .showedUp: return 0
        }
    }

    private var counterLabel: String {
        switch context {
        case .firstRun: return "First run"
        case .personalBest: return "New personal best"
        case .showedUp: return ""
        }
    }

    private var copy: (headline: String, subline: String) {
        switch context {
        case .firstRun:
            return (
                "You showed up. That's the hardest part.",
                "It gets easier from here — but you'll always remember this one."
            )
        case .personalBest:
            return (
                "You just ran further than you ever have.",
                "We noticed. That wasn't on anyone's schedule — it just happened."
            )
        case .showedUp:
            return (
                "You started.",
                "That's not nothing. Most people didn't."
            )
        }
    }

    private var analyticsContext: String {
        switch context {
        case .firstRun: return "first_run"
        case .personalBest: return "personal_best"
        case .showedUp: return "showed_up"
        }
    }

    private func dismissMoment() {
        guard !didDismiss else { return }
        didDismiss = true
        Analytics.trackAhaMomentDismissed(momentId: "achievement")
        Task {
            await AhaMomentStore.shared.record(
                momentId: "achievement",
                context: recordContext,
                variant: "C"
            )
        }
        onDismiss()
    }
}
