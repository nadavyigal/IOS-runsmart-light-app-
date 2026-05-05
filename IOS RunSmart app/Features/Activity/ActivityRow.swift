import SwiftUI

struct ActivityRow: View {
    var run: RecordedRun
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
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f km", run.distanceMeters / 1_000))
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(run.source.rawValue)
                    .font(.labelSM)
                    .tracking(1.0)
                    .foregroundStyle(Color.accentRecovery)
            }
        }
        .padding(.vertical, 5)
    }
}
