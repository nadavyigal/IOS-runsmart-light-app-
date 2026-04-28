import SwiftUI

extension Color {
    static let ink = Color(red: 0.011, green: 0.017, blue: 0.024)
    static let inkElevated = Color(red: 0.045, green: 0.060, blue: 0.078)
    static let inkCard = Color(red: 0.065, green: 0.080, blue: 0.100)
    static let lime = Color(red: 0.74, green: 1.0, blue: 0.12)
    static let electricGreen = Color(red: 0.32, green: 1.0, blue: 0.34)
    static let mutedText = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.13)
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
    static let lg: CGFloat = 20
    static let pill: CGFloat = 999
}

struct RunSmartBackground: View {
    var body: some View {
        ZStack {
            Color.ink
            RadialGradient(
                colors: [Color.lime.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 360
            )
            RadialGradient(
                colors: [Color.electricGreen.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = RunSmartRadius.lg
    var padding: CGFloat = RunSmartSpacing.md
    var glow: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.075), .white.opacity(0.028)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .shadow(color: glow?.opacity(0.18) ?? .clear, radius: 22, x: 0, y: 0)
            .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 12)
    }
}

struct NeonButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(isDestructive ? Color.white : Color.black)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: isDestructive ? [Color.red.opacity(0.88), Color.red.opacity(0.68)] : [Color.lime, Color.electricGreen.opacity(0.92)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
            .shadow(color: (isDestructive ? Color.red : Color.lime).opacity(configuration.isPressed ? 0.18 : 0.48), radius: configuration.isPressed ? 8 : 18)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionLabel: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.lime)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lime)
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
                    LinearGradient(colors: [Color.white.opacity(0.34), Color.inkElevated, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: size * 0.66))
                        .foregroundStyle(.white.opacity(0.78), Color.lime.opacity(0.22))
                )
                .overlay(
                    Circle()
                        .trim(from: 0.08, to: 0.9)
                        .stroke(
                            AngularGradient(colors: [Color.lime, Color.electricGreen, Color.lime.opacity(0.35)], center: .center),
                            style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-72))
                )
                .shadow(color: Color.lime.opacity(0.56), radius: size * 0.16)
                .frame(width: size, height: size)

            if showBolt {
                Image(systemName: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(7)
                    .background(Color.lime)
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(
                    AngularGradient(colors: [Color.electricGreen, Color.lime, Color.electricGreen], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color.lime)
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
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.mutedText)
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
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color.mutedText)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Text(metric.unit)
                    .font(.caption.bold())
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

    var body: some View {
        HStack {
            if showLogo {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Color.lime)
                    Text("RunSmart")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            if let title {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: showSettings ? "gearshape" : "bell")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.78))
                .overlay(alignment: .topTrailing) {
                    if !showSettings {
                        Circle()
                            .fill(Color.lime)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
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

    var body: some View {
        HStack(alignment: .bottom) {
            ForEach(RunSmartTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: tab == .run ? 30 : 21, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.lime : Color.white.opacity(0.52))
                    .frame(maxWidth: .infinity)
                    .frame(height: tab == .run ? 76 : 56)
                    .background {
                        if tab == .run {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.045)], startPoint: .top, endPoint: .bottom)
                                )
                                .overlay(Circle().stroke(Color.hairline))
                                .shadow(color: Color.lime.opacity(selectedTab == .run ? 0.42 : 0.12), radius: 16)
                                .frame(width: 76, height: 76)
                                .offset(y: -10)
                        }
                    }
                    .offset(y: tab == .run ? -10 : 0)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.inkElevated.opacity(0.62))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Color.hairline))
        .shadow(color: .black.opacity(0.42), radius: 22, y: 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
