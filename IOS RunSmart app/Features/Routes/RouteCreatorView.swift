import SwiftUI

struct RouteCreatorView: View {
    @State private var distance = 8.0
    @State private var elevation = "Rolling"
    @State private var surface = "Road"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentRecovery) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Route creator")
                    Text("Build a route for the workout")
                        .font(.headingLG)
                    RouteMapView(points: [], title: "Preview route")
                        .frame(height: 150)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Route shape")
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(String(format: "%.1f km", distance))
                            .font(.metricSM)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    Slider(value: $distance, in: 3...24, step: 0.5)
                        .tint(Color.accentPrimary)
                    RouteSegmentedControl(title: "Elevation", options: ["Flat", "Rolling", "Hilly"], selection: $elevation)
                    RouteSegmentedControl(title: "Surface", options: ["Road", "Trail", "Mixed"], selection: $surface)
                }
            }

            Button { RunSmartHaptics.medium() } label: {
                Label("Generate Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .buttonStyle(NeonButtonStyle())
        }
    }
}

private struct RouteSegmentedControl: View {
    var title: String
    var options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.1)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        Text(option)
                            .font(.labelSM)
                            .foregroundStyle(selection == option ? Color.black : Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selection == option ? Color.accentPrimary : Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
