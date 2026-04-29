import SwiftUI

struct CoachFlowView: View {
    var context: String
    @State private var draft = ""
    @State private var messages = [
        CoachMessage(text: "I'm here with your \(Date.now.formatted(date: .omitted, time: .shortened)) context. Ask about pacing, recovery, plan changes, or today's workout.", time: "Now", isUser: false),
        CoachMessage(text: "How should I handle the middle miles today?", time: "Just now", isUser: true),
        CoachMessage(text: "Hold back for the first two kilometers, settle into 5:10–5:15 pace, then only press if breathing still feels controlled.", time: "Just now", isUser: false)
    ]

    var body: some View {
        ZStack {
            RunSmartBackground()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CoachAvatar(size: 62, showBolt: true)
                        VStack(alignment: .leading) {
                            Text("RunSmart Coach")
                                .font(.title2.bold())
                            Text("\(context) context")
                                .font(.caption)
                                .foregroundStyle(Color.lime)
                        }
                        Spacer()
                    }
                    GlassCard(cornerRadius: 18, padding: 14, glow: Color.lime) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3.bold())
                                .foregroundStyle(Color.lime)
                                .frame(width: 42, height: 42)
                                .background(Color.lime.opacity(0.14))
                                .clipShape(Circle())
                            Text("Adaptive coaching for the next decision, tuned to your \(context.lowercased()) data.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(20)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            CoachBubble(message: message)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                HStack(spacing: 10) {
                    TextField("Ask Coach anything...", text: $draft)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button {
                        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        messages.append(CoachMessage(text: draft, time: "Now", isUser: true))
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.bold())
                            .foregroundStyle(.black)
                            .frame(width: 46, height: 46)
                            .background(Color.lime)
                            .clipShape(Circle())
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }
}
