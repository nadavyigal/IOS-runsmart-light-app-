# RunSmart iOS — Design Tokens (current system)

Extracted from `IOS RunSmart app/DesignSystem/RunSmartDesignSystem.swift`.
Designs should reuse these so returned work translates straight into SwiftUI. If you evolve a token, say so explicitly. The **electric-lime action color is core brand identity** — don't replace it casually.

## Color — surfaces (near-black, premium athletic dark)

| Role | Token | Value |
|---|---|---|
| Base background | `surfaceBase` / `ink` | `#06060A` |
| Elevated surface | `surfaceElevated` | `#0C0C14` |
| Card | `surfaceCard` | `#11111C` |
| Deep card | `surfaceDeepCard` | `#030504` |
| Green-black (run/active accents) | `surfaceGreenBlack` | `#040E09` |
| Border | `border` / `hairline` | white @ 7% |
| Border subtle | `borderSubtle` | white @ 5% |
| Shimmer | `shimmer` | white @ 8% |

## Color — accents

| Role | Token | Value |
|---|---|---|
| **Primary action (signature)** | `accentPrimary` / `lime` | **`#CCFF00` electric lime** |
| Lime alt | `accentLime` | `#BFFF00` |
| Energy / amber | `accentEnergy` / `accentAmber` | `#FB923C` |
| Recovery / blue | `accentRecovery` | `#60A5FA` |
| Heart / pink | `accentHeart` | `#FB7185` |
| Success / electric green | `accentSuccess` / `electricGreen` | `#2DDC82` |
| Magenta | `accentMagenta` | `#A78BFA` |

> The accent set is a **metric language**: lime = action/go, amber = energy/effort, blue = recovery, pink = heart/HR, green = success. Keep these meanings consistent; don't rely on color alone (pair with text/labels per the audit).

## Color — text

| Role | Token | Value |
|---|---|---|
| Primary | `textPrimary` | `#F2F2FF` (near-white) |
| Secondary | `textSecondary` / `mutedText` | `#85859E` (≈ white 52%) |
| Tertiary | `textTertiary` | `#505066` (≈ white 31%) |

> Audit flag: `textSecondary`/`textTertiary` on the dark cards may be **marginal contrast** — verify WCAG AA for body/metadata text, especially over blurred material.

## Geometry

| Spacing | Value | | Radius | Value |
|---|---|---|---|---|
| `xs` | 6 | | `sm` | 14 |
| `sm` | 10 | | `md` | 20 |
| `md` | 16 | | `lg` | 28 |
| `lg` | 24 | | `pill` | 999 |
| `xl` | 32 | | | |

**Tab-bar clearance:** `contentAvoidancePadding = 96` — scrollable content must leave this much bottom space so it clears the custom tab bar. (This is exactly the overlap the audit flagged; honor it.)

## Typography

System font (SF). Display/metric numerals are large and high-contrast (athletic, glanceable); body uses regular system weights. No custom font is bundled — assume **SF Pro** (consider `.rounded` for display, and tabular/monospaced digits for live run metrics). Flag any type-system change as a token change.

## Identity notes

- Visual feel: **dark, high-contrast, premium athletic**, with an `RS` mark.
- Lime (`#CCFF00`) is the unmistakable "go / primary action" color (Start Run, primary CTAs).
- Multi-accent metric chips/rings for energy/recovery/heart/success.
- Rounded cards (radius 14–28), thin white hairline borders.
