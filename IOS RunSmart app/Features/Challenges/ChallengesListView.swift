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
                        ForEach(Self.fallbackChallenges) { challenge in
                            ChallengeCard(challenge: challenge) {
                                selectedChallenge = challenge
                            }
                        }
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

    private static let fallbackChallenges: [ChallengeItem] = [
        ChallengeItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            slug: "local-21-day-start-running",
            title: "21-Day Start Running",
            description: "From zero to running 30 minutes comfortably with guided habit-building workouts.",
            durationDays: 21,
            isEnrolled: false,
            startedAt: nil
        ),
        ChallengeItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            slug: "local-10k-breakthrough",
            title: "10K Breakthrough",
            description: "A focused block with tempo, long run, and recovery balance to unlock your next 10K step.",
            durationDays: 28,
            isEnrolled: false,
            startedAt: nil
        ),
        ChallengeItem(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            slug: "local-consistency-streak",
            title: "Consistency Streak",
            description: "Complete three runs a week and keep momentum visible in your profile snapshot.",
            durationDays: 14,
            isEnrolled: false,
            startedAt: nil
        )
    ]
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
