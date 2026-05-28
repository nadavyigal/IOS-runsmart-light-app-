# RunSmart — Lifecycle Program

Email + in-app nudges. Use the workflow at `distribution-os/workflows/08-lifecycle-email.md`.

## Stages In Order

1. Welcome (account created)
2. Onboarding completed → first plan generated
3. First workout logged
4. 2-day no-show (planned run not logged)
5. Week-1 adherence digest
6. Inactive 14 days
7. Reactivation
8. Pre-paid offer (when monetization live)
9. Cancellation save

## Channels Per Stage

- Email: always
- In-app banner: stages 2, 4
- Push notification (optional): stage 4 only, founder-approved copy

## Status Per Stage

- Welcome: <draft | live | not started>
- (Fill in)

## Measurement

- Open rate, click rate, downstream action rate per stage
- Effect on `runsmart.activation.first_plan_generated`, `runsmart.activation.first_run_logged`, `runsmart.retention.week1_adherence`
