# WP-27: Garmin Gate-4 Evidence Recapture

*Track:* Garmin Production Gate
*Status:* Founder-run required
*Target build:* `1.0.7 (20)`
*Started:* 2026-07-02

## Objective

Recapture and verify the Garmin Gate-4 evidence package from the corrected `1.0.7 (20)` app build, then prepare the reply package for Garmin tickets `213145` / `213165`.

This package is intentionally evidence-first. It does not change app code, version numbers, Garmin credentials, App Store Connect state, or ticket state.

## Source Requirements

Use the current Garmin public guidance before sending evidence:

- Garmin Connect Brand Guidelines: `https://developer.garmin.com/brand-guidelines/connect/`
- Garmin API Brand Guidelines PDF: `https://developer.garmin.com/downloads/brand/Garmin-Developer-API-Brand-Guidelines.pdf`

Relevant rules to verify:

- Garmin Connect tile imagery must not be altered.
- Garmin Connect app name must not be abbreviated, truncated, or stylized.
- Title-level or primary displays using Garmin device-sourced data need visible `Garmin [device model]` attribution, or `Garmin` when the device model is unknown.
- Attribution must be near the supported data, above the fold, and not hidden in a tooltip, footnote, or expandable container.

## Current Local Evidence

### Code State

- `main` includes PR #69: removed "Garmin Wellness" naming and stopped clipping the Garmin Connect tile.
- `main` includes PR #70: bumped version/build to `1.0.7 (20)`.
- WP-27 branch starts from the Garmin track cleanup and does not add app-code changes for evidence capture.

### Asset State

Current local Garmin Connect tile:

```text
Path: IOS RunSmart app/Assets.xcassets/GarminConnectTile.imageset/gc-app-tile_iOS.pdf
Type: PDF
Source: https://static.garmincdn.com/com.garmin.connect/content/images/developer/gc-app-tile/gc-app-tile_iOS.pdf
SHA-256: f5c298184be1139257a22814b04a01da6f020f3123e14eca8f47d30a8c2d9712
```

Tile provenance verified on 2026-07-02 by downloading the official iOS tile PDF from Garmin's public brand page and replacing the prior local 512x512 JPEG derivative. The prior local JPEG SHA-256 was `4df876736f980433a7f3e634a2209d383aa72c139851affa2f5013a38071d1f2`; it was not byte-identical to Garmin's official iOS PDF or highest-density PNG.

## Preconditions

Do not start capture until all are true:

- [ ] PR #69 and PR #70 are present in the build being captured.
- [ ] App Store Connect or TestFlight shows build `1.0.7 (20)`.
- [ ] The capture device has the exact build installed.
- [ ] The Garmin account is connected and has at least one synced activity with a known device model when available.
- [ ] The device is unlocked, charged, and set to the target appearance mode for the screenshot set.
- [x] The official Garmin Connect tile asset provenance has been checked.

## Required Screenshot Set

Capture the six Gate-4 screens Garmin has been reviewing. If the reviewer requested a broader set, capture the same six plus any added screens, but keep this base matrix intact.

| ID | Surface | Required Proof | Pass Criteria |
| --- | --- | --- | --- |
| 01 | Garmin Connect authentication / connection entry | Garmin Connect app tile and name | Tile is not clipped, masked, reshaped, recolored, stretched, or replaced by generic Garmin wordmark. Text says `Garmin Connect`. |
| 02 | Garmin Connect connection sheet/header | Garmin Connect app tile and name | Same tile rules as 01. No invented product names. |
| 03 | Profile connected service tile | Garmin Connect connection entry | Tile renders in native shape. Service detail is `Garmin Connect`; no `Garmin Wellness`. |
| 04 | Today / readiness or morning check-in Garmin data | Device-sourced data attribution | Visible `Garmin [device model]` near the data, or `Garmin` only if model is unavailable. |
| 05 | Activity / Report Garmin activity row | Device-sourced activity attribution | Row/report shows `Garmin [device model]` from row or connected-device fallback. No bare `Garmin` when model is known. |
| 06 | Recovery / Wellness Trends Garmin data | Device-sourced wellness attribution | Screen title is RunSmart-owned, such as `Wellness Trends`; Garmin attribution is inline near Garmin-backed data. No `Garmin Wellness`. |

## Capture Steps

1. Install or open build `1.0.7 (20)` on the physical device.
2. Confirm the app build in the installed binary or TestFlight details.
3. Sign in with Apple if needed.
4. Connect Garmin through the Garmin Connect flow.
5. Sync Garmin activity and wellness data.
6. Navigate to each required surface in the matrix.
7. Capture a screenshot for each surface.
8. Name files with stable IDs:

```text
01-garmin-connect-entry.png
02-garmin-connect-sheet.png
03-profile-garmin-connect-tile.png
04-today-garmin-attribution.png
05-activity-report-garmin-device.png
06-wellness-trends-garmin-attribution.png
```

9. Record build, device model, iOS version, app appearance mode, Garmin account connection state, and capture timestamp in the evidence manifest below.

## Evidence Manifest

Fill this before zipping or sending.

```text
App version/build:
Capture device:
iOS version:
Appearance mode:
Garmin account connected: yes/no
Garmin device model shown in app:
Screenshots captured at:
Official Garmin Connect tile provenance checked: yes/no
Reviewer tickets:
Evidence zip filename:
```

## Verification Checklist

### Brand Naming

- [ ] No screenshot contains `Garmin Wellness`.
- [ ] Garmin connection surfaces use `Garmin Connect`.
- [ ] RunSmart-owned data surfaces use RunSmart titles such as `Wellness Trends`, with Garmin attribution near Garmin-backed data.

### Tile Rendering

- [ ] Garmin Connect tile appears only on connection/authentication surfaces.
- [ ] Tile is not clipped, masked, rounded by app code, recolored, stretched, or compressed.
- [ ] Tile has enough visual size to be recognizable.

### Device Attribution

- [ ] Primary Garmin data surfaces show `Garmin [device model]` when the model is known.
- [ ] If model is unknown, `Garmin` appears as the fallback source label.
- [ ] Attribution is near the data it supports and above the fold.
- [ ] Attribution is not only in footnotes, tooltips, disclosure rows, or expandable containers.

### Package Readiness

- [ ] All six screenshots pass the matrix.
- [ ] Evidence manifest is complete.
- [ ] Zip contains only approved screenshots and manifest, no secrets or personal identifiers beyond approved demo account/device display names.
- [ ] Founder has decided whether to ask Marc to clarify "start all over" before sending the full package.

## Reply Draft

Use only after the evidence package passes. Adjust the wording to match Garmin's ticket thread.

```text
Hi Marc,

Thank you for the clarification. We rebuilt the evidence package from RunSmart iOS 1.0.7 (20), after removing the "Garmin Wellness" naming and correcting the Garmin Connect tile rendering so the tile is not altered by our UI.

Attached are fresh screenshots from the current build showing:
- Garmin Connect connection/authentication surfaces using the Garmin Connect tile and name.
- RunSmart-owned wellness and activity surfaces using inline Garmin device-sourced data attribution.
- Device attribution as "Garmin [device model]" where the device model is available.

Please let us know if "start all over" requires creating a new Garmin Developer Portal production app, or if this corrected evidence package is sufficient for the current review.

Best,
Nadav
```

## Stop Conditions

Stop and do not send the package if any of these occur:

- The installed build is not `1.0.7 (20)`.
- Any captured screen still says `Garmin Wellness`.
- The Garmin Connect tile is visibly altered or cannot be proven to come from Garmin's official asset source.
- Device model is known but not shown on Garmin device-sourced data surfaces.
- The reviewer clarifies that "start all over" means a new production app submission rather than evidence recapture.
