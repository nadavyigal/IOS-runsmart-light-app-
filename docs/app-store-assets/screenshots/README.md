# App Store Screenshot Package

Prepared on 2026-05-10.

## Packaged Screenshots

The `iphone-6-9` folder contains cleanly named PNG files padded to `1290 x 2796`, an accepted portrait size for the current App Store Connect 6.9-inch iPhone screenshot slot:

- `01-today-generated-workout.png`
- `02-plan-monthly-weekly.png`
- `03-run-route.png`
- `04-profile-account.png`

Source images came from `design-assets/`.

## Still Needed

- Capture `05-no-plan-empty-state.png` from the real app after signing in with an account that has no active plan, showing "No plan yet", "Set Goal", and "Regenerate Plan".
- Prefer replacing these padded design-source images with real simulator/device captures at App Store Connect native dimensions before public release.

## Reference Sizes

Apple currently accepts one to ten screenshots per device display set in PNG, JPG, or JPEG. For iPhone 6.9-inch portrait, accepted sizes include:

- `1260 x 2736`
- `1290 x 2796`
- `1320 x 2868`

Reference: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
