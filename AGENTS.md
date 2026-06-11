# AGENTS.md - RunSmart iOS (native SwiftUI)

> Read tasks/progress.md, tasks/todo.md, and tasks/session-log.md at session start.
> Update tasks/progress.md before ending any session that changes project state.

## Session End Rule: Nothing Stays Local

Every session that produces committed code ends with a push and an open PR (or an explicit handoff) before declaring done. No exceptions. This applies to Claude Code, Codex, and Cursor alike.

1. Before declaring done, run `git status --short --branch` and `git log --oneline @{u}..` and report the output in the final message.
2. If you cannot push or open a PR, end with exactly: "N commits are local-only on branch X - you need to push and open a PR."
3. Never leave work in a worktree without reporting the worktree path and branch in the final message.
4. Safety net: the Agentic OS Stranded Work board (`./agentic-os refresh`, then PROJECT-STATUS.md) lists every unpushed branch, local-only commit, and leftover worktree across all projects. It runs as part of the morning brief.
