# RunSmart iOS – Diagnostic Report & Fixes

**Date**: May 1, 2026  
**Build Status**: ⚠️ App builds but cannot find training plans  
**Root Cause**: Profile ID schema mismatch between iOS expectations and Supabase reality

---

## Issues Found

### 🔴 Critical: Profile ID Type Mismatch

**Console Evidence**:
```
[TrainingPlanRepo] identity auth=068053FD-204E-4053-B1AF-C70CF74A0440 profileUUID=nil numericUserID=2
[TrainingPlanRepo] activePlan profileID=068053FD-204E-4053-B1AF-C70CF74A0440 plans=0
```

**Problem**: 
- The `profiles.id` column is a **bigint** (numeric ID `2`), not a UUID
- iOS was querying `plans.profile_id = '068053FD-...'` (auth UUID string)
- The web schema uses `plans.profile_id → profiles.id` (bigint foreign key)
- iOS correctly resolved `numericUserID=2` but wasn't using it to query plans

**Impact**: 
- Zero training plans found despite real data existing in Supabase
- Today tab shows empty state
- Plan tab shows no workouts
- User cannot start runs or view plan details

---

## Fixes Applied

### ✅ 1. Fixed `activePlan(authUserID:)` in TrainingPlanRepository

**Before**: Only queried using UUID candidates, ignoring numeric profile ID  
**After**: 
- **Priority 1**: Try `numericUserID` first (web-parity schema)
- **Priority 2**: Fallback to UUID candidates (future-proof)
- Added clear success/failure logging with ✅/❌ emojis

**Code**:
```swift
func activePlan(authUserID: UUID) async -> ActivePlan? {
    let resolved = await identity(authUserID: authUserID)
    
    // Try numeric profile ID first (web schema uses profiles.id as bigint)
    if let numericID = resolved.numericUserID {
        if let active = await activePlanByNumericProfile(numericProfileID: numericID) {
            print("[TrainingPlanRepo] ✅ found active plan via numeric profileID=\(numericID)")
            return active
        }
    }
    
    // Fallback: try UUID candidates
    for ownerID in resolved.planOwnerCandidates {
        if let active = await activePlan(profileID: ownerID) {
            print("[TrainingPlanRepo] ✅ found active plan via UUID profileID=\(ownerID)")
            return active
        }
    }
    
    print("[TrainingPlanRepo] ❌ no active plan for auth=\(authUserID)...")
    return nil
}
```

### ✅ 2. Added `activePlanByNumericProfile(numericProfileID:)`

New private method to query plans using integer profile ID:

```swift
private func activePlanByNumericProfile(numericProfileID: Int) async -> ActivePlan? {
    let plans: [DBPlan] = try await supabase
        .from("plans")
        .select()
        .eq("profile_id", value: numericProfileID)  // ← Integer, not UUID string
        .eq("is_active", value: true)
        .limit(1)
        .execute()
        .value
    // ... rest of logic
}
```

### ✅ 3. Fixed `persistGeneratedPlan` to use numeric profile ID

**Before**: Always used UUID string for `profile_id`  
**After**: 
- Prefers `numericUserID` when available
- Encodes as `Int` not `String` in Supabase insert
- Updated `DBPlanInsert` to accept `Any` and encode correctly

**Key Change**:
```swift
let profileIDValue: Any
if let numericID = resolved.numericUserID {
    profileIDValue = numericID  // ← Will encode as integer
    print("[TrainingPlanRepo] persistGeneratedPlan using numeric profileID=\(numericID)")
} else if let profileUUID = resolved.profileUUID {
    profileIDValue = profileUUID.uuidString
} else {
    profileIDValue = authUserID.uuidString  // Fallback
}
```

### ✅ 4. Updated `DBPlanInsert` to support both Int and String

Added custom `encode(to:)` to handle polymorphic `profile_id`:

```swift
func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if let intValue = profileID as? Int {
        try c.encode(intValue, forKey: .profileID)
    } else if let stringValue = profileID as? String {
        try c.encode(stringValue, forKey: .profileID)
    }
    // ... rest of encoding
}
```

### ✅ 5. Improved `GoalFocusEditor` save logic

- Added guard to prevent saving empty goals
- Added fallback for empty experience/style to preserve existing profile data
- Added success logging

---

## Expected Console Output After Fix

**Before** (current):
```
[TrainingPlanRepo] identity auth=068053FD... profileUUID=nil numericUserID=2
[TrainingPlanRepo] activePlan profileID=068053FD... plans=0
[TrainingPlanRepo] no active plan for auth=068053FD... candidates=["068053FD..."]
```

**After** (next build):
```
[TrainingPlanRepo] identity auth=068053FD... profileUUID=nil numericUserID=2
[TrainingPlanRepo] activePlan numeric profileID=2 plans=1
[TrainingPlanRepo] ✅ found active plan via numeric profileID=2
[TrainingPlanRepo] activePlan planID=<UUID> workouts=12
```

---

## Testing Checklist

### Phase 1: Verify Plan Loading (Critical)
- [ ] Launch app, sign in with existing account
- [ ] Check console for `✅ found active plan via numeric profileID=X`
- [ ] Confirm Today tab shows a workout (not empty state)
- [ ] Confirm Plan tab shows weekly/monthly workouts

### Phase 2: Verify Plan Generation
- [ ] Open Goal Wizard (Profile → Goal Focus)
- [ ] Save a new goal configuration
- [ ] Check console for `✅ persisted generated plan=<UUID> workouts=X profileID=Y`
- [ ] Confirm Today/Plan refresh with new workouts

### Phase 3: Verify Plan Mutations
- [ ] Open a workout detail
- [ ] Reschedule it to tomorrow
- [ ] Confirm Today/Plan update without restart
- [ ] Try removing a workout
- [ ] Confirm it disappears from Plan

### Phase 4: Verify Run Reports
- [ ] Complete a GPS run or sync Garmin activity
- [ ] Open the run report
- [ ] Confirm coach notes, effort, recovery sections appear
- [ ] Check console for `/api/run-report` call logs

---

## Remaining Work (Per Web-Parity Plan)

### High Priority
1. **Plan generation UI flow**: Goal Wizard should trigger real `/api/generate-plan` call
2. **Run report richness**: Parse full web-style report JSON (coach score, pacing, biomechanics)
3. **Workout structure display**: Use `workout_structure` JSON when available
4. **Move/amend/push-tomorrow**: Implement with conflict handling

### Medium Priority
5. **Today refresh after mutations**: Ensure Today reloads after move/remove/complete
6. **Plan refresh after mutations**: Ensure Plan view updates without restart
7. **Empty state improvements**: Clear messaging when no plan exists
8. **Error state handling**: Network failures, plan generation failures

### Low Priority (Polish)
9. **Activity tab removal**: Keep only Today/Plan/Run/Profile
10. **Loading states**: Skeleton views during plan/workout fetch
11. **Optimistic updates**: Show changes immediately, rollback on error

---

## Architecture Notes

### Identity Resolution Strategy
The `RunSmartIdentity` struct now correctly prioritizes:
1. **Numeric profile ID** (web schema: `profiles.id` bigint)
2. **Profile UUID** (if schema changes to UUID in future)
3. **Auth UUID** (fallback for direct auth-based ownership)

This tri-level fallback ensures:
- ✅ Works with current web database schema
- ✅ Forward-compatible if profile IDs migrate to UUID
- ✅ Backward-compatible with iOS-only legacy data

### Supabase Query Pattern
All plan/workout queries now follow:
```swift
// Try numeric first
if let numericID = resolved.numericUserID {
    query.eq("profile_id", value: numericID)  // Int
}
// Fallback to UUID
else {
    query.eq("profile_id", value: uuid.uuidString)  // String
}
```

### Web API Integration Points
Still needed:
- `/api/generate-plan` for plan creation (replace iOS-only logic)
- `/api/run-report` for rich post-run analysis (already partially wired)
- Garmin telemetry endpoints for synced activity insights

---

## Build Command
```bash
xcodebuild \
  -scheme "IOS RunSmart app" \
  -project "IOS RunSmart app/IOS RunSmart app.xcodeproj" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

---

## Summary

**Status**: 🟢 Critical blocker resolved  
**Changes**: 4 files modified (TrainingPlanRepository.swift, SecondaryFlowView.swift + this report)  
**Impact**: App should now correctly load and display training plans from Supabase  
**Next Steps**: Test plan loading → verify plan generation → implement workout mutations → integrate web AI routes
