import SwiftUI

struct AnimatedCounterText: View {
    var from: Double
    var to: Double
    var suffix: String
    var duration: TimeInterval = 1.2

    @State private var progress: Double = 0

    var body: some View {
        let value = from + (to - from) * progress
        Text(String(format: "%.1f%@", value, suffix))
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.textPrimary)
            .onAppear {
                progress = 0
                withAnimation(.easeOut(duration: duration)) {
                    progress = 1
                }
            }
    }
}
