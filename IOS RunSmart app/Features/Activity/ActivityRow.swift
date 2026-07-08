import SwiftUI

struct ActivityRow: View {
    var run: RecordedRun
    var fallbackGarminDeviceName: String? = nil
    var onTap: () -> Void = {}
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                rowContent
            }
            .buttonStyle(.plain)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentHeart)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove run")
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.black)
                .frame(width: 40, height: 40)
                .background(Color.accentPrimary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Run")
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                // Garmin API Brand Guidelines: device-sourced data must carry a plain,
                // unstylized "Garmin [device model]" attribution adjacent to the title, above
                // the fold. No accent color / no letter-spacing.
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Text(String(format: "%.1f km", run.distanceMeters / 1_000))
                .font(.metricSM)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.vertical, 5)
    }

    /// Metadata line shown under the run title, e.g. "Jun 22, 2026 at 5:41 PM · Garmin Forerunner 265".
    /// For Garmin-sourced runs this doubles as the required "Garmin [device model]" attribution.
    private var metadataLine: String {
        let date = run.startedAt.formatted(date: .abbreviated, time: .shortened)
        let rpeText = run.rpe.map { "RPE \($0)/10" }
        return [date, RunSmartAttribution.sourceLabel(for: run, fallbackGarminDeviceName: fallbackGarminDeviceName), rpeText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
