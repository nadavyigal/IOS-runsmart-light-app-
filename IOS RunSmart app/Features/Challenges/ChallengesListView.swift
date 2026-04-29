import SwiftUI

struct ChallengesListView: View {
    @EnvironmentObject private var session: SupabaseSession
    @State private var challenges: [ChallengeItem] = []
    @State private var isLoading = true
    @State private var selectedChallenge: ChallengeItem?
    private let repo = ChallengeRepository()

    var body: some View {
        ZStack {
            RunSmartBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    RunSmartHeader(title: "Challenges")

                    Text("Complete a challenge to level up your running.")
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedText)

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 110)
                        }
                    } else if challenges.isEmpty {
                        Text("No challenges available right now.")
                            .foregroundStyle(Color.mutedText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(challenges) { challenge in
                            ChallengeCard(challenge: challenge) {
                                selectedChallenge = challenge
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .foregroundStyle(.white)
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedChallenge) { challenge in
            ChallengeDetailView(challenge: challenge) {
                Task { await loadChallenges() }
            }
        }
        .task { await loadChallenges() }
    }

    private func loadChallenges() async {
        guard let userID = session.currentUserID else {
            isLoading = false
            return
        }
        challenges = await repo.availableChallenges(authUserID: userID)
        isLoading = false
    }
}

private struct ChallengeCard: View {
    var challenge: ChallengeItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCard(cornerRadius: 18, padding: 16, glow: challenge.isEnrolled ? Color.lime : nil) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(challenge.isEnrolled ? Color.lime.opacity(0.2) : Color.white.opacity(0.08))
                            .frame(width: 52, height: 52)
                        Image(systemName: challenge.isEnrolled ? "checkmark.seal.fill" : "trophy.fill")
                            .font(.title2.bold())
                            .foregroundStyle(challenge.isEnrolled ? Color.lime : .white)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(challenge.title)
                            .font(.headline)
                        Text(challenge.description)
                            .font(.caption)
                            .foregroundStyle(Color.mutedText)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Label("\(challenge.durationDays) days", systemImage: "calendar")
                                .font(.caption2.bold())
                                .foregroundStyle(challenge.isEnrolled ? Color.lime : Color.mutedText)
                            if challenge.isEnrolled {
                                Text("Active")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.lime)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
