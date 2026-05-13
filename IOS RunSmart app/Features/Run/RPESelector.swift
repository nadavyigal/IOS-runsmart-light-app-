import SwiftUI

struct RPESelector: View {
    @Binding var value: Int

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "How did that feel?", trailing: "\(value)/10")
                HStack(spacing: 6) {
                    ForEach(1...10, id: \.self) { number in
                        Button { value = number } label: {
                            Text("\(number)")
                                .font(.caption.bold())
                                .foregroundStyle(value == number ? Color.black : Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(value == number ? tint(for: number) : Color.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tint(for number: Int) -> Color {
        switch number {
        case 1...3: return .accentRecovery
        case 4...7: return .accentPrimary
        default: return .accentEnergy
        }
    }
}
