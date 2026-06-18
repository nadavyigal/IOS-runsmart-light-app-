import SwiftUI

extension Color {
    static let surfaceBase = Color(red: 0.024, green: 0.024, blue: 0.039) // #06060A
    static let surfaceElevated = Color(red: 0.047, green: 0.047, blue: 0.078) // #0C0C14
    static let surfaceCard = Color(red: 0.067, green: 0.067, blue: 0.110) // #11111C
    static let surfaceDeepCard = Color(red: 0.012, green: 0.018, blue: 0.016) // #030504
    static let surfaceGreenBlack = Color(red: 0.016, green: 0.055, blue: 0.035) // #040E09

    static let accentPrimary = Color(red: 0.800, green: 1.000, blue: 0.000) // #CCFF00
    static let accentLime = Color(red: 0.750, green: 1.000, blue: 0.000) // #BFFF00
    static let accentEnergy = Color(red: 0.984, green: 0.573, blue: 0.235) // #FB923C
    static let accentRecovery = Color(red: 0.376, green: 0.647, blue: 0.980) // #60A5FA
    static let accentHeart = Color(red: 0.984, green: 0.443, blue: 0.522) // #FB7185
    static let accentSuccess = Color(red: 0.176, green: 0.863, blue: 0.510) // #2DDC82

    static let textPrimary = Color(red: 0.949, green: 0.949, blue: 1.000) // #F2F2FF
    static let textSecondary = Color(red: 0.522, green: 0.522, blue: 0.620)
    static let textTertiary = Color(red: 0.314, green: 0.314, blue: 0.400)
    static let border = Color.white.opacity(0.07)

    static let accentAmber = Color(red: 0.984, green: 0.573, blue: 0.235)
    static let accentMagenta = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let borderSubtle = Color.white.opacity(0.05)
    static let shimmer = Color.white.opacity(0.08)

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
    static let sm: CGFloat = 14
    static let md: CGFloat = 20
    static let lg: CGFloat = 28
    static let pill: CGFloat = 999
}

enum RunSmartBackgroundContext {
    case today(readiness: Int?)
    case plan
    case run(isRecording: Bool)
    case report
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
        case .report:
            self = .report
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
        case .report: return .accentSuccess
        case .profile: return .clear
        case .neutral: return .accentPrimary
        }
    }

    private var secondaryGlow: Color {
        switch context {
        case .today: return .accentEnergy
        case .plan: return .accentPrimary
        case .run: return .accentHeart
        case .report: return .accentRecovery
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

struct RunSmartLogoMark: View {
    var size: CGFloat = 34
    var filled = true
    var glow = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    filled
                    ? LinearGradient(colors: [Color.accentPrimary, Color.accentLime], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color.surfaceGreenBlack, Color.surfaceDeepCard], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .stroke(Color.accentPrimary.opacity(filled ? 0 : 0.85), lineWidth: max(1, size * 0.045))
                )

            Text("RS")
                .font(.system(size: size * 0.37, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(filled ? Color.black : Color.accentPrimary)
                .offset(x: size * 0.01, y: -size * 0.02)

            Capsule(style: .continuous)
                .fill(filled ? Color.black.opacity(0.86) : Color.accentPrimary)
                .frame(width: size * 0.50, height: max(2, size * 0.065))
                .rotationEffect(.degrees(-24))
                .offset(x: size * 0.10, y: size * 0.24)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.accentPrimary.opacity(glow ? 0.34 : 0), radius: size * 0.34)
    }
}

struct RunSmartIconMark: View {
    var size: CGFloat = 34
    var tint: Color = .accentPrimary
    var selected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? tint : Color.surfaceElevated)
                .overlay(Circle().stroke(tint.opacity(selected ? 0 : 0.50), lineWidth: 1))
            Text("RS")
                .font(.system(size: size * 0.28, weight: .black, design: .rounded))
                .foregroundStyle(selected ? Color.black : tint)
            Capsule(style: .continuous)
                .fill(selected ? Color.black.opacity(0.82) : tint)
                .frame(width: size * 0.34, height: max(2, size * 0.055))
                .rotationEffect(.degrees(-24))
                .offset(x: size * 0.05, y: size * 0.18)
        }
        .frame(width: size, height: size)
    }
}

struct RunSmartTopBar: View {
    var title: String?
    var showBrand = false
    var showSettings = false
    var onSettingsTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showBrand {
                RunSmartWordmark(mode: .compact, size: 36, glow: true)
            } else if let title {
                Text(title)
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                RunSmartLogoMark(size: 34)
            }

            Spacer()

            if showSettings {
                Button(action: { onSettingsTap?() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "bell")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 36, height: 44)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color.accentPrimary)
                            .frame(width: 9, height: 9)
                            .offset(x: -4, y: 9)
                    }
                CoachAvatar(size: 42)
            }
        }
        .frame(minHeight: 48)
    }
}

struct RunSmartPanel<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    var accent: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.surfaceElevated.opacity(0.86))
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            (accent ?? Color.accentPrimary).opacity(accent == nil ? 0.015 : 0.08),
                            Color.black.opacity(0.10)
                        ],
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
                            colors: [Color.white.opacity(0.16), (accent ?? Color.border).opacity(0.64), Color.border.opacity(0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: (accent ?? Color.black).opacity(accent == nil ? 0.20 : 0.18), radius: accent == nil ? 10 : 20, x: 0, y: 10)
    }
}

struct CoachGlowBadge: View {
    var symbol: String = "sparkles"
    var size: CGFloat = 52

    var body: some View {
        RunSmartIconMark(size: size, tint: .accentPrimary, selected: false)
            .shadow(color: Color.accentPrimary.opacity(0.45), radius: size * 0.32)
    }
}

struct MetricBars: View {
    var values: [CGFloat] = [0.25, 0.48, 0.66, 0.88, 0.50, 0.36, 0.72]
    var tint: Color = .accentPrimary

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(tint.opacity(value > 0.55 ? 0.92 : 0.48))
                    .frame(width: 4, height: max(5, value * 28))
            }
        }
        .frame(height: 30, alignment: .bottom)
    }
}

struct RunSmartSparkline: View {
    var values: [Double]
    var tint: Color = .accentPrimary

    var body: some View {
        GeometryReader { geo in
            let maxVal = values.max() ?? 1
            let minVal = values.min() ?? 0
            let range = max(maxVal - minVal, 1)
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))

            Path { path in
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * step
                    let y = geo.size.height * (1 - CGFloat((value - minVal) / range))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct RunSmartRoutePreview: View {
    var title: String?
    var showGPS = false
    var height: CGFloat = 132

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.26))

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                Path { path in
                    for index in 0..<7 {
                        let y = h * (0.18 + CGFloat(index) * 0.11)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y + (index.isMultiple(of: 2) ? 16 : -10)))
                    }
                    for index in 0..<5 {
                        let x = w * (0.12 + CGFloat(index) * 0.20)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + 22, y: h))
                    }
                }
                .stroke(Color.white.opacity(0.045), lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.78))
                    path.addCurve(to: CGPoint(x: w * 0.38, y: h * 0.58), control1: CGPoint(x: w * 0.20, y: h * 0.66), control2: CGPoint(x: w * 0.29, y: h * 0.61))
                    path.addCurve(to: CGPoint(x: w * 0.62, y: h * 0.46), control1: CGPoint(x: w * 0.48, y: h * 0.55), control2: CGPoint(x: w * 0.54, y: h * 0.51))
                    path.addCurve(to: CGPoint(x: w * 0.82, y: h * 0.17), control1: CGPoint(x: w * 0.74, y: h * 0.38), control2: CGPoint(x: w * 0.77, y: h * 0.22))
                }
                .stroke(Color.accentPrimary, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.accentPrimary.opacity(0.65), radius: 10)

                Circle()
                    .fill(Color.accentSuccess)
                    .frame(width: 20, height: 20)
                    .position(x: w * 0.12, y: h * 0.78)
                Circle()
                    .fill(Color.textPrimary)
                    .frame(width: 15, height: 15)
                    .position(x: w * 0.82, y: h * 0.17)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let title {
                VStack {
                    HStack {
                        Label(title, systemImage: showGPS ? "location.fill" : "map")
                            .font(.caption.bold())
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.surfaceElevated.opacity(0.88), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.border.opacity(0.9), lineWidth: 1))
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
                    RunSmartLogoMark(size: size * 0.62, filled: false)
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
                RunSmartIconMark(size: max(24, size * 0.28), tint: .accentPrimary, selected: true)
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
                RunSmartWordmark(mode: .compact, size: 36, glow: true)
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
        .padding(.top, 10)
        .padding(.bottom, 9)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color.surfaceElevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.white.opacity(0.13), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.34), radius: 20, x: 0, y: 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func tabButton(_ tab: RunSmartTab, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            RunSmartIconMark(size: 32, tint: isSelected ? .accentPrimary : .textSecondary, selected: isSelected)
                .frame(width: 44, height: 32)
            Text(tab.rawValue)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(isSelected ? Color.accentPrimary : Color.textSecondary)
        .frame(height: 52)
        .accessibilityLabel(tab.rawValue)
    }

    private func runButton(isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            RunSmartIconMark(size: 64, tint: isSelected ? .accentPrimary : .textSecondary, selected: isSelected)
                .shadow(color: Color.accentPrimary.opacity(isSelected ? 0.46 : 0.0), radius: isSelected ? 20 : 0)
                .scaleEffect(isSelected ? 1.04 : 1.0)
            Text("Run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentPrimary : Color.textSecondary)
        }
        .offset(y: -17)
        .accessibilityLabel(RunSmartTab.run.rawValue)
    }
}

struct SegmentedPillPicker<T: Hashable & CaseIterable & Identifiable>: View {
    var values: [T]
    @Binding var selection: T
    var label: (T) -> String

    init(values: [T], selection: Binding<T>, label: @escaping (T) -> String) {
        self.values = values
        self._selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values) { value in
                Button { selection = value } label: {
                    Text(label(value))
                        .font(.labelSM)
                        .tracking(0.6)
                        .foregroundStyle(selection == value ? Color.black : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selection == value ? Color.accentPrimary : Color.surfaceElevated,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: RunSmartRadius.pill, style: .continuous))
    }
}

struct StatusChip: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = .accentPrimary

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

struct ParityMetricCard: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color
    var values: [Double]

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Text(title.uppercased())
                        .font(.labelSM)
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)
                }
                Text(value)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                MiniSparkline(values: values, tint: tint)
                    .frame(height: 20)
            }
        }
    }
}

private struct MiniSparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let maxVal = values.max() ?? 1
            let minVal = values.min() ?? 0
            let range = maxVal - minVal == 0 ? 1 : maxVal - minVal
            let step = geo.size.width / CGFloat(Swift.max(values.count - 1, 1))
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height * (1 - CGFloat((v - minVal) / range))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct OrganicProgressRing: View {
    var value: Double
    var title: String
    var subtitle: String
    var tint: Color = .accentPrimary

    var body: some View {
        ZStack {
            ProgressRing(value: value, lineWidth: 8, tint: tint)
            VStack(spacing: 1) {
                Text(title)
                    .font(.labelLG)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
