import SwiftUI

extension Color {
    static let surfaceBase = Color(red: 0.039, green: 0.055, blue: 0.078)
    static let surfaceElevated = Color(red: 0.071, green: 0.094, blue: 0.125)
    static let surfaceCard = Color(red: 0.102, green: 0.125, blue: 0.188)

    static let accentPrimary = Color(red: 0.910, green: 1.000, blue: 0.278)
    static let accentEnergy = Color(red: 1.000, green: 0.420, blue: 0.208)
    static let accentRecovery = Color(red: 0.278, green: 0.831, blue: 1.000)
    static let accentHeart = Color(red: 1.000, green: 0.302, blue: 0.416)
    static let accentSuccess = Color(red: 0.239, green: 0.922, blue: 0.451)

    static let textPrimary = Color(red: 0.941, green: 0.949, blue: 0.961)
    static let textSecondary = Color(red: 0.541, green: 0.584, blue: 0.659)
    static let textTertiary = Color(red: 0.353, green: 0.392, blue: 0.471)
    static let border = Color(red: 0.118, green: 0.149, blue: 0.212)

    // Compatibility aliases for existing screens while Phase 2 migrates view code.
    static let ink = Color.surfaceBase
    static let inkElevated = Color.surfaceElevated
    static let inkCard = Color.surfaceCard
    static let lime = Color.accentPrimary
    static let electricGreen = Color.accentSuccess
    static let mutedText = Color.textSecondary
    static let hairline = Color.border
}

enum RunSmartSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum RunSmartRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let pill: CGFloat = 999
}

enum RunSmartBackgroundContext {
    case today(readiness: Int?)
    case plan
    case run(isRecording: Bool)
    case activity
    case profile
    case neutral

    init(tab: RunSmartTab) {
        switch tab {
        case .today:
            self = .today(readiness: nil)
        case .plan:
            self = .plan
        case .run:
            self = .run(isRecording: false)
        case .activity:
            self = .activity
        case .profile:
            self = .profile
        }
    }
}

struct RunSmartBackground: View {
    var context: RunSmartBackgroundContext = .neutral

    private var primaryGlow: Color {
        switch context {
        case .today(let readiness):
            switch readiness ?? 82 {
            case 80...100: return .accentSuccess
            case 55..<80: return .accentPrimary
            default: return .accentHeart
            }
        case .plan: return .accentRecovery
        case .run(let isRecording): return isRecording ? .clear : .accentEnergy
        case .activity: return .accentSuccess
        case .profile: return .clear
        case .neutral: return .accentPrimary
        }
    }

    private var secondaryGlow: Color {
        switch context {
        case .today: return .accentEnergy
        case .plan: return .accentPrimary
        case .run: return .accentHeart
        case .activity: return .accentRecovery
        case .profile: return .clear
        case .neutral: return .accentRecovery
        }
    }

    var body: some View {
        ZStack {
            Color.surfaceBase

            if case .profile = context {
                LinearGradient(
                    colors: [Color.surfaceBase, Color.black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                RadialGradient(
                    colors: [primaryGlow.opacity(0.18), primaryGlow.opacity(0.05), .clear],
                    center: .top,
                    startRadius: 12,
                    endRadius: 430
                )

                RadialGradient(
                    colors: [secondaryGlow.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 40,
                    endRadius: 360
                )

                LinearGradient(
                    colors: [Color.white.opacity(0.030), .clear, Color.black.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct HeroCard<Content: View>: View {
    var accent: Color = .accentPrimary
    var cornerRadius: CGFloat = RunSmartRadius.lg
    var padding: CGFloat = RunSmartSpacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.surfaceElevated)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(accent.opacity(0.020))
                    LinearGradient(
                        colors: [accent.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.72), Color.border.opacity(0.18), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: accent.opacity(0.18), radius: 24, x: 0, y: 0)
            .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 12)
    }
}

struct ContentCard<Content: View>: View {
    var cornerRadius: CGFloat = RunSmartRadius.md
    var padding: CGFloat = RunSmartSpacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 8)
    }
}

struct CompactCard<Content: View>: View {
    var cornerRadius: CGFloat = RunSmartRadius.sm
    var padding: CGFloat = RunSmartSpacing.sm
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = RunSmartRadius.md
    var padding: CGFloat = RunSmartSpacing.md
    var glow: Color?
    @ViewBuilder var content: Content

    var body: some View {
        if let glow {
            HeroCard(accent: glow, cornerRadius: max(cornerRadius, RunSmartRadius.md), padding: padding) {
                content
            }
        } else {
            ContentCard(cornerRadius: cornerRadius, padding: padding) {
                content
            }
        }
    }
}

struct NeonButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .foregroundStyle(isDestructive ? Color.textPrimary : Color.black)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: isDestructive ? [Color.accentHeart, Color.red.opacity(0.78)] : [Color.accentPrimary, Color.accentSuccess],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
            .shadow(color: (isDestructive ? Color.accentHeart : Color.accentPrimary).opacity(configuration.isPressed ? 0.18 : 0.42), radius: configuration.isPressed ? 8 : 18)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

struct SectionLabel: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.2)
                .foregroundStyle(Color.accentPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.labelSM)
                    .tracking(1.0)
                    .foregroundStyle(Color.accentPrimary)
            }
        }
    }
}

struct CoachAvatar: View {
    var size: CGFloat = 92
    var showBolt = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(colors: [Color.textPrimary.opacity(0.22), Color.surfaceCard, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: size * 0.66))
                        .foregroundStyle(Color.textPrimary.opacity(0.80), Color.accentPrimary.opacity(0.18))
                )
                .overlay(
                    Circle()
                        .trim(from: 0.08, to: 0.9)
                        .stroke(
                            AngularGradient(colors: [Color.accentEnergy, Color.accentPrimary, Color.accentSuccess], center: .center),
                            style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-72))
                )
                .shadow(color: Color.accentPrimary.opacity(0.30), radius: size * 0.14)
                .frame(width: size, height: size)

            if showBolt {
                Image(systemName: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(7)
                    .background(Color.accentPrimary)
                    .clipShape(Circle())
                    .offset(x: -2, y: -2)
            }
        }
    }
}

struct ProgressRing: View {
    var value: Double
    var lineWidth: CGFloat = 11
    var icon: String = "figure.run"
    var tint: Color = .accentPrimary

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.textPrimary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(
                    AngularGradient(colors: [Color.accentSuccess, tint, Color.accentEnergy], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(tint)
        }
    }
}

struct MetricPill: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
                .monospacedDigit()
        }
        .font(.metricXS)
        .foregroundStyle(Color.textSecondary)
    }
}

struct MetricTileView: View {
    var metric: MetricTile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.symbol)
                Text(metric.title.uppercased())
            }
            .font(.labelSM)
            .tracking(1.1)
            .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(.metric)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(metric.unit)
                    .font(.labelSM)
                    .foregroundStyle(metric.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RunSmartHeader: View {
    var title: String?
    var showLogo = false
    var showSettings = false
    var onSettingsTap: (() -> Void)?

    var body: some View {
        HStack {
            if showLogo {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Color.accentPrimary)
                    Text("RunSmart")
                        .font(.headingMD)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            if let title {
                Text(title)
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            Group {
                if showSettings, let onSettingsTap {
                    Button(action: onSettingsTap) {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(Color.textPrimary.opacity(0.78))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: showSettings ? "gearshape" : "bell")
                        .font(.title3)
                        .foregroundStyle(Color.textPrimary.opacity(0.78))
                        .overlay(alignment: .topTrailing) {
                            if !showSettings {
                                Circle()
                                    .fill(Color.accentPrimary)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
            }
            if !showSettings {
                CoachAvatar(size: 38)
            }
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: RunSmartTab
    @Namespace private var indicator

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(RunSmartTab.allCases) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    RunSmartHaptics.light()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                } label: {
                    if tab == .run {
                        runButton(isSelected: selectedTab == tab)
                    } else {
                        tabButton(tab, isSelected: selectedTab == tab)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.surfaceBase.opacity(0.82))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.border)
                        .frame(height: 1)
                }
        )
    }

    private func tabButton(_ tab: RunSmartTab, isSelected: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: isSelected ? tab.filledSymbol : tab.symbol)
                .font(.system(size: 21, weight: .semibold))
                .frame(width: 44, height: 32)
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.accentPrimary)
                        .matchedGeometryEffect(id: "tab-dot", in: indicator)
                } else {
                    Capsule()
                        .fill(.clear)
                }
            }
            .frame(width: 5, height: 5)
        }
        .foregroundStyle(isSelected ? Color.accentPrimary : Color.textSecondary)
        .accessibilityLabel(tab.rawValue)
    }

    private func runButton(isSelected: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: isSelected ? RunSmartTab.run.filledSymbol : RunSmartTab.run.symbol)
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(Color.black)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentPrimary, Color.accentEnergy],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color.accentPrimary.opacity(isSelected ? 0.52 : 0.28), radius: isSelected ? 18 : 10)
                .scaleEffect(isSelected ? 1.04 : 1.0)

            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.accentPrimary)
                        .matchedGeometryEffect(id: "tab-dot", in: indicator)
                } else {
                    Capsule()
                        .fill(.clear)
                }
            }
            .frame(width: 5, height: 5)
        }
        .offset(y: -18)
        .accessibilityLabel(RunSmartTab.run.rawValue)
    }
}
