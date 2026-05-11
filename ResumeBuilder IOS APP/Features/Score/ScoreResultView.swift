import SwiftUI

struct ScoreResultView: View {
    let result: ATSScoreResult
    let isAuthenticated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Score header ──────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ATS Score")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(result.score?.overall ?? 0)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                ATSDial(score: result.score?.overall ?? 0)
                    .frame(width: 90, height: 90)
            }

            // ── Quick wins ────────────────────────────────────────────────────
            if let quickWins = result.quickWins, !quickWins.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Quick Wins", systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentCyan)

                    ForEach(quickWins.prefix(3)) { win in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Theme.accentCyan)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(win.title ?? win.action ?? win.keyword ?? "Improve keyword alignment")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(14)
                .background(Theme.accentCyan.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
            }

            // ── Top issues ────────────────────────────────────────────────────
            if let preview = result.preview {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Top Issues", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)

                    ForEach(preview.topIssues.prefix(3)) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(issue.message ?? issue.text ?? issue.suggestion ?? "ATS issue found")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if let locked = preview.lockedCount, locked > 0 {
                        Text("\(locked) more recommendations unlock with full optimization.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(14)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
            }

            // ── Footer ────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                if let remaining = result.checksRemaining {
                    Text("\(remaining) free checks remaining this week.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                Text(isAuthenticated
                     ? "Use Tailor to generate the full optimized resume."
                     : "Sign in to unlock full resume optimization.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(18)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
        )
    }
}
