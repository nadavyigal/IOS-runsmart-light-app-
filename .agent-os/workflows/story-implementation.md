# Story Implementation Workflow

Use only after a story or spec is approved.

## Read
- `AGENTS.md`
- Agent router: `CLAUDE.md` or `CODEX.md`
- `tasks/lessons.md`
- `tasks/todo.md`
- Approved feature spec/story
- Relevant source files only

## Steps
1. Confirm current story, acceptance criteria, and out of scope.
2. Check git status.
3. Define verification before editing.
4. Make the smallest useful code change.
5. Run focused build/test/simulator checks.
6. Update `tasks/todo.md` with progress and validation.
7. Update `tasks/session-log.md` for meaningful work.
8. If something failed or the user corrected direction, update `tasks/lessons.md`.

## Done
- Acceptance criteria met.
- Verification run or explicitly blocked.
- No unrelated app code changed.
- Next story is clear.

