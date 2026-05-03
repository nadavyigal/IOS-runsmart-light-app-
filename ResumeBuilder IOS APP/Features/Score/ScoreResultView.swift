import SwiftUI

struct ScoreResultView: View {
    let result: ATSScoreResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ATS Score")
                    .font(.headline)
                Spacer()
                Text("\(result.score?.overall ?? 0)")
                    .font(.title.bold())
            }

            ATSDial(score: result.score?.overall ?? 0)
                .frame(height: 140)

            Text("Use Tailor to improve weak bullets and keyword alignment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
