# E2 — Weekly Progress Narrative Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `WeeklyProgressCard` to the Today tab that shows an AI-generated coach narrative of the past week — what was built, one headline stat, and a forward look — generated once per week and cached. Card is suppressed while the 21-Day Rookie Challenge (`Beginner5KHabitCard`) is active.

**Architecture:** Extend `coach_message` Edge Function with a `weekly_summary` intent. iOS computes week boundary using `Calendar.current.firstWeekday` (locale-aware) and calls the endpoint on first app open of each new week. Result is cached in `UserDefaults` keyed by ISO week string. `WeeklyProgressCard` is a new SwiftUI card inserted into `TodayTabView` below `PlanExplanationCard`, shown only when a current-week summary exists and the beginner challenge is inactive.

**Prerequisite:** E6 (post-run debrief) must be live and deployed before building E2, so at least one full week of run data with debriefs exists to make the weekly narrative meaningful.

**Tech Stack:** Swift / SwiftUI, Supabase Edge Functions, Deno/TypeScript, OpenAI Responses API (`gpt-4.1-mini`), `UserDefaults` for weekly cache

**Spec:** `docs/superpowers/specs/2026-05-24-e2-e6-design.md` — Section 3

---

## File Map

| File | Change |
|------|--------|
| `supabase/functions/coach_message/index.ts` | Modify — add `weekly_summary` intent routing |
| `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift` | Modify — add `WeeklySummaryRequestDTO`, `WeeklySummaryResponseDTO` |
| `IOS RunSmart app/Models/RunSmartModels.swift` | Modify — add `WeeklyProgressSummary` model |
| `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` | Modify — add `generateWeeklySummary()` + week-boundary logic + UserDefaults cache |
| `IOS RunSmart app/Features/Today/WeeklyProgressCard.swift` | Create (new file) |
| `IOS RunSmart app/Features/Today/TodayTabView.swift` | Modify — wire `WeeklyProgressCard` into card stack |
| `IOS RunSmart appTests/RunSmartReadinessTests.swift` | Modify — add E2 test cases |

---

## Task 1: iOS model + DTOs

**Files:**
- Modify: `IOS RunSmart app/Models/RunSmartModels.swift`
- Modify: `IOS RunSmart app/Services/Live/RunSmartAPIModels.swift`
- Modify: `IOS RunSmart appTests/RunSmartReadinessTests.swift`

- [ ] **Step 1: Write failing model tests**

In `RunSmartReadinessTests.swift`, add:

```swift
func testWeeklyProgressSummaryFallbackHasHeadline() {
    let summary = WeeklyProgressSummary.fallback(runsCompleted: 3, totalDistanceKm: 15.4)
    XCTAssertFalse(summary.headline.isEmpty)
    XCTAssertEqual(summary.source, .fallback)
}

func testWeeklySummaryRequestDTOEncodesIntent() throws {
    let dto = RunSmartDTO.WeeklySummaryRequestDTO(
        weekStartDate: "2026-05-18",
        runsCompleted: 3,
        runsPlanned: 4,
        totalDistanceKm: 18.5,
        prevWeekDistanceKm: 15.2,
        planPhase: "build",
        isRecoveryWeek: false,
        readinessAverage: 72.0,
        limitations: []
    )
    let data = try JSONEncoder().encode(dto)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["intent"] as? String, "weekly_summary")
    XCTAssertEqual(json["runsCompleted"] as? Int, 3)
}

func testWeeklySummaryResponseDTODecodes() throws {
    let json = """
    {
      "headline": "3 runs · 18.5 km",
      "narrative": "A strong base week.",
      "forwardLook": "Next week's long run is where this pays off.",
      "weekLabel": "Week 3 of your plan",
      "source": "live_ai"
    }
    """
    let data = json.data(using: .utf8)!
    let dto = try JSONDecoder().decode(RunSmartDTO.WeeklySummaryResponseDTO.self, from: data)
    XCTAssertEqual(dto.headline, "3 runs · 18.5 km")
    XCTAssertEqual(dto.source, "live_ai")
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcrun swiftc -parse "IOS RunSmart appTests/RunSmartReadinessTests.swift"
```
Expected: compile errors for missing types.

- [ ] **Step 3: Add `WeeklyProgressSummary` to `RunSmartModels.swift`**

After the `PostRunDebriefModel` struct (added in E6), add:

```swift
struct WeeklyProgressSummary: Hashable, Codable {
    enum Source: String, Hashable, Codable {
        case ai
        case fallback
    }

    var headline: String
    var narrative: String
    var forwardLook: String
    var weekLabel: String
    var generatedDate: Date
    var isoWeekKey: String         // e.g. "2026-W21" — cache key
    var source: Source

    static func fallback(runsCompleted: Int, totalDistanceKm: Double) -> WeeklyProgressSummary {
        let distanceStr = String(format: "%.1f km", totalDistanceKm)
        let runWord = runsCompleted == 1 ? "run" : "runs"
        return WeeklyProgressSummary(
            headline: "\(runsCompleted) \(runWord) · \(distanceStr)",
            narrative: "A solid week of training. RunSmart has logged your effort.",
            forwardLook: "Check Today for your next recommended session.",
            weekLabel: "This week",
            generatedDate: Date(),
            isoWeekKey: WeeklyProgressSummary.currentISOWeekKey(),
            source: .fallback
        )
    }

    static func currentISOWeekKey() -> String {
        let cal = Calendar.current
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let year = components.yearForWeekOfYear ?? 2026
        let week = components.weekOfYear ?? 1
        return String(format: "%04d-W%02d", year, week)
    }

    static func isNewWeek(since lastKey: String) -> Bool {
        currentISOWeekKey() != lastKey
    }
}
```

- [ ] **Step 4: Add DTOs to `RunSmartAPIModels.swift`**

Inside `enum RunSmartDTO { }`, after `RunDebriefResponseDTO`, add:

```swift
struct WeeklySummaryRequestDTO: Encodable {
    let intent: String = "weekly_summary"
    let weekStartDate: String           // ISO date of first day of the week
    let runsCompleted: Int
    let runsPlanned: Int
    let totalDistanceKm: Double
    let prevWeekDistanceKm: Double?
    let planPhase: String?              // "build" / "peak" / "taper" / "base"
    let isRecoveryWeek: Bool
    let readinessAverage: Double?       // 0-100 if available
    let limitations: [String]
}

struct WeeklySummaryResponseDTO: Decodable {
    let headline: String
    let narrative: String
    let forwardLook: String
    let weekLabel: String
    let source: String
}
```

- [ ] **Step 5: Swift parse check**

```bash
xcrun swiftc -parse \
  "IOS RunSmart app/Models/RunSmartModels.swift" \
  "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift"
```
Expected: no errors.

- [ ] **Step 6: Run the model/DTO tests**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryFallbackHasHeadline" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklySummaryRequestDTOEncodesIntent" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklySummaryResponseDTODecodes" \
  -derivedDataPath /tmp/runsmart-e2-derived \
  test
```
Expected: 3 tests pass.

- [ ] **Step 7: Commit**

```bash
git add "IOS RunSmart app/Models/RunSmartModels.swift" \
        "IOS RunSmart app/Services/Live/RunSmartAPIModels.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(e2): add WeeklyProgressSummary model and WeeklySummary DTOs"
```

---

## Task 2: Backend — `weekly_summary` intent in `coach_message`

**Files:**
- Modify: `supabase/functions/coach_message/index.ts`

- [ ] **Step 1: Add the `weekly_summary` system prompt constant**

After `RUN_DEBRIEF_SYSTEM_PROMPT` (added in E6), add:

```typescript
const WEEKLY_SUMMARY_SYSTEM_PROMPT = `You are RunSmart Coach. Given a runner's week summary data, write a short weekly progress narrative.

Return ONLY valid JSON — no markdown, no explanation — in exactly this shape:
{
  "headline": "Key stat that proves something changed (max 50 characters, e.g. '3 runs · 18 km · 4th week in a row')",
  "narrative": "2-3 sentences in coach voice: what was built this week, what the data shows, why it matters",
  "forwardLook": "One sentence: what next week is building toward",
  "weekLabel": "Context label, e.g. 'Week 4 of your plan' or 'Week 3 with RunSmart'"
}

Rules:
- Be specific: reference actual numbers (runs, distance, comparison to last week if available).
- Be warm, direct, forward-looking.
- Do not shame missed workouts: if runsCompleted < runsPlanned, acknowledge effort without guilt.
- Do not diagnose or give medical advice.
- If runsCompleted is 0, return a short encouraging message anyway.
- Conservative under uncertainty.`;
```

- [ ] **Step 2: Add `generateWeeklySummary` function**

Before `Deno.serve`, add:

```typescript
async function generateWeeklySummary(context: JsonRecord): Promise<{
  headline: string;
  narrative: string;
  forwardLook: string;
  weekLabel: string;
  source: CoachSource;
}> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL") || "gpt-4.1-mini";
  if (!apiKey) {
    return fallbackWeeklySummary(context);
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
        instructions: WEEKLY_SUMMARY_SYSTEM_PROMPT,
        input: [{
          role: "user",
          content: [{ type: "input_text", text: `Week data:\n${JSON.stringify(context)}` }],
        }],
        max_output_tokens: 220,
      }),
    });
    if (!response.ok) throw new Error(`OpenAI ${response.status}`);
    const json = await response.json();
    const text = extractResponseText(json).trim();
    const parsed = JSON.parse(text);
    return {
      headline: limitString(parsed.headline, 50),
      narrative: limitString(parsed.narrative, 400),
      forwardLook: limitString(parsed.forwardLook, 160),
      weekLabel: limitString(parsed.weekLabel, 60),
      source: "live_ai",
    };
  } catch (error) {
    console.error("weekly_summary AI fallback", error);
    return fallbackWeeklySummary(context);
  } finally {
    clearTimeout(timeout);
  }
}

function fallbackWeeklySummary(context: JsonRecord): {
  headline: string; narrative: string; forwardLook: string; weekLabel: string; source: CoachSource;
} {
  const runs = typeof context.runsCompleted === "number" ? context.runsCompleted : 0;
  const distanceKm = typeof context.totalDistanceKm === "number"
    ? (context.totalDistanceKm as number).toFixed(1)
    : "–";
  const runWord = runs === 1 ? "run" : "runs";
  return {
    headline: `${runs} ${runWord} · ${distanceKm} km`,
    narrative: "A solid week of training. RunSmart has logged your effort.",
    forwardLook: "Check Today for your next recommended session.",
    weekLabel: "This week",
    source: "fallback",
  };
}
```

- [ ] **Step 3: Add `weekly_summary` routing to `Deno.serve`**

In the intent routing block (inside `Deno.serve`, after the `run_debrief` block added in E6), add:

```typescript
if (intent === "weekly_summary") {
  if (!context) {
    return jsonResponse({ error: "Context is required" }, 400);
  }
  const safeContext = {
    weekStartDate: limitString(context.weekStartDate, 20),
    runsCompleted: typeof context.runsCompleted === "number" ? context.runsCompleted : 0,
    runsPlanned: typeof context.runsPlanned === "number" ? context.runsPlanned : 0,
    totalDistanceKm: typeof context.totalDistanceKm === "number" ? context.totalDistanceKm : 0,
    prevWeekDistanceKm: typeof context.prevWeekDistanceKm === "number" ? context.prevWeekDistanceKm : null,
    planPhase: context.planPhase ? limitString(context.planPhase, 40) : null,
    isRecoveryWeek: Boolean(context.isRecoveryWeek),
    readinessAverage: typeof context.readinessAverage === "number" ? context.readinessAverage : null,
  };
  const summary = await generateWeeklySummary(safeContext);
  return jsonResponse(summary);
}
```

- [ ] **Step 4: Deno type-check**

```bash
npx -y deno check supabase/functions/coach_message/index.ts
```
Expected: no errors.

- [ ] **Step 5: Local smoke test**

```bash
supabase functions serve coach_message --env-file supabase/.env.local
```

```bash
curl -s -X POST http://localhost:54321/functions/v1/coach_message \
  -H "Authorization: Bearer <local-anon-jwt>" \
  -H "Content-Type: application/json" \
  -d '{
    "intent": "weekly_summary",
    "context": {
      "weekStartDate": "2026-05-18",
      "runsCompleted": 3,
      "runsPlanned": 4,
      "totalDistanceKm": 18.5,
      "prevWeekDistanceKm": 15.2,
      "planPhase": "build",
      "isRecoveryWeek": false
    }
  }' | jq .
```
Expected: JSON with `headline`, `narrative`, `forwardLook`, `weekLabel`, `source`. No `error` key.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/coach_message/index.ts
git commit -m "feat(e2): add weekly_summary intent to coach_message edge function"
```

---

## Task 3: iOS service — `generateWeeklySummary` + caching

**Files:**
- Modify: `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift`

- [ ] **Step 1: Write failing service tests**

In `RunSmartReadinessTests.swift`, add:

```swift
func testWeeklyProgressSummaryISOWeekKeyIsStable() {
    let key1 = WeeklyProgressSummary.currentISOWeekKey()
    let key2 = WeeklyProgressSummary.currentISOWeekKey()
    XCTAssertEqual(key1, key2)
    // Key should be non-empty and match pattern YYYY-Www
    XCTAssertTrue(key1.contains("-W"), "Expected ISO week format, got \(key1)")
}

func testWeeklyProgressSummaryIsNewWeekDetection() {
    let oldKey = "2020-W01"
    XCTAssertTrue(WeeklyProgressSummary.isNewWeek(since: oldKey))
    let currentKey = WeeklyProgressSummary.currentISOWeekKey()
    XCTAssertFalse(WeeklyProgressSummary.isNewWeek(since: currentKey))
}

func testWeeklyProgressSummaryCacheRoundTrip() throws {
    let summary = WeeklyProgressSummary(
        headline: "3 runs · 15 km",
        narrative: "Good week.",
        forwardLook: "Next week builds on this.",
        weekLabel: "Week 2 of your plan",
        generatedDate: Date(),
        isoWeekKey: WeeklyProgressSummary.currentISOWeekKey(),
        source: .fallback
    )
    let data = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(WeeklyProgressSummary.self, from: data)
    XCTAssertEqual(decoded.headline, summary.headline)
    XCTAssertEqual(decoded.isoWeekKey, summary.isoWeekKey)
}
```

- [ ] **Step 2: Run tests — verify they pass (model is already defined)**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryISOWeekKeyIsStable" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryIsNewWeekDetection" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryCacheRoundTrip" \
  -derivedDataPath /tmp/runsmart-e2-derived \
  test
```
Expected: all 3 pass (model is already defined from Task 1).

- [ ] **Step 3: Add `generateWeeklySummary` to `SupabaseRunSmartServices`**

Add this method. Place it near the other AI-generation methods (e.g., after `fetchRunDebrief`):

```swift
func generateWeeklySummary() async -> WeeklyProgressSummary? {
    let currentKey = WeeklyProgressSummary.currentISOWeekKey()
    let cacheKey = "runsmart.weekly_summary.\(currentKey)"

    // Return cached summary if it exists for this week
    if let cached = UserDefaults.standard.data(forKey: cacheKey),
       let summary = try? JSONDecoder().decode(WeeklyProgressSummary.self, from: cached) {
        return summary
    }

    // Gather week stats from local store
    let cal = Calendar.current
    let weekStart = cal.date(from: cal.dateComponents(
        [.yearForWeekOfYear, .weekOfYear],
        from: Date()
    )) ?? Date()
    let allRuns = store.loadRuns()
    let weekRuns = allRuns.filter { $0.startedAt >= weekStart }

    // Guard: no card if zero runs this week
    guard !weekRuns.isEmpty else { return nil }

    let totalDistanceKm = weekRuns.reduce(0.0) { $0 + $1.distanceMeters / 1_000.0 }

    // Previous week distance for step-up context
    let prevWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
    let prevWeekRuns = allRuns.filter { $0.startedAt >= prevWeekStart && $0.startedAt < weekStart }
    let prevDistanceKm = prevWeekRuns.isEmpty ? nil :
        prevWeekRuns.reduce(0.0) { $0 + $1.distanceMeters / 1_000.0 }

    // Fetch from AI
    guard let token = try? await supabase.auth.session.accessToken else {
        let fallback = WeeklyProgressSummary.fallback(
            runsCompleted: weekRuns.count,
            totalDistanceKm: totalDistanceKm
        )
        cacheSummary(fallback, forKey: cacheKey)
        return fallback
    }

    let weekStartISO = ISO8601DateFormatter.shortDate.string(from: weekStart)
    let request = RunSmartDTO.WeeklySummaryRequestDTO(
        weekStartDate: weekStartISO,
        runsCompleted: weekRuns.count,
        runsPlanned: 0,          // placeholder: wire to plan data when available
        totalDistanceKm: totalDistanceKm,
        prevWeekDistanceKm: prevDistanceKm,
        planPhase: nil,
        isRecoveryWeek: false,
        readinessAverage: nil,
        limitations: []
    )
    guard let body = try? JSONEncoder().encode(request) else {
        return nil
    }
    let client = URLSessionRunSmartAPIClient(
        baseURL: SupabaseManager.functionsBaseURL,
        accessToken: token,
        additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
    )
    do {
        let response = try await withThrowingTaskGroup(of: RunSmartDTO.WeeklySummaryResponseDTO.self) { group in
            group.addTask {
                try await client.send(
                    RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
                    as: RunSmartDTO.WeeklySummaryResponseDTO.self
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw CancellationError()
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
        let summary = WeeklyProgressSummary(
            headline: response.headline,
            narrative: response.narrative,
            forwardLook: response.forwardLook,
            weekLabel: response.weekLabel,
            generatedDate: Date(),
            isoWeekKey: currentKey,
            source: .ai
        )
        cacheSummary(summary, forKey: cacheKey)
        return summary
    } catch {
        if !(error is CancellationError) {
            print("[SupabaseServices] weekly_summary fallback:", error)
        }
        let fallback = WeeklyProgressSummary.fallback(
            runsCompleted: weekRuns.count,
            totalDistanceKm: totalDistanceKm
        )
        cacheSummary(fallback, forKey: cacheKey)
        return fallback
    }
}

private func cacheSummary(_ summary: WeeklyProgressSummary, forKey key: String) {
    if let data = try? JSONEncoder().encode(summary) {
        UserDefaults.standard.set(data, forKey: key)
    }
}
```

Note: `ISO8601DateFormatter.shortDate` is already an extension in this codebase (used in `TrainingContextSnapshotDTO`). If it's not accessible here, replace with:
```swift
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withFullDate]
let weekStartISO = formatter.string(from: weekStart)
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
  -derivedDataPath /tmp/runsmart-e2-derived \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add "IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(e2): add generateWeeklySummary with locale-aware week boundary and UserDefaults cache"
```

---

## Task 4: `WeeklyProgressCard` view

**Files:**
- Create: `IOS RunSmart app/Features/Today/WeeklyProgressCard.swift`

- [ ] **Step 1: Create the file**

```swift
// IOS RunSmart app/Features/Today/WeeklyProgressCard.swift
import SwiftUI

struct WeeklyProgressCard: View {
    let summary: WeeklyProgressSummary
    var onTapCoach: (() -> Void)? = nil

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Label("WEEK IN REVIEW", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    StatusChip(
                        text: summary.source == .ai ? "AI" : "Summary",
                        tint: summary.source == .ai ? .accentPrimary : .textSecondary
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.weekLabel)
                        .font(.labelSM)
                        .foregroundStyle(Color.textSecondary)
                    Text(summary.headline)
                        .font(.title3.bold())
                        .foregroundStyle(Color.textPrimary)
                }

                Text(summary.narrative)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Next week")
                        .font(.labelSM)
                        .foregroundStyle(Color.textSecondary)
                    Text(summary.forwardLook)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onTapCoach {
                    Button(action: onTapCoach) {
                        Label("Ask Coach", systemImage: "bubble.left")
                            .font(.buttonLabel)
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapCoach?() }
    }
}

#Preview {
    WeeklyProgressCard(
        summary: WeeklyProgressSummary(
            headline: "3 runs · 18.5 km",
            narrative: "You held easy pace across all three runs this week even as total distance stepped up 15%. Your aerobic base is absorbing the load.",
            forwardLook: "Next week's long run is where this base starts to pay off.",
            weekLabel: "Week 4 of your plan",
            generatedDate: Date(),
            isoWeekKey: "2026-W21",
            source: .ai
        ),
        onTapCoach: {}
    )
    .padding()
}
```

- [ ] **Step 2: Swift parse check**

```bash
xcrun swiftc -parse \
  "IOS RunSmart app/Features/Today/WeeklyProgressCard.swift" \
  "IOS RunSmart app/Models/RunSmartModels.swift"
```
Expected: no errors.

- [ ] **Step 3: Generic simulator build**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-e2-derived \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Verify preview renders in Xcode**

Open `WeeklyProgressCard.swift` in Xcode and confirm the preview canvas shows the card with headline, narrative, forward look, and "Ask Coach" button.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Features/Today/WeeklyProgressCard.swift"
git commit -m "feat(e2): add WeeklyProgressCard SwiftUI component"
```

---

## Task 5: Wire `WeeklyProgressCard` into `TodayTabView`

**Files:**
- Modify: `IOS RunSmart app/Features/Today/TodayTabView.swift`

The existing `TodayTabView` card stack order (from the code):
1. Today recommendation card
2. Safety explanation (E3)
3. Rationale / PlanExplanationCard (E1)  
4. `Beginner5KHabitCard` (if `Beginner5KHabitTrack.isBeginnerFirst5K`)
5. `TodayQuickActions`
6. `InsightCard`
7. Coach conversation preview

The `WeeklyProgressCard` inserts **after `PlanExplanationCard` and before `Beginner5KHabitCard`**, and is suppressed when the beginner challenge is active.

- [ ] **Step 1: Write a failing test for the suppression logic**

In `RunSmartReadinessTests.swift`, add:

```swift
func testWeeklyProgressCardSuppressedDuringBeginnerChallenge() {
    // isBeginnerFirst5K == true → card must NOT show
    // This tests the gate condition used in TodayTabView
    let beginnerProfile = OnboardingProfile.makeStub(goal: "first5k")
    let isChallenge = Beginner5KHabitTrack.isBeginnerFirst5K(profile: beginnerProfile)
    // If isChallenge, card should be hidden
    // (Verified in view logic — this test validates the gate condition compiles and returns true)
    XCTAssertTrue(isChallenge)
}
```

Note: `OnboardingProfile.makeStub` — use whatever stub or mock pattern exists in the test file. If `OnboardingProfile` has a default init, create one with a first-5K goal.

- [ ] **Step 2: Add `@State var weeklySummary: WeeklyProgressSummary?` to `TodayTabView`**

In `TodayTabView.swift`, add a state property alongside the other `@State` properties:

```swift
@State private var weeklySummary: WeeklyProgressSummary? = nil
```

- [ ] **Step 3: Insert `WeeklyProgressCard` into the card stack**

Find the block that contains `Beginner5KHabitCard` (around line 84):

```swift
// BEFORE (existing):
if Beginner5KHabitTrack.isBeginnerFirst5K(profile: session.onboardingProfile) {
    Beginner5KHabitCard(track: habitTrack)
        .runSmartStaggeredAppear(index: 5)
}
```

Replace with:

```swift
// E2: weekly progress card — suppressed during 21-Day Rookie Challenge
let isBeginnerChallenge = Beginner5KHabitTrack.isBeginnerFirst5K(profile: session.onboardingProfile)
if isBeginnerChallenge {
    Beginner5KHabitCard(track: habitTrack)
        .runSmartStaggeredAppear(index: 5)
} else if let summary = weeklySummary {
    WeeklyProgressCard(
        summary: summary,
        onTapCoach: openTodayCoach
    )
    .runSmartStaggeredAppear(index: 5)
}
```

Note: `openTodayCoach` is already defined in `TodayTabView` (it's what the InsightCard uses). If the exact name differs, search for `openTodayCoach` or the Coach sheet opener and use that reference.

- [ ] **Step 4: Add `.task` to load the weekly summary**

Find the `.task` or `.onAppear` modifier on `TodayTabView`'s root view, and add weekly summary loading alongside existing data loads:

```swift
// Inside the existing .task { } modifier (or add a new .task):
if weeklySummary == nil {
    weeklySummary = await services.generateWeeklySummary()
}
```

If `generateWeeklySummary` is not yet on the `RunSmartServiceProviding` protocol, add it as an extension or call it via the concrete Supabase service. The simplest approach for V1.2: cast and call directly, or add the method to the protocol. To keep scope small, call it on the services object if the protocol doesn't need updating.

- [ ] **Step 5: Swift parse check**

```bash
xcrun swiftc -parse "IOS RunSmart app/Features/Today/TodayTabView.swift"
```
Expected: no errors.

- [ ] **Step 6: Generic simulator build**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/runsmart-e2-derived \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Manual simulator verification**

Install on iPhone 17 Pro simulator. Verify:
- For a user with at least 1 run in the current week: `WeeklyProgressCard` appears between `PlanExplanationCard` and `TodayQuickActions`
- For a user with zero runs this week: `WeeklyProgressCard` does not appear
- For a user who is a beginner (first5K goal): `Beginner5KHabitCard` shows; `WeeklyProgressCard` does not
- Tapping the card (or "Ask Coach") opens the Coach sheet
- Dark mode: card text is legible
- Dynamic Type (Accessibility Inspector, largest size): text wraps without truncation

- [ ] **Step 8: Commit**

```bash
git add "IOS RunSmart app/Features/Today/TodayTabView.swift" \
        "IOS RunSmart appTests/RunSmartReadinessTests.swift"
git commit -m "feat(e2): wire WeeklyProgressCard into TodayTabView with beginner-challenge suppression"
```

---

## Task 6: Deploy + end-to-end validation

**Files:** no new files; validates everything together.

- [ ] **Step 1: Deploy updated Edge Function**

```bash
bash scripts/deploy-coach-message.sh
```
Expected: deployment log shows `coach_message` deployed successfully with the new `weekly_summary` intent.

- [ ] **Step 2: Remote smoke test**

```bash
curl -s -X POST https://<your-project-ref>.supabase.co/functions/v1/coach_message \
  -H "Authorization: Bearer <valid-user-jwt>" \
  -H "apikey: <your-anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "intent": "weekly_summary",
    "context": {
      "weekStartDate": "2026-05-18",
      "runsCompleted": 3,
      "runsPlanned": 4,
      "totalDistanceKm": 18.5,
      "prevWeekDistanceKm": 15.2,
      "planPhase": "build",
      "isRecoveryWeek": false,
      "readinessAverage": 74
    }
  }' | jq .
```
Expected: JSON with `headline`, `narrative`, `forwardLook`, `weekLabel`, `source: "live_ai"`.

- [ ] **Step 3: Verify existing `chat` intent still works**

```bash
curl -s -X POST https://<your-project-ref>.supabase.co/functions/v1/coach_message \
  -H "Authorization: Bearer <valid-user-jwt>" \
  -H "apikey: <your-anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "How am I doing this week?",
    "clientMessageId": "test-regression-001",
    "entryPoint": "today",
    "context": {
      "generatedAt": "2026-05-24T10:00:00Z",
      "entryPoint": "today",
      "runner": { "goal": "5k", "level": "beginner", "streak": "3 days", "totalRuns": 12, "totalDistanceKm": 45, "totalTime": "6h" },
      "today": { "readiness": 72, "readinessLabel": "Good", "workoutTitle": "Easy Run", "distance": "5 km", "pace": "6:00/km", "coachMessage": "Ready to run", "weeklyProgress": "3 of 4", "recovery": "Good", "hrv": "Normal" },
      "plan": { "activePlanTitle": "5K Plan", "planType": "beginner", "totalWeeks": 8, "weeklyWorkoutCount": 4, "upcomingWorkouts": [] },
      "recovery": { "readiness": 72, "bodyBattery": 80, "sleep": "7h", "hrv": "Normal", "stress": "Low", "recommendation": "Go" },
      "wellness": { "soreness": "None", "mood": "Good", "hydration": "Good", "checkInStatus": "Done" },
      "activity": { "recentRunCount": 3, "recentRuns": [], "sources": ["RunSmart"], "averageWeeklyDistanceKm": 18.5 },
      "routes": [],
      "reports": [],
      "limitations": []
    }
  }' | jq .assistantMessage.content
```
Expected: a coach response string (not null, not an error).

- [ ] **Step 4: Run all E2 tests**

```bash
xcodebuild -project "IOS RunSmart app.xcodeproj" \
  -scheme "IOS RunSmart app" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryFallbackHasHeadline" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklySummaryRequestDTOEncodesIntent" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklySummaryResponseDTODecodes" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryISOWeekKeyIsStable" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryIsNewWeekDetection" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressSummaryCacheRoundTrip" \
  -only-testing:"IOS RunSmart appTests/RunSmartReadinessTests/testWeeklyProgressCardSuppressedDuringBeginnerChallenge" \
  -derivedDataPath /tmp/runsmart-e2-derived \
  test
```
Expected: all 7 tests pass.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat(e2): E2 weekly progress narrative complete — deploy, all 7 tests pass"
```

---

## E2 Acceptance Checklist

- [ ] `weekly_summary` intent live in deployed Edge Function
- [ ] Regression: existing `chat` intent still returns correct response
- [ ] Remote smoke test returns `source: "live_ai"` for weekly_summary
- [ ] iOS build passes with no new warnings
- [ ] All 7 E2 tests pass
- [ ] `WeeklyProgressCard` appears on Today when ≥1 run exists this week
- [ ] Card absent when zero runs this week
- [ ] Card suppressed when `Beginner5KHabitTrack.isBeginnerFirst5K` is true; `Beginner5KHabitCard` shows instead
- [ ] Tapping card opens Coach sheet
- [ ] Week boundary uses `Calendar.current.firstWeekday` (locale-aware)
- [ ] Cache returns same summary on repeated calls within same week
- [ ] Deterministic fallback renders on AI failure — no error state
- [ ] Dark mode and Dynamic Type verified in simulator
