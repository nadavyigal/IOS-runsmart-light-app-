# Garmin-deferred UI copy restore

Parked with Garmin (EXD-015 / WP-34). Restored strings below were removed in **WP-38 S11** so delete dialogs no longer mention Garmin on every run (including phone-recorded ones). When Garmin connect is un-parked, re-evaluate whether delete/remove dialogs should be **source-aware** again (neutral for RunSmart/manual; Garmin-specific for `.garmin` rows).

## Run delete / remove dialogs (WP-38 S11)

### `Features/Run/PostRunSummaryView.swift`

- **Title (unchanged at removal):** `Delete this activity?`
- **Message (removed):** `This removes the run from RunSmart. It will not delete anything from Garmin.`

### `Features/Activity/ActivityTabView.swift`

- **Title (unchanged at removal):** `Remove this run?`
- **Message (removed):** `RunSmart/manual runs are deleted from RunSmart. Garmin runs are hidden in RunSmart but stay in Garmin.`

### Neutral copy shipped in S11 (both surfaces)

- Prefer a single generic message such as: `This removes the run from your RunSmart history.`
- Titles may stay as-is or unify to `Delete this run?` — check the S11 diff.

## Related (not changed in S11; still Garmin-aware)

These still mention Garmin and were **out of S11 scope**. Revisit with the same restore pass if product wants full source-neutral language:

- `Features/Routes/SaveRouteSheet.swift` — saved-route privacy copy about Garmin activities not being deleted.
- `Features/Routes/RouteDetailView.swift` — delete-route confirmation that Garmin activity is not deleted.

## Behavior note (do not lose)

`removeRun` still **hides** Garmin-sourced rows in RunSmart and **deletes** RunSmart/manual rows. S11 was copy-only; restoring Garmin dialog text should not change that unless product explicitly re-scopes the hide/delete rules.
