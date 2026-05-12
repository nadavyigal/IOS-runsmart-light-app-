# Lessons Memory

Review this file at the start of future tasks.

## Active Rules
- Keep `AGENTS.md`, `CLAUDE.md`, and `CODEX.md` as routers, not manuals.
- Load only the files needed for the current workflow.
- Do not assume the project is already a clean RunSmart app; verify whether files still use resume-builder names.
- Do not change app feature code when the task is to install or update the operating layer only.
- Before TestFlight claims, verify signing, bundle id, archive status, permissions, privacy strings, and smoke tests.
- When a workspace contains nested git repositories or nested Xcode projects, explicitly state which root is the GitHub repo and write committed docs relative to that root.

## Lesson Log

### 2026-05-12 - Thin OS Install
Trigger: User explicitly asked for a lightweight Agent OS, not a third-party framework or huge prompt file.

Lesson: Agent behavior changes best when workflow, memory, templates, and QA files exist in the repo, while router files stay short.

Future rule: Put detailed guidance under `.agent-os/`; keep root agent files token-efficient.

### 2026-05-12 - Nested Workspace Root
Trigger: Verification initially checked the nested iOS folder while the Agent OS was installed at the outer workspace root.

Lesson: This workspace has an outer folder and an inner GitHub-connected iOS repo, so path assumptions can be wrong.

Future rule: Before writing or verifying repo-level files, confirm whether paths are relative to the outer workspace or the GitHub repo root.
