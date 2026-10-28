import SwiftUI

/// Entry points share the selected saved run, not formatted report strings or a prototype track.
struct RunMediaShareEntry: View {
    let run: RecordedRun
    var insight: String = ""
    @State private var selection: RunShareAssetFormat?

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(title: "Share your run")
                        Text("Your miles. Your moment.")
                            .font(.headingMD)
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                    RunSmartLogoMark(size: 36, filled: true, glow: false)
                }
                Text("Create a photo or short route video. Your route map is included, without the first and last 200 m.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    ForEach(RunShareAssetFormat.allCases) { format in
                        Button { selection = format } label: {
                            VStack(spacing: 6) {
                                Image(systemName: format == .video ? "play.rectangle" : format == .feed ? "photo" : "rectangle.portrait")
                                    .font(.title3)
                                Text(format.rawValue).font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 64)
                            .foregroundStyle(Color.accentPrimary)
                            .background(Color.accentPrimary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel("Create \(format.rawValue.lowercased()) share")
                    }
                }
            }
        }
        .sheet(item: $selection) { format in
            NavigationStack {
                ShareRunView(run: run, insight: insight, initialFormat: format)
            }
        }
    }
}
