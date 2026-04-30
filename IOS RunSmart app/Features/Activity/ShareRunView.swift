import SwiftUI

struct ShareRunView: View {
    var run: RecordedRun?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "Share run")
                    Text(distanceLabel)
                        .font(.displayLG)
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                    Text("Night Stadium share card")
                        .font(.headingMD)
                    RouteMapView(points: run?.routePoints ?? [], title: "Completed route")
                        .frame(height: 160)
                }
            }
            Button { RunSmartHaptics.light() } label: {
                Label("Open Share Sheet", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NeonButtonStyle())
        }
    }

    private var distanceLabel: String {
        guard let run else { return "5.2 km" }
        return String(format: "%.1f km", run.distanceMeters / 1_000)
    }
}
