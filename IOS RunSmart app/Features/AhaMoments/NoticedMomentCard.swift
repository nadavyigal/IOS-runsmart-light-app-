import SwiftUI

struct NoticedMomentCard: View {
    var context: NoticeContextKind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(copy.headline)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(copy.subline)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surfaceCard.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor)
                .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .onAppear {
            Analytics.trackAhaMomentFired(momentId: "noticed", context: context.contextKey)
        }
    }

    private var accentColor: Color {
        switch context {
        case .streak, .thirdRunWeek: return .accentSuccess
        case .comeback: return .accentRecovery
        case .highEffort: return .accentPrimary
        case .categoryFirst: return .accentPrimary
        case .earlyMorning, .lateNight: return .textSecondary
        }
    }

    private var symbolName: String {
        switch context {
        case .streak: return "flame.fill"
        case .categoryFirst: return "flag.checkered"
        case .comeback: return "arrow.counterclockwise"
        case .highEffort: return "bolt.fill"
        case .earlyMorning: return "sunrise.fill"
        case .lateNight: return "moon.stars.fill"
        case .thirdRunWeek: return "calendar"
        }
    }

    private var copy: (headline: String, subline: String) {
        switch context {
        case .streak(let days):
            if days == 7 {
                return (
                    "Seven days straight.",
                    "The streak everyone talks about — the one you almost didn't start."
                )
            }
            if days == 3 {
                return (
                    "Three days straight.",
                    "The streak has started. This is how habits form."
                )
            }
            return (
                "\(days) days in a row.",
                "Consistency like this is rare. Keep showing up."
            )
        case .categoryFirst(_, let label):
            return (
                label + ".",
                "Most people talk about it. You just did it."
            )
        case .comeback(let daysSince):
            if daysSince >= 10 {
                return (
                    "Ten days off, and you came back.",
                    "That's harder than never stopping."
                )
            }
            return (
                "You're back.",
                "Gaps aren't failures. Getting back out is what matters."
            )
        case .highEffort(let percentAbove):
            return (
                "We noticed you ran harder than usual today.",
                "So did your legs, probably. Good."
            )
        case .earlyMorning:
            return (
                "You were running before sunrise.",
                "We don't know why. We're glad you were."
            )
        case .lateNight:
            return (
                "You ran tonight.",
                "Whatever was in the way — you went anyway."
            )
        case .thirdRunWeek:
            return (
                "Three runs this week.",
                "That's the habit. You're building it."
            )
        }
    }
}
