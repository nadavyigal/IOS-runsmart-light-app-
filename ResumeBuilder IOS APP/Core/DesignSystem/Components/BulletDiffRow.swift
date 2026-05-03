import SwiftUI

struct BulletDiffRow: View {
    let original: String
    let optimized: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Original")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(original)

            Text("Suggested")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(optimized)

            HStack {
                Button("Reject", role: .destructive, action: onReject)
                Spacer()
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
