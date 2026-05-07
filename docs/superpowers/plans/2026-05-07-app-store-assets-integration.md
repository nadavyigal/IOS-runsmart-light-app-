# App Store Assets Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the generated Resumely design-assets into the Xcode project so the app ships with the correct icon, accent colour, brand colours, logo on the onboarding screen, and a branded launch screen.

**Architecture:** Pure file-system changes to the Xcode asset catalog + two Swift source edits. No new dependencies. No xcodeproj graph changes needed (the `.xcassets` folder is already referenced as a group, so any new imagesets inside it are auto-discovered by Xcode).

**Tech Stack:** Xcode 16 / Swift 6 / SwiftUI — iOS app target `Resumebuilder-IOS.ResumeBuilder-IOS-APP`

---

## File Map

| Action | Path | Change |
|--------|------|--------|
| Modify | `ResumeBuilder IOS APP/Assets.xcassets/AppIcon.appiconset/Contents.json` | Add filename refs for 3 icon PNGs |
| Copy ×3 | `ResumeBuilder IOS APP/Assets.xcassets/AppIcon.appiconset/` | Main / Dark / Tinted 1024 PNGs |
| Modify | `ResumeBuilder IOS APP/Assets.xcassets/AccentColor.colorset/Contents.json` | Set to #6C63FF |
| Create | `ResumeBuilder IOS APP/Assets.xcassets/LaunchBackground.colorset/Contents.json` | #050814 dark navy |
| Create | `ResumeBuilder IOS APP/Assets.xcassets/ResumelyMark.imageset/Contents.json` | Image set manifest |
| Copy | `ResumeBuilder IOS APP/Assets.xcassets/ResumelyMark.imageset/ResumelyMark.png` | Square badge logo |
| Modify | `ResumeBuilder IOS APP/Core/DesignSystem/Theme.swift` | Full brand palette |
| Modify | `ResumeBuilder IOS APP/Features/Onboarding/OnboardingView.swift` | Brand logo + dark theme visuals |
| Modify | `ResumeBuilder IOS APP.xcodeproj/project.pbxproj` | Add LaunchScreen background colour key (×2 configs) |

---

### Task 1: Wire App Icons into the Asset Catalog

**Files:**
- Modify: `ResumeBuilder IOS APP/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Copy: `AppIcon_Main_1024.png`, `AppIcon_Dark_1024.png`, `AppIcon_Tinted_1024.png`

- [ ] Copy the three icon PNGs from `design-assets/app-icons/` into `AppIcon.appiconset/`
- [ ] Replace `Contents.json` with the correct filename references
- [ ] Verify no build error in Xcode (open project and check the icon slots are filled)

---

### Task 2: Accent Color → Brand Violet #6C63FF

**Files:**
- Modify: `ResumeBuilder IOS APP/Assets.xcassets/AccentColor.colorset/Contents.json`

- [ ] Write new Contents.json with sRGB components R:0.424 G:0.388 B:1.000

---

### Task 3: Launch Background Color #050814

**Files:**
- Create: `ResumeBuilder IOS APP/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- Modify: `ResumeBuilder IOS APP.xcodeproj/project.pbxproj` (lines 262, 296)

- [ ] Create `LaunchBackground.colorset` with sRGB R:0.020 G:0.031 B:0.078
- [ ] Add `INFOPLIST_KEY_UILaunchScreen_BackgroundColor = LaunchBackground;` to both Debug and Release configs in pbxproj

---

### Task 4: Add ResumelyMark Image Set

**Files:**
- Create: `ResumeBuilder IOS APP/Assets.xcassets/ResumelyMark.imageset/Contents.json`
- Copy: `ResumelyMark.png` (from `design-assets/logos/Logo_SquareBadge.png`)

- [ ] Create the imageset folder and Contents.json referencing a universal 1× image
- [ ] Copy the square badge PNG as `ResumelyMark.png`

---

### Task 5: Update Theme.swift with Full Brand Palette

**Files:**
- Modify: `ResumeBuilder IOS APP/Core/DesignSystem/Theme.swift`

- [ ] Replace stub colours with the complete Resumely brand palette

---

### Task 6: Update OnboardingView with Brand Visuals

**Files:**
- Modify: `ResumeBuilder IOS APP/Features/Onboarding/OnboardingView.swift`

- [ ] Replace `Image(systemName: "doc.text.magnifyingglass")` with `Image("ResumelyMark")`
- [ ] Apply dark navy background, brand button style, gradient headline
- [ ] Keep all auth logic unchanged (SignInWithApple, email form, error handling)

---

### Task 7: Commit

- [ ] `git add -A && git commit -m "feat: integrate Resumely brand assets for App Store"`
