import SwiftUI

struct ChallengeDetailView: View {
    var challenge: ChallengeItem
    var onEnrolled: () -> Void

    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss
    @State private var isEnrolling = false
    @State private var isEnrolled: Bool
    @State private var errorMessage: String?
    private let repo = ChallengeRepository()

    init(challenge: ChallengeItem, onEnrolled: @escaping () -> Void) {
        self.challenge = challenge
        self.onEnrolled = onEnrolled
        _isEnrolled = State(initialValue: challenge.isEnrolled)
    }

    var body: some View {
        ZStack {
            RunSmartBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(Color.mutedText)
                                .padding(10)
                                .background(.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        Spacer()
                        if isEnrolled {
                            Label("Active", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.lime)
                                .clipShape(Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.lime.opacity(0.18))
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.lime.opacity(0.4), radius: 20)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Color.lime)
                        }

                        Text(challenge.title)
                            .font(.title2.bold())

                        HStack(spacing: 12) {
                            MetricPill(symbol: "calendar", text: "\(challenge.durationDays) days")
                            if let started = challenge.startedAt {
                                MetricPill(symbol: "play.fill", text: "Started \(started.formatted(.relative(presentation: .named)))")
                            }
                        }
                    }

                    GlassCard(cornerRadius: 18, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(title: "About this challenge")
                            Text(challenge.description)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !isEnrolled {
                        Button(action: { Task { await enroll() } }) {
                            HStack {
                                if isEnrolling {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("Adopt Challenge")
                                        .font(.headline)
                                }
                            }
                        }
                        .buttonStyle(NeonButtonStyle())
                        .disabled(isEnrolling)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func enroll() async {
        if challenge.slug.hasPrefix("local-") {
            isEnrolled = true
            onEnrolled()
            return
        }
        guard let userID = session.currentUserID else { return }
        isEnrolling = true
        errorMessage = nil
        do {
            try await repo.enroll(challengeID: challenge.id, authUserID: userID)
            isEnrolled = true
            onEnrolled()
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnrolling = false
    }
}
