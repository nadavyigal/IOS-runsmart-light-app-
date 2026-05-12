# iOS QA Review Workflow

## Read
- `AGENTS.md`
- Agent router: `CLAUDE.md` or `CODEX.md`
- `tasks/lessons.md`
- `docs/qa/ios-qa-checklist.md`
- `.agent-os/templates/ios-qa-report-template.md`

## Steps
1. Identify build/scheme/device assumptions.
2. Run build/tests when available.
3. Perform simulator smoke test for primary changed flows.
4. Check small iPhone layout and dark mode if relevant.
5. Check permissions and failure states touched by the change.
6. Produce QA report.
7. Update `tasks/session-log.md` and `tasks/lessons.md` if needed.

## Done
- QA report lists passed checks, failed checks, skipped checks, and release risk.

