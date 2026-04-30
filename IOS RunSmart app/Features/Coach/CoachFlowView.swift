import SwiftUI

struct CoachFlowView: View {
    var context: String
    @Environment(\.runSmartServices) private var services
    @State private var draft = ""
    @State private var isTyping = false
    @State private var messages = [
        CoachMessage(text: "I have your readiness, recent runs, and current plan context. What should we adjust?", time: "Now", isUser: false),
        CoachMessage(text: "Should I run today?", time: "Just now", isUser: true),
        CoachMessage(text: "Yes, but treat the first 10 minutes as a readiness check. If breathing feels strained, convert the tempo into steady aerobic work.", time: "Just now", isUser: false)
    ]

    private let prompts = ["Explain today’s workout", "Should I run today?", "Adjust my plan", "Recovery advice"]

    var body: some View {
        ZStack {
            RunSmartBackground(context: .today(readiness: nil))
            VStack(spacing: 0) {
                header
                contextPanel
                promptRow
                chatArea
                inputBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            CoachAvatar(size: 54, showBolt: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("RunSmart Coach")
                    .font(.headingMD)
                Text("\(context) context")
                    .font(.labelSM)
                    .tracking(1.1)
                    .foregroundStyle(Color.accentPrimary)
            }
            Spacer()
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var contextPanel: some View {
        ContentCard {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentPrimary)
                Text("Coach can use readiness, plan week, recent runs, routes, and wellness summaries.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    private var promptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button { send(prompt) } label: {
                        Text(prompt)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var chatArea: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(messages) { message in
                    CoachBubble(message: message)
                }
                if isTyping {
                    TypingIndicator()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Coach anything...", text: $draft)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.textPrimary)
                .padding(14)
                .background(Color.surfaceCard)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.border))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button { RunSmartHaptics.light() } label: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceCard, in: Circle())
            }
            .buttonStyle(.plain)
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Color.accentPrimary, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(CoachMessage(text: trimmed, time: "Now", isUser: true))
        draft = ""
        isTyping = true
        Task {
            let response = await services.send(message: trimmed)
            try? await Task.sleep(nanoseconds: 550_000_000)
            messages.append(CoachMessage(text: response.text.isEmpty ? "I’ll adjust that against your plan and recovery signals." : response.text, time: "Now", isUser: false))
            isTyping = false
        }
    }
}

private struct TypingIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack {
            CoachAvatar(size: 30)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accentPrimary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.2 : 0.82)
                        .animation(.easeInOut(duration: 0.55).repeatForever().delay(Double(index) * 0.12), value: pulse)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
        .onAppear { pulse = true }
    }
}
