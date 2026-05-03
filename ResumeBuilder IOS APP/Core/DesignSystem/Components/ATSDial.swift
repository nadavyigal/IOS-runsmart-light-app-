import SwiftUI

struct ATSDial: View {
    let score: Int

    var body: some View {
        GeometryReader { geometry in
            let progress = max(0, min(1, Double(score) / 100.0))

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [.orange, .green],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)

                Text("\(score)")
                    .font(.title.bold())
            }
            .frame(width: min(geometry.size.width, geometry.size.height), height: min(geometry.size.width, geometry.size.height))
        }
    }
}
