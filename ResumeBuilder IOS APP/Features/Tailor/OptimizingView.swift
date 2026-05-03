import SwiftUI

struct OptimizingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Optimizing your resume...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
