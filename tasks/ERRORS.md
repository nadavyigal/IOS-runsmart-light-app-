# RunSmart iOS — Error & Incident Log

Record failed approaches, lost work, and incidents so future sessions do not repeat them.

---

## 2026-07-05 — WP-34: Garmin credential-guard branch unrecoverable

**What was lost:** Branch `codex/wp24-garmin-credential-guard`, commit `baa19aa` — a finished fix gating new Garmin connections behind a credential guard (maintenance-mode scope; not a Garmin relaunch wedge).

**Last confirmed present:** 2026-07-02 (per Agentic OS WP-34 handoff; not present in this repo's git history at that time).

**Recovery attempts (2026-07-05):** `git cat-file -t baa19aa` (invalid object); `git branch -a` / `git log --all` / `git reflog` (no branch or commit); `git fsck --unreachable` (no matching commit message); `git stash list` (no match); `git fetch origin` + `git ls-remote` (no remote branch); local bundle `runsmart-local-branches-backup-20260520-144014.bundle` (18 heads, none credential/wp24); other machine clones under `~/projects/runsmart`, `~/nadav-workspace/projects/runsmart`, `~/.gstack/projects/nadavyigal-IOS-runsmart-light-app-` (no match).

**Action taken:** No re-implementation (would be new scope, not a merge). Flagged in `tasks/progress.md` for founder decision.

**Founder decision needed:** Re-implement the Garmin credential guard as new scoped work (WP-34), or explicitly park it under EXD-015 maintenance mode.
