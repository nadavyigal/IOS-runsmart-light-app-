# Bug Fix Workflow

## Read
- `AGENTS.md`
- Agent router: `CLAUDE.md` or `CODEX.md`
- `tasks/lessons.md`
- Relevant logs, errors, files, and tests

## Steps
1. Reproduce or explain why reproduction is unavailable.
2. Identify the narrow failing behavior.
3. Add or define a regression test when practical.
4. Fix the smallest root cause.
5. Run the regression check and nearby smoke test.
6. Update `tasks/todo.md`.
7. Add a lesson if the bug came from a bad assumption, repeated mistake, or missed QA path.

## Done
- Root cause is explained.
- Fix is scoped.
- Regression risk is covered by test or manual verification.

