import SwiftUI

enum RunSmartBrand {
    static let appName = "RunSmart"
    static let promise = "Premium AI running coach"
    static let primaryLime = Color.accentPrimary
    static let background = Color.surfaceBase
    static let card = Color.surfaceDeepCard
    static let secondaryCard = Color.surfaceGreenBlack
    static let textPrimary = Color.textPrimary
    static let textSecondary = Color.textSecondary
    static let success = Color.accentPrimary
    static let warning = Color.accentAmber
    static let recovery = Color.accentRecovery
    static let error = Color.accentHeart
}

enum RunSmartBrandMode {
    case iconOnly
    case compact
    case full
}

struct RunSmartWordmark: View {
    var mode: RunSmartBrandMode = .full
    var size: CGFloat = 46
    var glow = false

    var body: some View {
        HStack(spacing: mode == .compact ? 8 : 10) {
            RunSmartLogoMark(size: size, filled: false, glow: glow)

            if mode != .iconOnly {
                Text(RunSmartBrand.appName)
                    .font(.system(size: mode == .compact ? size * 0.38 : size * 0.46, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RunSmartBrand.appName)
    }
}

struct RunSmartAppBadge: View {
    var mode: RunSmartBrandMode = .compact
    var size: CGFloat = 58
    var glow = true

    var body: some View {
        HStack(spacing: 10) {
            RunSmartLogoMark(size: size, filled: false, glow: glow)

            if mode == .full {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RunSmartBrand.appName)
                        .font(.headingMD.weight(.heavy))
                        .italic()
                    Text(RunSmartBrand.promise.uppercased())
                        .font(.labelSM)
                        .foregroundStyle(Color.accentPrimary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            } else if mode == .compact {
                Text(RunSmartBrand.appName)
                    .font(.headingMD.weight(.heavy))
                    .italic()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, mode == .iconOnly ? 0 : 14)
        .padding(.vertical, mode == .iconOnly ? 0 : 10)
        .background {
            if mode != .iconOnly {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.surfaceDeepCard.opacity(0.90))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.accentPrimary.opacity(0.22), lineWidth: 1))
            }
        }
        .shadow(color: Color.accentPrimary.opacity(glow ? 0.20 : 0), radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RunSmartBrand.appName)
    }
}

struct RunSmartLaunchLogo: View {
    var size: CGFloat = 190
    var glow = true

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentPrimary.opacity(glow ? 0.18 : 0))
                .blur(radius: 44)
                .frame(width: size * 1.20, height: size * 1.20)

            Image("RunSmartLaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        }
        .accessibilityLabel("RunSmart launch logo")
    }
}

struct RunSmartBrandHeader: View {
    var subtitle: String?
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            RunSmartWordmark(mode: compact ? .compact : .full, size: compact ? 34 : 42, glow: true)
            Spacer(minLength: 10)
            if let subtitle, !compact {
                Text(subtitle)
                    .font(.labelSM)
                    .foregroundStyle(Color.accentPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minHeight: compact ? 44 : 54)
    }
}

struct RunSmartLaunchView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            RunSmartBackground(context: .neutral)

            VStack(spacing: 26) {
                RunSmartLaunchLogo(size: 210)
                    .scaleEffect(animate ? 1 : 0.95)
                    .opacity(animate ? 1 : 0.88)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.accentPrimary, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 168, height: 3)
                    .offset(x: animate ? 42 : -42)
                    .opacity(animate ? 0.95 : 0.35)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct RunSmartMetricCard: View {
    var title: String
    var value: String
    var unit: String
    var symbol: String
    var tint: Color = .accentPrimary

    var body: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14, accent: tint) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title.uppercased(), systemImage: symbol)
                    .font(.labelSM)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.metric)
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RunSmartPrimaryButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .font(.buttonLabel)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(colors: [Color.accentPrimary, Color.accentLime], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: Color.accentPrimary.opacity(0.36), radius: 18)
        }
        .buttonStyle(.plain)
    }
}
