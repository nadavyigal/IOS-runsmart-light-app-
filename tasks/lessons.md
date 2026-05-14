# Lessons Memory

Review this file at the start of future tasks.

## Active Rules
- Keep `AGENTS.md`, `CLAUDE.md`, and `CODEX.md` as routers, not manuals.
- Load only the files needed for the current workflow.
- Do not assume the project is already a clean RunSmart app; verify whether files still use resume-builder names.
- Do not change app feature code when the task is to install or update the operating layer only.
- Before TestFlight claims, verify signing, bundle id, archive status, permissions, privacy strings, and smoke tests.

## Lesson Log

### 2026-05-12 - Thin OS Install
Trigger: User explicitly asked for a lightweight Agent OS, not a third-party framework or huge prompt file.

Lesson: Agent behavior changes best when workflow, memory, templates, and QA files exist in the repo, while router files stay short.

Future rule: Put detailed guidance under `.agent-os/`; keep root agent files token-efficient.

