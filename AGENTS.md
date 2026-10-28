# AGENTS.md - RunSmart iOS (native SwiftUI)

> Read tasks/progress.md, tasks/todo.md, and tasks/session-log.md at session start.
> Update tasks/progress.md before ending any session that changes project state.

## Next App Store Connect Submission: Benchmark Fix Required

Owner instruction, 2026-10-27: include the saved-report / save-once route benchmark fix in the next ASC submission.

- Required implementation: PR #166, commit `5c96738` (`fix: restore saved-run route benchmarks and save-once comparisons`). Do not archive or select another release candidate until that implementation is merged into the source being archived.
- Verify inclusion with `git merge-base --is-ancestor 5c96738 <archive-source-commit>` and record the actual source commit in the release evidence. Checking the current working branch alone does not establish which source an older archive contains.
- Build 37 was archived before this fix and does not satisfy the requirement. Use a new unused build number greater than 37; determine the marketing version from live ASC state at release preparation time. Do not withdraw or change the existing submission as part of this inclusion instruction alone.
- Follow `docs/qa/releases/next-submission/README.md`: validate the archived candidate's saved-report map, Save Route with benchmark on by default, three-run previous/PB/average comparison, and persistence after relaunch. Keep the live packaged-backend gate below.
- Close this requirement only after recording the exact processed build selected for the next ASC submission and its source-inclusion evidence. Do not mark it satisfied by a PR, merge, simulator build, or older uploaded binary alone.

## Release Backend Gate

Before uploading a release or TestFlight build, run `python3 scripts/verify-release-backend.py <built-app-path>` against the actual archived/exported app. A nonempty key is insufficient: require the live check to pass. Check ignored xcconfig overrides when the packaged key differs from committed defaults.

## Session End Rule: Nothing Stays Local

Every session that produces committed code ends with a push and an open PR (or an explicit handoff) before declaring done. No exceptions. This applies to Claude Code, Codex, and Cursor alike.

1. Before declaring done, run `git status --short --branch` and `git log --oneline @{u}..` and report the output in the final message.
2. If you cannot push or open a PR, end with exactly: "N commits are local-only on branch X - you need to push and open a PR."
3. Never leave work in a worktree without reporting the worktree path and branch in the final message.
4. Safety net: the Agentic OS Stranded Work board (`./agentic-os refresh`, then PROJECT-STATUS.md) lists every unpushed branch, local-only commit, and leftover worktree across all projects. It runs as part of the morning brief.
