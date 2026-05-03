import SwiftUI

struct DiffReviewView: View {
    @State private var acceptedCount = 0
    @State private var rejectedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diff Review")
                .font(.title2.bold())

            BulletDiffRow(
                original: "Built internal dashboard for application status.",
                optimized: "Built ATS-friendly dashboard to track candidate pipeline and follow-ups.",
                onAccept: { acceptedCount += 1 },
                onReject: { rejectedCount += 1 }
            )

            ATSDial(score: min(100, 60 + (acceptedCount * 8) - (rejectedCount * 2)))
                .frame(height: 120)

            Text("Accepted: \(acceptedCount)  •  Rejected: \(rejectedCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
