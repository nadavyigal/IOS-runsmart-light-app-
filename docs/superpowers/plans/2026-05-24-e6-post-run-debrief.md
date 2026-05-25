# E6 — Post-Run Debrief Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the deterministic `PostRunLearningCard` with an AI-generated post-run debrief (headline + 1-2 sentence reaction + "what it means for tomorrow"), falling back to the existing deterministic content when the AI call times out or fails.

**Architecture:** Extend the existing `coach_message` Supabase Edge Function with a `run_debrief` intent that returns structured JSON. iOS calls this inside `processCompletedActivity` (3-second timeout, concurrent with report generation). The result is stored in a new `run_debriefs` Supabase table and returned in `PostActivityOutcome.debrief`. The card reads from the outcome — no view-level async required.

**Tech Stack:** Swift / SwiftUI, Supabase (Postgres + Edge Functions), Deno/TypeScript, OpenAI Responses API (`gpt-4.1-mini`)

**Spec:** `docs/superpowers/specs/2026-05-24-e2-e6-design.md` — Section 2

---

## File Map

| File | Change |
|------|--------|
| `supabase/migrations/20260524000001_run_debriefs.sql` | Create (new migration) |
| `supabase/functions/coach_message/index.ts` | Modify — add `run_debrief` intent routing |
| `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift` | Modify — add `RunDebriefRequestDTO`, `RunDebriefResponseDTO` |
| `IOS RunSmart app/Models/RunSmartModels.swift` | Modify — add `PostRunDebriefModel`, extend `PostActivityOutcome` |
| `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` | Modify — add `fetchRunDebrief`, `persistDebrief`, wire into `processCompletedActivity` |
| `IOS RunSmart app/Features/Run/PostRunLearningCard.swift` | Modify — read from `PostRunDebriefModel` when available |
| `IOS RunSmart appTests/RunSmartReadinessTests.swift` | Modify — add E6 test cases |

---

## Task 1: Supabase migration — `run_debriefs` table

**Files:**
- Create: `supabase/migrations/20260524000001_run_debriefs.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/20260524000001_run_debriefs.sql
create table if not exists public.run_debriefs (
  id           uuid        primary key default gen_random_uuid(),
  auth_user_id uuid        not null references auth.users(id) on delete cascade,
  run_id       uuid        not null,
  headline     text        not null,
  debrief      text        not null,
  tomorrow     text        not null,
  plan_impact  text,
  source       text        not null default 'ai',
  created_at   timestamptz not null default now()
);

-- One debrief per run per user; re-running processCompletedActivity upserts safely
create unique index if not exists run_debriefs_user_run_uidx
  on public.run_debriefs (auth_user_id, run_id);

alter table public.run_debriefs enable row level security;

create policy "owner_all" on public.run_debriefs
  for all
  using  (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());
```

- [ ] **Step 2: Apply the migration via Supabase MCP**

Use `mcp__c5035e6b...apply_migration` with the SQL above, or run:
```bash
supabase db push
```
Expected: migration applies without error; `run_debriefs` table appears in Supabase dashboard.

- [ ] **Step 3: Verify table exists**

```bash
supabase db diff
```
Expected: diff is empty (migration applied cleanly).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260524000001_run_debriefs.sql
git commit -m "feat(e6): add run_debriefs table with RLS"
```

---

## Task 2: Backend — `run_debrief` intent in `coach_message`

**Files:**
- Modify: `supabase/functions/coach_message/index.ts`

- [ ] **Step 1: Add the run_debrief system prompt constant**

After the existing `SYSTEM_PROMPT` constant (line ~25), add:

```typescript
const RUN_DEBRIEF_SYSTEM_PROMPT = `You are RunSmart Coach. Given a completed run's data, write a short post-run debrief.

Return ONLY valid JSON — no markdown, no explanation — in exactly this shape:
{
  "headline": "One short coach reaction (max 40 characters)",
  "debrief": "1-2 sentences referencing at least one real signal from the run (pace, HR, distance, effort)",
  "tomorrow": "One sentence: what this run means for tomorrow",
  "planImpact": "Short phrase or null"
}

Rules:
- Be specific: reference actual numbers from the context.
- Be warm and direct. No filler.
- Do not diagnose injuries or give medical advice.
- If injurySignal is true in context, set headline to "Rest up — listen to your body", debrief to "Any pain or discomfort after a run needs rest first. Check in with a professional before your next session.", tomorrow to "Take a full rest day tomorrow.", planImpact to null.
- Do not shame any result.
- Conservative guidance under uncertainty.`;
```

- [ ] **Step 2: Add the `generateRunDebrief` function**

Before the `Deno.serve` call, add:

```typescript
async function generateRunDebrief(context: JsonRecord): Promise<{
  headline: string;
  debrief: string;
  tomorrow: string;
  planImpact: string | null;
  source: CoachSource;
}> {
  const injurySignal = Boolean(context.injurySignal);
  if (injurySignal) {
    return {
      headline: "Rest up — listen to your body",
      debrief: "Any pain or discomfort after a run needs rest first. Check in with a professional before your next session.",
      tomorrow: "Take a full rest day tomorrow.",
      planImpact: null,
      source: "fallback",
    };
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL") || "gpt-4.1-mini";
  if (!apiKey) {
    return fallbackRunDebrief(context, model);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      signal: controller.signal,
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        instructions: RUN_DEBRIEF_SYSTEM_PROMPT,
        input: [{
          role: "user",
          content: [{ type: "input_text", text: `Run data:\n${JSON.stringify(context)}` }],
        }],
        max_output_tokens: 180,
      }),
    });
    if (!response.ok) throw new Error(`OpenAI ${response.status}`);
    const json = await response.json();
    const text = extractResponseText(json).trim();
    const parsed = JSON.parse(text);
    return {
      headline: limitString(parsed.headline, 40),
      debrief: limitString(parsed.debrief, 300),
      tomorrow: limitString(parsed.tomorrow, 160),
      planImpact: parsed.planImpact ? limitString(parsed.planImpact, 60) : null,
      source: "live_ai",
    };
  } catch (error) {
    console.error("run_debrief AI fallback", error);
    return fallbackRunDebrief(context, model);
  } finally {
    clearTimeout(timeout);
  }
}

function fallbackRunDebrief(context: JsonRecord, _model: string): {
  headline: string; debrief: string; tomorrow: string; planImpact: string | null; source: CoachSource;
} {
  const distanceKm = typeof context.runDistanceKm === "number" ? context.runDistanceKm.toFixed(1) : "–";
  const durationMin = typeof context.runDurationSeconds === "number"
    ? Math.round((context.runDurationSeconds as number) / 60)
    : null;
  const durationStr = durationMin ? `${durationMin} min` : "";
  return {
    headline: "Run logged",
    debrief: `You covered ${distanceKm} km${durationStr ? ` in ${durationStr}` : ""}. RunSmart has logged this effort toward your training.`,
    tomorrow: "Check Today tomorrow for your next recommended session.",
    planImpact: null,
    source: "fallback",
  };
}
```

- [ ] **Step 3: Add `run_debrief` routing to `Deno.serve`**

In `Deno.serve`, after parsing `body`, before the existing `!message` validation, add intent reading and routing:

```typescript
// Add after: const context = asRecord(body.context);
const intent = stringValue(body.intent) || "chat";

// Route run_debrief before the chat-specific validation
if (intent === "run_debrief") {
  if (!context || containsForbiddenKeys(context)) {
    return jsonResponse({ error: "Context contains forbidden keys" }, 400);
  }
  const safeContext = {
    runDistanceKm: typeof context.runDistanceKm === "number" ? context.runDistanceKm : 0,
    runDurationSeconds: typeof context.runDurationSeconds === "number" ? context.runDurationSeconds : 0,
    averagePaceMinPerKm: typeof context.averagePaceMinPerKm === "number" ? context.averagePaceMinPerKm : null,
    averageHeartRateBPM: typeof context.averageHeartRateBPM === "number" ? context.averageHeartRateBPM : null,
    workoutType: limitString(context.workoutType, 40),
    planPhase: context.planPhase ? limitString(context.planPhase, 80) : null,
    recentLoadDays: typeof context.recentLoadDays === "number" ? context.recentLoadDays : 0,
    injurySignal: Boolean(context.injurySignal),
  };
  const debrief = await generateRunDebrief(safeContext);
  return jsonResponse(debrief);
}

// Existing chat validation continues below
if (!message) {
  return jsonResponse({ error: "Message is required" }, 400);
}
```

- [ ] **Step 4: Deno type-check**

```bash
npx -y deno check supabase/functions/coach_message/index.ts
```
Expected: no type errors.

- [ ] **Step 5: Local smoke test**

```bash
# start local supabase if not running
supabase functions serve coach_message --env-file supabase/.env.local
```

In a second terminal:
```bash
curl -s -X POST http://localhost:54321/functions/v1/coach_message \
  -H "Authorization: Bearer <your-local-anon-jwt>" \
  -H "Content-Type: application/json" \
  -d '{
    "intent": "run_debrief",
    "context": {
      "runDistanceKm": 5.2,
      "runDurationSeconds": 1680,
      "averagePaceMinPerKm": 5.38,
      "workoutType": "easy",
      "recentLoadDays": 3
    }
  }' | jq .
```
Expected: JSON with `headline`, `debrief`, `tomorrow`, `source` fields. No `error` key.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/coach_message/index.ts
git commit -m "feat(e6): add run_debrief intent to coach_message edge function"
```

---

## Task 3: iOS DTOs

**Files:**
- Modify: `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`

- [ ] **Step 1: Write a failing parse test first**

In `IOS RunSmart appTests/RunSmartReadinessTests.swift`, add inside the existing test class:

```swift
func testRunDebriefRequestDTOEncodesIntent() throws {
    let dto = RunSmartDTO.RunDebriefRequestDTO(
        runDistanceKm: 5.0,
        runDurationSeconds: 1500,
        averagePaceMinPerKm: 5.0,
        averageHeartRateBPM: nil,
        workoutType: "easy",
        planPhase: nil,
        recentLoadDays: 2,
        limitations: []
    )
    let data = try JSONEncoder().encode(dto)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["intent"] as? String, "run_debrief")
    XCTAssertEqual(json["runDistanceKm"] as? Double, 5.0)
}

func testRunDebriefResponseDTODecodes() throws {
    let json = """
    {
      "headline": "Solid effort",
      "debrief": "You held pace well for 5 km.",
      "tomorrow": "Easy day tomorrow.",
      "planImpact": "Plan stays on track",
      "source": "live_ai"
    }
    """
    let data = json.data(using: .utf8)!
    let dto = try JSONDecoder().decode(RunSmartDTO.RunDebriefResponseDTO.self, from: data)
    XCTAssertEqual(dto.headline, "Solid effort")
    XCTAssertEqual(dto.source, "live_ai")
}
```

- [ ] **Step 2: Run the tests — verify they fail (type not defined)**

```bash
xcrun swiftc -parse "IOS RunSmart appTests/RunSmartReadinessTests.swift"
```
Expected: compile error referencing `RunSmartDTO.RunDebriefRequestDTO`.

- [ ] **Step 3: Add the DTOs to `RunSmartAPIModels.swift`**

Inside `enum RunSmartDTO { }`, after the `WellnessContextDTO` struct (around line 448), add:

```swift
struct RunDebriefRequestDTO: Encodable {
    let intent: String = "run_debrief"
    let runDistanceKm: Double
    let runDurationSeconds: Int
    let averagePaceMinPerKm: Double?
    let averageHeartRateBPM: Int?
    let workoutType: String
    let planPhase: String?
    let recentLoadDays: Int
    let limitations: [String]
}

struct RunDebriefResponseDTO: Decodable {
    let headline: String
    let debrief: String
    let tomorrow: String
    let planImpact: String?
    let source: String
}
```

- [ ] **Step 4: Swift parse check**

```bash
xcrun swiftc -parse "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift"
```
Expected: no errors.

- [ ] **Step 5: Run the DTO tests**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRunDebriefRequestDTOEncodesIntent" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRunDebriefResponseDTODecodes" \
  -derivedDataPath /tmp/runsmart-e6-derived \
  test
```
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(e6): add RunDebriefRequestDTO and RunDebriefResponseDTO"
```

---

## Task 4: iOS model — `PostRunDebriefModel` + extend `PostActivityOutcome`

**Files:**
- Modify: `IOS RunSmart app/Models/RunSmartModels.swift`

- [ ] **Step 1: Write failing model tests**

In `RunSmartReadinessTests.swift`, add:

```swift
func testPostRunDebriefModelFallbackHasContent() {
    let run = RecordedRun.makeStub(distanceMeters: 5000, movingTimeSeconds: 1500)
    let fallback = PostRunDebriefModel.fallback(for: run)
    XCTAssertFalse(fallback.headline.isEmpty)
    XCTAssertFalse(fallback.debrief.isEmpty)
    XCTAssertFalse(fallback.tomorrow.isEmpty)
    XCTAssertEqual(fallback.source, .fallback)
}

func testPostActivityOutcomeHasDebriefField() {
    let run = RecordedRun.makeStub(distanceMeters: 3000, movingTimeSeconds: 1200)
    let outcome = PostActivityOutcome(
        canonicalRun: run,
        report: nil,
        completedWorkout: nil,
        didCompletePlannedWorkout: false,
        debrief: nil
    )
    XCTAssertNil(outcome.debrief)
}
```

Note: `RecordedRun.makeStub` may need to be added as a test helper if it doesn't exist — use whatever factory exists in the test file already (search for `RecordedRun(` in the test file for the pattern).

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcrun swiftc -parse "IOS RunSmart appTests/RunSmartReadinessTests.swift"
```
Expected: compile error for `PostRunDebriefModel`.

- [ ] **Step 3: Add `PostRunDebriefModel` to `RunSmartModels.swift`**

After the `PostRunPlanImpact` / `PostRunLearningCardModel` block (search for `struct PostRunLearningCardModel` — add below its closing brace), add:

```swift
struct PostRunDebriefModel: Hashable {
    enum Source: String, Hashable {
        case ai
        case fallback
    }

    var headline: String
    var debrief: String
    var tomorrow: String
    var planImpact: String?
    var source: Source

    static func fallback(for run: RecordedRun?) -> PostRunDebriefModel {
        let distanceKm = (run?.distanceMeters ?? 0) / 1_000
        let durationMin = Int((run?.movingTimeSeconds ?? 0) / 60)
        let distanceStr = distanceKm > 0 ? String(format: "%.1f km", distanceKm) : "your run"
        let durationStr = durationMin > 0 ? " in \(durationMin) min" : ""
        return PostRunDebriefModel(
            headline: "Run logged",
            debrief: "You covered \(distanceStr)\(durationStr). RunSmart has recorded this effort.",
            tomorrow: "Check Today tomorrow for your next recommended session.",
            planImpact: nil,
            source: .fallback
        )
    }
}
```

- [ ] **Step 4: Add `debrief` field to `PostActivityOutcome`**

Find `struct PostActivityOutcome: Hashable` (currently at line ~1412) and add the field:

```swift
struct PostActivityOutcome: Hashable {
    var canonicalRun: RecordedRun
    var report: RunReportDetail?
    var completedWorkout: WorkoutSummary?
    var didCompletePlannedWorkout: Bool
    var debrief: PostRunDebriefModel?          // E6: AI post-run debrief
}
```

The existing call site in `processCompletedActivity` constructs `PostActivityOutcome(...)` — Swift will require adding `debrief:` there. Add `debrief: nil` to the existing initializer call for now (you'll replace it in Task 5).

- [ ] **Step 5: Swift parse check for both model files**

```bash
xcrun swiftc -parse \
  "IOS RunSmart app/Models/RunSmartModels.swift" \
  "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift"
```
Expected: no errors (the existing `PostActivityOutcome(...)` call needs `debrief: nil` added).

- [ ] **Step 6: Run the model tests**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testPostRunDebriefModelFallbackHasContent" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testPostActivityOutcomeHasDebriefField" \
  -derivedDataPath /tmp/runsmart-e6-derived \
  test
```
Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
git add "IOS RunSmart app/Models/RunSmartModels.swift" \
        "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(e6): add PostRunDebriefModel and debrief field to PostActivityOutcome"
```

---

## Task 5: iOS service — `fetchRunDebrief` + wire into `processCompletedActivity`

**Files:**
- Modify: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`

- [ ] **Step 1: Write a failing service test**

In `RunSmartReadinessTests.swift`, add:

```swift
func testFetchRunDebriefReturnsFallbackWithoutAuth() async {
    // Use a fake/non-Supabase service that has no auth session
    let services = FakeRunSmartServices()
    // FakeRunSmartServices.processCompletedActivity should return
    // a PostActivityOutcome where debrief.source == .fallback (no real network)
    let run = RecordedRun.makeStub(distanceMeters: 4000, movingTimeSeconds: 1320)
    let outcome = await services.processCompletedActivity(run)
    // The fake service returns a fallback debrief (no live Supabase available)
    XCTAssertNotNil(outcome.debrief)
    if let debrief = outcome.debrief {
        XCTAssertFalse(debrief.headline.isEmpty)
    }
}
```

Note: this test verifies that `processCompletedActivity` always returns a non-nil debrief, even in the fake/offline case. Adjust to whichever fake service class is already used in this test file.

- [ ] **Step 2: Add `fetchRunDebrief` to `SupabaseRunSmartServices`**

Add this private method before `processCompletedActivity`:

```swift
private func fetchRunDebrief(for run: RecordedRun) async -> PostRunDebriefModel {
    guard let token = try? await supabase.auth.session.accessToken else {
        return .fallback(for: run)
    }

    let distanceKm = run.distanceMeters / 1_000.0
    let durationSec = run.movingTimeSeconds
    let paceMinPerKm: Double? = distanceKm > 0 && durationSec > 0
        ? (Double(durationSec) / 60.0) / distanceKm
        : nil
    let recentCount = store.loadRuns()
        .filter { Calendar.current.dateComponents([.day], from: $0.startedAt, to: Date()).day.map { $0 <= 7 } ?? false }
        .count

    let request = RunSmartDTO.RunDebriefRequestDTO(
        runDistanceKm: distanceKm,
        runDurationSeconds: durationSec,
        averagePaceMinPerKm: paceMinPerKm,
        averageHeartRateBPM: run.averageHeartRateBPM,
        workoutType: "easy",
        planPhase: nil,
        recentLoadDays: recentCount,
        limitations: []
    )
    guard let body = try? JSONEncoder().encode(request) else {
        return .fallback(for: run)
    }
    let client = URLSessionRunSmartAPIClient(
        baseURL: SupabaseManager.functionsBaseURL,
        accessToken: token,
        additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
    )
    do {
        let response = try await withThrowingTaskGroup(of: RunSmartDTO.RunDebriefResponseDTO.self) { group in
            group.addTask {
                try await client.send(
                    RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
                    as: RunSmartDTO.RunDebriefResponseDTO.self
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw CancellationError()
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
        let model = PostRunDebriefModel(
            headline: response.headline,
            debrief: response.debrief,
            tomorrow: response.tomorrow,
            planImpact: response.planImpact,
            source: .ai
        )
        await persistDebrief(model, for: run)
        return model
    } catch {
        if !(error is CancellationError) {
            print("[SupabaseServices] run_debrief fallback:", error)
        }
        return .fallback(for: run)
    }
}

private func persistDebrief(_ debrief: PostRunDebriefModel, for run: RecordedRun) async {
    guard let userID = currentUserID else { return }
    do {
        try await supabase
            .from("run_debriefs")
            .upsert(
                [
                    "auth_user_id": userID.uuidString,
                    "run_id": run.id.uuidString,
                    "headline": debrief.headline,
                    "debrief": debrief.debrief,
                    "tomorrow": debrief.tomorrow,
                    "plan_impact": debrief.planImpact as Any,
                    "source": debrief.source.rawValue,
                ],
                onConflict: "auth_user_id,run_id"
            )
            .execute()
    } catch {
        if !(error is CancellationError) {
            print("[SupabaseServices] persistDebrief error:", error)
        }
    }
}
```

- [ ] **Step 3: Wire `fetchRunDebrief` into `processCompletedActivity`**

Find `processCompletedActivity` and update it to run the debrief concurrently:

```swift
func processCompletedActivity(_ run: RecordedRun) async -> PostActivityOutcome {
    let canonical = saveRouteMatch(for: ActivityConsolidationService.canonicalRun(for: run, in: await recentRuns(limit: 100)))
    await upsertCompletedRunIfPossible(canonical)
    store.refreshBenchmarkStats()
    async let reportTask = generateRunReportIfMissing(for: canonical)
    async let completedTask = completeMatchingWorkout(for: canonical)
    async let debriefTask = fetchRunDebrief(for: canonical)          // E6
    let (report, completed, debrief) = await (reportTask, completedTask, debriefTask)

    await MainActor.run {
        NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        NotificationCenter.default.post(name: .runSmartReportsDidChange, object: nil)
        NotificationCenter.default.post(name: .runSmartPlanDidChange, object: nil)
        if let completed {
            PushService.shared.cancelWorkoutReminder(workoutID: completed.id)
        }
    }

    return PostActivityOutcome(
        canonicalRun: canonical,
        report: report,
        completedWorkout: completed,
        didCompletePlannedWorkout: completed != nil,
        debrief: debrief                                              // E6
    )
}
```

- [ ] **Step 4: Swift parse check**

```bash
xcrun swiftc -parse \
  "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift" \
  "IOS RunSmart app/Models/RunSmartModels.swift" \
  "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift"
```
Expected: no errors.

- [ ] **Step 5: Generic simulator build**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-e6-derived \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(e6): wire fetchRunDebrief into processCompletedActivity"
```

---

## Task 6: Card view — upgrade `PostRunLearningCard`

**Files:**
- Modify: `IOS RunSmart app/Features/Run/PostRunLearningCard.swift`
- Modify: `IOS RunSmart app/Features/Run/PostRunSummaryView.swift`

- [ ] **Step 1: Add `debrief` parameter to `PostRunLearningCard`**

In `PostRunLearningCard.swift`, add a new stored property alongside the existing ones:

```swift
struct PostRunLearningCard: View {
    @Environment(\.runSmartServices) private var services
    var run: RecordedRun?
    var outcome: PostActivityOutcome?
    var report: RunReportDetail?
    var isProcessing: Bool = false
    var debrief: PostRunDebriefModel? = nil       // E6: AI debrief (nil = use deterministic)

    // ... existing @State properties unchanged
```

- [ ] **Step 2: Add a skeleton view**

Add a private `skeletonBody` computed property inside `PostRunLearningCard`:

```swift
private var skeletonBody: some View {
    RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("COACH REACTION", systemImage: "sparkles")
                    .font(.labelLG)
                    .foregroundStyle(Color.accentPrimary)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.textSecondary.opacity(0.2))
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.textSecondary.opacity(0.2))
                .frame(height: 14)
                .frame(maxWidth: .infinity * 0.75)
        }
    }
    .redacted(reason: .placeholder)
}
```

- [ ] **Step 3: Update `body` to branch on debrief state**

Replace the existing `var body: some View` in `PostRunLearningCard` with:

```swift
var body: some View {
    if isProcessing && debrief == nil {
        skeletonBody
    } else if let debrief {
        debriefBody(debrief)
    } else {
        deterministicBody
    }
}
```

- [ ] **Step 4: Add `debriefBody` view**

Add a private method that renders AI debrief content:

```swift
private func debriefBody(_ debrief: PostRunDebriefModel) -> some View {
    RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Label("COACH REACTION", systemImage: "sparkles")
                    .font(.labelLG)
                    .foregroundStyle(Color.accentPrimary)
                Spacer()
                StatusChip(
                    text: debrief.source == .ai ? "AI" : "Coach",
                    tint: debrief.source == .ai ? .accentPrimary : .textSecondary
                )
            }

            Text(debrief.headline)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Text(debrief.debrief)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Tomorrow")
                    .font(.labelSM)
                    .foregroundStyle(Color.textSecondary)
                Text(debrief.tomorrow)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let planImpact = debrief.planImpact {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentSuccess)
                    Text(planImpact)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}
```

- [ ] **Step 5: Rename the existing `body` content as `deterministicBody`**

Wrap the existing card rendering (the one that uses `model: PostRunLearningCardModel`) in a computed property called `deterministicBody`:

```swift
private var deterministicBody: some View {
    // paste the existing RunSmartPanel { ... } body here unchanged
}
```

- [ ] **Step 6: Update `PostRunSummaryView` call site**

In `PostRunSummaryView.swift`, the call at line ~57 currently is:
```swift
PostRunLearningCard(
    run: run,
    outcome: outcome,
    report: outcome?.report,
    isProcessing: isProcessing
)
```

Update to pass the debrief from the outcome:
```swift
PostRunLearningCard(
    run: run,
    outcome: outcome,
    report: outcome?.report,
    isProcessing: isProcessing,
    debrief: outcome?.debrief        // E6: AI debrief from processCompletedActivity
)
```

- [ ] **Step 7: Swift parse check**

```bash
xcrun swiftc -parse \
  "IOS RunSmart app/Features/Run/PostRunLearningCard.swift" \
  "IOS RunSmart app/Features/Run/PostRunSummaryView.swift"
```
Expected: no errors.

- [ ] **Step 8: Generic simulator build**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-e6-derived \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Visual check in simulator**

Install on iPhone 17 Pro simulator, sign in, complete a run (or trigger `processCompletedActivity` via the debug/screenshot mode). Verify:
- Skeleton card shows while `isProcessing == true` and `debrief == nil`
- AI debrief card renders with headline, debrief body, tomorrow row
- Dark mode passes (check in Simulator > Features > Toggle Appearance)

- [ ] **Step 10: Commit**

```bash
git add "IOS RunSmart app/Features/Run/PostRunLearningCard.swift" \
        "IOS RunSmart app/Features/Run/PostRunSummaryView.swift"
git commit -m "feat(e6): upgrade PostRunLearningCard with AI debrief + skeleton loading"
```

---

## Task 7: Deploy + end-to-end validation

**Files:** no new files; validates everything together.

- [ ] **Step 1: Deploy the updated Edge Function**

```bash
# Ensure SUPABASE_ACCESS_TOKEN is set in your local.env
bash scripts/deploy-coach-message.sh
```
Expected: deployment log shows `coach_message` deployed successfully.

- [ ] **Step 2: Remote smoke test**

```bash
curl -s -X POST https://<your-project-ref>.supabase.co/functions/v1/coach_message \
  -H "Authorization: Bearer <valid-user-jwt>" \
  -H "apikey: <your-anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "intent": "run_debrief",
    "context": {
      "runDistanceKm": 7.1,
      "runDurationSeconds": 2400,
      "averagePaceMinPerKm": 5.6,
      "workoutType": "easy",
      "recentLoadDays": 4
    }
  }' | jq .
```
Expected: JSON with `headline`, `debrief`, `tomorrow`, `source: "live_ai"`, no `error` key.

- [ ] **Step 3: Generic simulator build-for-testing**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-e6-derived \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all E6 tests**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRunDebriefRequestDTOEncodesIntent" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testRunDebriefResponseDTODecodes" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testPostRunDebriefModelFallbackHasContent" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testPostActivityOutcomeHasDebriefField" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testFetchRunDebriefReturnsFallbackWithoutAuth" \
  -derivedDataPath /tmp/runsmart-e6-derived \
  test
```
Expected: all 5 tests pass.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat(e6): E6 post-run debrief complete — deploy, tests pass"
```

---

## E6 Acceptance Checklist

- [ ] `run_debriefs` table created with RLS
- [ ] `run_debrief` intent live in deployed Edge Function
- [ ] Remote smoke test returns `source: "live_ai"`
- [ ] iOS build passes with no new warnings
- [ ] All 5 E6 tests pass
- [ ] Skeleton shows while `isProcessing == true` and debrief is nil
- [ ] AI debrief card renders headline + debrief + tomorrow + optional planImpact
- [ ] Deterministic content renders when debrief is nil and not loading
- [ ] Injury signal in context → rest recommendation, no shame copy
- [ ] Dark mode verified in simulator
