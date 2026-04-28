# RunSmart Lite QA Checklist

## Primary Tabs

- Today shows coach greeting, readiness, workout recommendation, Start Workout, coach insight, conversation, and compact stats.
- Plan shows coach briefing, week strip, month overview, coach notes, and plan adjustment entry.
- Run shows live coach, metrics, route panel, coach cue, run controls, and post-run summary entry.
- Profile shows runner identity, stats, Coach Spark, settings, optimization cards, achievements, and connected services.

## Coach Flow

- Coach opens from Today, Plan, Run, and Profile.
- Sheet is readable at large detent.
- Sending an empty message does nothing.
- Sending a non-empty message appends it and clears the field.

## Secondary Flows

- Workout details, plan adjustment, post-run summary, audio/lap, reminders, preferences, and connected service entries open a scaffold.
- Each scaffold clearly states the next integration step.

## Visual And Accessibility

- Check iPhone small and Pro Max sizes.
- Check Dynamic Type through at least accessibility large.
- Check reduced motion once animations are added.
- Confirm sufficient contrast on neon text and small labels.
- Confirm tab targets and run controls remain one-handed friendly.

## Run-Specific Risks

- Interruption handling: call, lock screen, app background, low power mode.
- Location permission denial and degraded GPS.
- Pause/resume/finish state transitions.
- Save failure and retry behavior.

## Performance

- Primary tabs should render from mock data without visible jank.
- Live map and streaming coach responses require separate profiling once integrated.
