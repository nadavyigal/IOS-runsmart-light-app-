# RunSmart Agent OS Router

This repo uses a thin Agent OS. Do not load every file. Start with this router, the agent-specific router, `tasks/lessons.md`, and only the workflow files needed for the current task.

## Always Start
- Check `git status --short` and do not overwrite user changes.
- Read `tasks/lessons.md` before planning or editing.
- Update `tasks/todo.md` for non-trivial work.
- Work in small verified steps.
- Do not rewrite product logic or redesign screens unless the task asks for it.
- Keep RunSmart iOS native, premium, simple, fast, visual, and TestFlight-ready.

## Workflow Route
- Planning: read `.agent-os/workflows/feature-planning.md`, `docs/product/current-product-state.md`, `docs/architecture/current-ios-architecture.md`, and relevant templates.
- Implementation: read `.agent-os/workflows/story-implementation.md`, `tasks/todo.md`, `tasks/lessons.md`, and the approved spec/story.
- Bug fix: read `.agent-os/workflows/bug-fix.md`, relevant errors/logs/files, and `tasks/lessons.md`.
- iOS QA: read `.agent-os/workflows/ios-qa-review.md` and `docs/qa/ios-qa-checklist.md`.
- TestFlight: read `.agent-os/workflows/testflight-review.md` and `docs/qa/testflight-checklist.md`.
- PR summary: read `.agent-os/workflows/pr-review.md` and `.agent-os/templates/pr-summary-template.md`.
- Self-improvement: read `.agent-os/workflows/self-improvement.md` after mistakes, failed builds, bad assumptions, or user corrections.

## Required Flow
Idea -> Product Brief -> Feature Spec -> Development Stories -> Implementation Plan -> Build/Test/Simulator Validation -> iOS QA Report -> TestFlight Readiness Review -> PR Summary -> Lessons Update.

## Verification Before Done
Before marking work complete, run the smallest useful verification: Xcode build, tests, simulator smoke test, static inspection, or docs/file existence checks. Report what passed and what was not run.

## Self-Improvement Rule
After a user correction, failed implementation, broken build/test, bad SwiftUI pattern, repeated mistake, confusing output, overengineering, or missed requirement: add a short lesson to `tasks/lessons.md`, convert it into a future rule, and apply it next time.

## Example Prompts
- "Plan the Today screen refresh using the Agent OS."
- "Implement one SwiftUI story from `docs/specs/today-screen.md`."
- "Review the iOS UI for small iPhones and dark mode."
- "Fix this bug using the bug-fix workflow: [error/log]."
- "Create a TestFlight QA report for the current build."
- "Prepare a PR summary for the current branch."

