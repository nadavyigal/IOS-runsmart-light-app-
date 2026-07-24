import SwiftUI

// Full-bleed route card: RouteMapView fills the entire card height,
// all metadata overlaid via a bottom gradient scrim.
struct FullBleedRouteCard: View {
    var suggestion: RouteSuggestion
    var isSelected: Bool
    var onTap: () -> Void
    var onDetail: (() -> Void)? = nil

    private var isBenchmark: Bool { suggestion.kind == .benchmark }

    var body: some View {
        ZStack {
            Button(action: onTap) {
                cardContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // Sibling of the selection button, never nested inside it: a Button
            // within a Button does not reliably receive its own taps, and the
            // selection button's `children: .combine` would hide this action
            // from VoiceOver entirely.
            if let onDetail {
                Button(action: onDetail) {
                    detailChip
                }
                .buttonStyle(.plain)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityLabel("Route details for \(suggestion.name)")
            }
        }
        .frame(height: isBenchmark ? 180 : 155)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected ? Color.lime.opacity(0.55)
                        : isBenchmark ? Color.lime.opacity(0.22)
                        : Color.white.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .shadow(color: isSelected ? Color.lime.opacity(0.12) : .clear, radius: 10)
    }

    private var detailChip: some View {
        HStack(spacing: 4) {
            Text("Details")
                .font(.system(size: 11, weight: .bold))
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }

    private var cardContent: some View {
        ZStack(alignment: .bottomLeading) {

            // Map fills the entire card
            RouteMapView(points: suggestion.points, title: nil)
                .allowsHitTesting(false)

            // Bottom gradient scrim
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.50), location: 0.30),
                    .init(color: Color.black.opacity(0.88), location: 0.65),
                    .init(color: Color.black.opacity(0.97), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Overlaid data content
            VStack(alignment: .leading, spacing: 5) {
                Spacer()
                Text(suggestion.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    statItem(icon: "point.topleft.down.curvedto.point.bottomright.up",
                             value: String(format: "%.1f km", suggestion.distanceKm))
                    statItem(icon: "arrow.up.right",
                             value: "\(suggestion.elevationGainMeters) m")
                    statItem(icon: "clock",
                             value: "\(suggestion.estimatedDurationMinutes) min")
                }

                if let reason = suggestion.recommendationReason {
                    reasonChip(reason, kind: suggestion.kind)
                }
            }
            .padding(12)

            // Select circle — top-left
            selectCircle
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Kind badges — top-right
            HStack(spacing: 5) {
                if isBenchmark {
                    kindBadge(label: "Benchmark", icon: "chart.line.uptrend.xyaxis", color: Color.lime)
                }
                if suggestion.isFavorite {
                    kindBadge(label: "", icon: "heart.fill", color: Color.accentHeart)
                }
                if suggestion.kind == .generated {
                    kindBadge(label: "Generated", icon: "sparkles", color: Color.accentRecovery)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Sub-views

    private var selectCircle: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.lime : Color.black.opacity(0.35))
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .overlay(Circle().stroke(isSelected ? Color.lime : Color.white.opacity(0.3), lineWidth: 1.5))
    }

    private func statItem(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(value)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }

    private func reasonChip(_ text: String, kind: RouteKind) -> some View {
        let (bg, fg): (Color, Color) = switch kind {
        case .benchmark: (Color.lime.opacity(0.16), Color.lime)
        case .saved:     (Color.white.opacity(0.10), Color.white.opacity(0.65))
        case .generated: (Color.accentRecovery.opacity(0.15), Color.accentRecovery)
        case .past:      (Color.white.opacity(0.08), Color.white.opacity(0.5))
        }
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(fg.opacity(0.25), lineWidth: 1)
            )
    }

    private func kindBadge(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, label.isEmpty ? 5 : 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(color.opacity(0.3), lineWidth: 1))
    }

    private var accessibilityLabel: String {
        var parts = [suggestion.name,
                     String(format: "%.1f kilometers", suggestion.distanceKm),
                     "\(suggestion.elevationGainMeters) meters elevation"]
        if isBenchmark { parts.append("Benchmark route") }
        if suggestion.isFavorite { parts.append("Favorite") }
        if let r = suggestion.recommendationReason { parts.append(r) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shared section header

struct RouteDiscoverySectionHeader: View {
    var title: String
    var count: Int?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.textTertiary)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}

// MARK: - Distance filter bar

struct RouteDistanceFilterBar: View {
    let options: [Double?]
    @Binding var selected: Double?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(options.indices, id: \.self) { i in
                    let opt = options[i]
                    let label = opt.map { "\(Int($0)) km" } ?? "Any"
                    let active = selected == opt
                    Button { selected = opt } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? Color.black : Color.textSecondary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(active ? Color.lime : Color.white.opacity(0.07))
                            .clipShape(Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).stroke(
                                active ? Color.lime : Color.white.opacity(0.1), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Empty state card

struct RouteDiscoveryEmptyCard: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Color.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

#if DEBUG
#Preview("Full Bleed Cards") {
    ZStack {
        RunSmartBackground()
        ScrollView {
            VStack(spacing: 10) {
                FullBleedRouteCard(
                    suggestion: RouteSuggestion(
                        id: "1", name: "Riverside Loop",
                        distanceKm: 8.2, elevationGainMeters: 48, estimatedDurationMinutes: 44,
                        points: [], kind: .benchmark,
                        recommendationReason: "Matches today's 8 km tempo",
                        savedRouteID: UUID(), isFavorite: true),
                    isSelected: true, onTap: {}
                )
                FullBleedRouteCard(
                    suggestion: RouteSuggestion(
                        id: "2", name: "Park Circuit",
                        distanceKm: 7.8, elevationGainMeters: 22, estimatedDurationMinutes: 41,
                        points: [], kind: .saved,
                        recommendationReason: "Saved · Favorite",
                        savedRouteID: UUID(), isFavorite: false),
                    isSelected: false, onTap: {}
                )
                FullBleedRouteCard(
                    suggestion: RouteSuggestion(
                        id: "3", name: "8K Loop · nearby",
                        distanceKm: 8.0, elevationGainMeters: 31, estimatedDurationMinutes: 43,
                        points: [], kind: .generated,
                        recommendationReason: "Low elevation · good for pace",
                        savedRouteID: nil, isFavorite: false),
                    isSelected: false, onTap: {}
                )
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
