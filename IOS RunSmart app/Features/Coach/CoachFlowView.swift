import SwiftUI

struct CoachFlowView: View {
    var entryPoint: CoachEntryPoint
    @Environment(\.runSmartServices) private var services
    @State private var draft = ""
    @State private var isTyping = false
    @State private var messages: [CoachMessage] = []
    @State private var trainingContext: TrainingContextSnapshot?

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
        .task(id: entryPoint) {
            async let messagesTask = services.recentMessages()
            async let contextTask = services.trainingContext(for: entryPoint)
            let (loadedMessages, loadedContext) = await (messagesTask, contextTask)
            messages = loadedMessages
            trainingContext = loadedContext
        }
        .onAppear {
            Analytics.trackCoachThreadOpened(entryPoint: entryPoint.rawValue)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RunSmartAppBadge(mode: .iconOnly, size: 54, glow: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("RunSmart Coach")
                    .font(.headingMD)
                Text(entryPoint.contextLabel)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentPrimary)
                    Text(contextPanelTitle)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }

                if let trainingContext {
                    FlowLayout(spacing: 7) {
                        ForEach(trainingContext.contextChips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                        }
                    }

                    if let limitation = trainingContext.limitations.first {
                        Text(limitation)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Loading training context...")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var contextPanelTitle: String {
        guard let trainingContext else {
            return "Preparing Coach context"
        }
        if trainingContext.limitations.isEmpty {
            return "Using your current training context"
        }
        return "Using limited training context"
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
                    .disabled(isTyping)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var chatArea: some View {
        ScrollView {
            VStack(spacing: 12) {
                if messages.isEmpty {
                    ContentCard {
                        Text("No verified coach conversation yet. Ask a question to start a new thread with your current RunSmart context.")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(messages) { message in
                        CoachBubble(message: message)
                    }
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
                .disabled(isTyping)
            Button { RunSmartHaptics.light() } label: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceCard, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isTyping)
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Color.accentPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isTyping || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isTyping else { return }
        Analytics.trackCoachMessageSent(
            entryPoint: entryPoint.rawValue,
            messageLength: trimmed.count
        )
        messages.append(CoachMessage(text: trimmed, time: "Now", isUser: true))
        draft = ""
        isTyping = true
        Task {
            let currentContext: TrainingContextSnapshot
            if let trainingContext {
                currentContext = trainingContext
            } else {
                currentContext = await services.trainingContext(for: entryPoint)
            }
            let response = await services.send(message: trimmed, context: currentContext)
            try? await Task.sleep(nanoseconds: 550_000_000)
            await MainActor.run {
                trainingContext = currentContext
                messages.append(CoachMessage(text: response.text.isEmpty ? "I’ll adjust that against your plan and recovery signals." : response.text, time: "Now", isUser: false))
                isTyping = false
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
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
