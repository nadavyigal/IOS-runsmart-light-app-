export type FlexWeekReasonKind = "tired" | "traveling" | "missed_workout" | "sick";

export type FlexWeekWorkoutDTO = {
  workout_id: string;
  scheduled_date: string;
  weekday: string;
  date_label: string;
  kind: string;
  title: string;
  distance_label: string;
  detail_label: string;
  intensity?: string | null;
  training_phase?: string | null;
  is_today: boolean;
  is_complete: boolean;
  original_workout_id?: string | null;
};

export type FlexWeekChangeDTO = {
  workout_id: string;
  change_type: "moved" | "downgraded" | "rest" | "dropped" | "added";
  rationale: string;
  original_workout_id?: string | null;
};

export type FlexWeekReadinessContextDTO = {
  readiness?: number | null;
  readiness_label?: string | null;
  body_battery?: number | null;
  hrv?: string | null;
  sleep?: string | null;
  recommendation?: string | null;
};

export type FlexWeekRequestPayload = {
  reason: FlexWeekReasonKind;
  current_week: FlexWeekWorkoutDTO[];
  readiness_context?: FlexWeekReadinessContextDTO | null;
  blocked_days?: string[] | null;
  missed_workout_id?: string | null;
  sick_days_out?: number | null;
};

export type FlexWeekResponsePayload = {
  restructured_week: FlexWeekWorkoutDTO[];
  changes: FlexWeekChangeDTO[];
  safety_warnings: string[];
  source: "live_ai" | "fallback";
};

const HARD_KINDS = new Set(["Tempo Run", "Intervals", "Hills", "Long Run", "Race", "tempo", "intervals", "hills", "long", "race"]);
const MAX_CHANGES = 6;

export function sanitizeFlexWeekRequest(body: Record<string, unknown>): FlexWeekRequestPayload | null {
  const reason = stringValue(body.reason).trim() as FlexWeekReasonKind;
  if (!["tired", "traveling", "missed_workout", "sick"].includes(reason)) {
    return null;
  }

  const currentWeek = sanitizeWorkoutList(body.currentWeek ?? body.current_week);
  if (currentWeek.length === 0) {
    return null;
  }

  const readinessRaw = asRecord(body.readinessContext ?? body.readiness_context);
  const readinessContext = readinessRaw
    ? {
        readiness: numberValue(readinessRaw.readiness),
        readiness_label: limitString(readinessRaw.readinessLabel ?? readinessRaw.readiness_label, 40) || null,
        body_battery: numberValue(readinessRaw.bodyBattery ?? readinessRaw.body_battery),
        hrv: limitString(readinessRaw.hrv, 40) || null,
        sleep: limitString(readinessRaw.sleep, 40) || null,
        recommendation: limitString(readinessRaw.recommendation, 160) || null,
      }
    : null;

  const blockedDays = stringArray(body.blockedDays ?? body.blocked_days, 7);
  const missedWorkoutId = optionalUUID(body.missedWorkoutId ?? body.missed_workout_id);
  const sickDaysOut = clampInt(numberValue(body.sickDaysOut ?? body.sick_days_out), 3, 7);

  if (reason === "traveling" && blockedDays.length === 0) {
    return null;
  }
  if (reason === "missed_workout" && !missedWorkoutId) {
    return null;
  }

  return {
    reason,
    current_week: currentWeek,
    readiness_context: readinessContext,
    blocked_days: reason === "traveling" ? blockedDays : null,
    missed_workout_id: reason === "missed_workout" ? missedWorkoutId : null,
    sick_days_out: reason === "sick" ? (sickDaysOut ?? 4) : null,
  };
}

export function validateFlexWeekResponse(
  parsed: unknown,
  originalWeek: FlexWeekWorkoutDTO[],
): FlexWeekResponsePayload | null {
  const record = asRecord(parsed);
  if (!record) return null;

  const restructuredWeek = sanitizeWorkoutList(record.restructuredWeek ?? record.restructured_week);
  const changesRaw = Array.isArray(record.changes) ? record.changes : [];
  const changes: FlexWeekChangeDTO[] = [];

  for (const item of changesRaw.slice(0, MAX_CHANGES)) {
    const change = asRecord(item);
    if (!change) continue;
    const workoutID = optionalUUID(change.workoutId ?? change.workout_id);
    const changeType = stringValue(change.changeType ?? change.change_type).trim() as FlexWeekChangeDTO["change_type"];
    const rationale = limitString(change.rationale, 240);
    if (!workoutID || !rationale) continue;
    if (!["moved", "downgraded", "rest", "dropped", "added"].includes(changeType)) continue;
    changes.push({
      workout_id: workoutID,
      change_type: changeType,
      rationale,
      original_workout_id: optionalUUID(change.originalWorkoutId ?? change.original_workout_id),
    });
  }

  if (restructuredWeek.length !== originalWeek.length || changes.length === 0) {
    return null;
  }

  const safetyWarnings = stringArray(record.safetyWarnings ?? record.safety_warnings, 5);
  const sourceRaw = stringValue(record.source);
  const source: "live_ai" | "fallback" = sourceRaw === "live_ai" ? "live_ai" : "fallback";

  if (violatesSafetyRules(originalWeek, restructuredWeek, changes)) {
    return null;
  }

  return {
    restructured_week: restructuredWeek,
    changes,
    safety_warnings: safetyWarnings,
    source,
  };
}

export function fallbackFlexWeek(request: FlexWeekRequestPayload): FlexWeekResponsePayload {
  const sortedWeek = [...request.current_week].sort((a, b) => a.scheduled_date.localeCompare(b.scheduled_date));

  if (isTaperWeek(sortedWeek)) {
    return {
      restructured_week: sortedWeek,
      changes: [{
        workout_id: sortedWeek[0].workout_id,
        change_type: "rest",
        rationale: "Taper week — locking the schedule.",
      }],
      safety_warnings: ["Taper week detected — schedule left unchanged."],
      source: "fallback",
    };
  }

  const week = sortedWeek.map(cloneWorkout);
  const changes: FlexWeekChangeDTO[] = [];

  switch (request.reason) {
    case "tired":
      applyTiredRule(week, changes);
      break;
    case "traveling":
      applyTravelingRule(week, changes, request.blocked_days ?? []);
      break;
    case "missed_workout":
      applyMissedWorkoutRule(week, changes, request.missed_workout_id ?? "");
      break;
    case "sick":
      applySickRule(week, changes, request.sick_days_out ?? 4);
      break;
  }

  if (changes.length === 0) {
    const target = week.find((w) => !isRestDay(w)) ?? week[0];
    changes.push({
      workout_id: target.workout_id,
      change_type: "downgraded",
      rationale: `RECOVERY — applied a conservative ${request.reason.replace("_", " ")} adjustment for the rest of the week.`,
    });
  }

  return {
    restructured_week: week,
    changes: changes.slice(0, MAX_CHANGES),
    safety_warnings: ["Coach is taking a careful path — here's a safe adjustment based on standard recovery rules."],
    source: "fallback",
  };
}

export async function generateFlexWeek(
  request: FlexWeekRequestPayload,
  fetchImpl: typeof fetch = fetch,
): Promise<FlexWeekResponsePayload> {
  if (isTaperWeek(request.current_week)) {
    return fallbackFlexWeek(request);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL") || "gpt-4.1-mini";
  if (!apiKey) {
    return fallbackFlexWeek(request);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4_000);
  try {
    const response = await fetchImpl("https://api.openai.com/v1/responses", {
      method: "POST",
      signal: controller.signal,
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        instructions: FLEX_WEEK_SYSTEM_PROMPT,
        input: [{
          role: "user",
          content: [{ type: "input_text", text: `Flex week request:\n${JSON.stringify(request)}` }],
        }],
        max_output_tokens: 900,
      }),
    });
    if (!response.ok) throw new Error(`OpenAI ${response.status}`);
    const json = await response.json();
    const text = extractResponseText(json).trim();
    if (!text) throw new Error("flex_week: OpenAI returned empty text");
    const parsed = JSON.parse(text);
    const validated = validateFlexWeekResponse(parsed, request.current_week);
    if (!validated) throw new Error("flex_week: AI response failed validation");
    return { ...validated, source: "live_ai" };
  } catch (error) {
    console.error("flex_week AI fallback", error);
    return fallbackFlexWeek(request);
  } finally {
    clearTimeout(timeout);
  }
}

const FLEX_WEEK_SYSTEM_PROMPT = `You are RunSmart Coach. Restructure the runner's current ISO week based on their life disruption.

Return ONLY valid JSON — no markdown — in exactly this shape:
{
  "restructured_week": [ /* same array length and workout_id values as current_week; update fields in place */ ],
  "changes": [
    { "workout_id": "uuid", "change_type": "moved|downgraded|rest|dropped|added", "rationale": "one sentence", "original_workout_id": "uuid or null" }
  ],
  "safety_warnings": ["optional strings"],
  "source": "live_ai"
}

Safety rules (mandatory):
- Never remove or drop a Long Run session; downgrade or move it instead.
- If any workout has training_phase containing "taper", return the original week unchanged with one change rationale "Taper week — locking the schedule."
- Weekly mileage must not increase more than 10% versus the original week.
- Never create back-to-back hard sessions (tempo, intervals, hills, long, race).
- Limit to at most 6 changes.
- Never replace rest with a hard effort.
- For sick: no hard sessions within 48 hours after the last sick-rest day.
- Always include at least one change with a plain-language rationale per changed workout.
- Do not diagnose illness or injury; stay conservative.`;

function applyTiredRule(week: FlexWeekWorkoutDTO[], changes: FlexWeekChangeDTO[]) {
  const todayIndex = week.findIndex((w) => w.is_today);
  const targetIndex = todayIndex >= 0 && isHardWorkout(week[todayIndex]) && !isRestDay(week[todayIndex])
    ? todayIndex
    : week.findIndex((w, idx) => idx > (todayIndex >= 0 ? todayIndex : -1) && isHardWorkout(w) && !isRestDay(w));

  if (targetIndex < 0) return;
  const workout = week[targetIndex];
  week[targetIndex] = downgradedEasy(workout);
  changes.push({
    workout_id: workout.workout_id,
    change_type: "downgraded",
    rationale: "RECOVERY — downgraded the next hard session while you recharge.",
  });
}

function applyTravelingRule(week: FlexWeekWorkoutDTO[], changes: FlexWeekChangeDTO[], blockedDays: string[]) {
  const blocked = new Set(blockedDays);
  const originalMileage = weeklyMileage(week);
  const displaced: { index: number; workout: FlexWeekWorkoutDTO }[] = [];

  week.forEach((workout, index) => {
    if (!blocked.has(workout.scheduled_date) || isRestDay(workout)) return;
    displaced.push({ index, workout });
    week[index] = restDay(workout);
    changes.push({
      workout_id: workout.workout_id,
      change_type: "rest",
      rationale: `Marked ${workout.weekday} as rest while you're traveling.`,
    });
  });

  const candidate = displaced.find(({ workout }) => isHardWorkout(workout) || !isEasyWorkout(workout));
  if (!candidate) return;

  const maxMileage = originalMileage * 1.10;
  for (let index = 0; index < week.length; index++) {
    const workout = week[index];
    if (blocked.has(workout.scheduled_date) || !(isRestDay(workout) || isEasyWorkout(workout))) continue;
    if (wouldCreateBackToBackHard(week, candidate.workout, index)) continue;

    const moved = { ...candidate.workout, scheduled_date: workout.scheduled_date, weekday: workout.weekday, date_label: workout.date_label };
    week[index] = moved;
    if (weeklyMileage(week) <= maxMileage + 0.01) {
      changes.push({
        workout_id: moved.workout_id,
        change_type: "moved",
        rationale: `Shifted ${candidate.workout.title} to ${workout.weekday} to protect weekly mileage.`,
        original_workout_id: candidate.workout.workout_id,
      });
      return;
    }
    week[index] = restDay(workout);
  }
}

function applyMissedWorkoutRule(week: FlexWeekWorkoutDTO[], changes: FlexWeekChangeDTO[], missedWorkoutId: string) {
  const missedIndex = week.findIndex((w) => w.workout_id === missedWorkoutId);
  if (missedIndex < 0) return;
  const missed = week[missedIndex];

  if (isEasyWorkout(missed) || isRestDay(missed)) {
    week[missedIndex] = restDay(missed);
    changes.push({
      workout_id: missed.workout_id,
      change_type: "dropped",
      rationale: "Dropped the missed easy session so you don't cram extra volume into the week.",
    });
    return;
  }

  const tomorrowIndex = missedIndex + 1 < week.length ? missedIndex + 1 : -1;
  if (tomorrowIndex < 0 || isHardWorkout(week[tomorrowIndex])) {
    week[missedIndex] = restDay(missed);
    changes.push({
      workout_id: missed.workout_id,
      change_type: "rest",
      rationale: "Left the missed workout as rest to avoid stacking two hard days back-to-back.",
    });
    return;
  }

  const tomorrow = week[tomorrowIndex];
  week[missedIndex] = restDay(missed);
  week[tomorrowIndex] = {
    ...missed,
    scheduled_date: tomorrow.scheduled_date,
    weekday: tomorrow.weekday,
    date_label: tomorrow.date_label,
  };
  changes.push({
    workout_id: missed.workout_id,
    change_type: "rest",
    rationale: "Converted the missed day to rest.",
  });
  changes.push({
    workout_id: missed.workout_id,
    change_type: "moved",
    rationale: "Moved the missed session to the next open day because that slot was easy enough to absorb it safely.",
    original_workout_id: missed.workout_id,
  });
}

function applySickRule(week: FlexWeekWorkoutDTO[], changes: FlexWeekChangeDTO[], daysOut: number) {
  const recoveryDays = Math.max(3, Math.min(daysOut, 7));
  const startDate = week.find((w) => w.is_today)?.scheduled_date ?? week[0].scheduled_date;
  const sickEnd = addDays(startDate, recoveryDays - 1);

  week.forEach((workout, index) => {
    if (workout.scheduled_date < startDate || workout.scheduled_date > sickEnd || isRestDay(workout)) return;
    week[index] = restDay(workout);
    changes.push({
      workout_id: workout.workout_id,
      change_type: "rest",
      rationale: "Rest while you recover — illness recovery comes before training load.",
    });
  });

  const returnDay = addDays(sickEnd, 2);
  const returnIndex = week.findIndex((w) => w.scheduled_date >= returnDay && !isRestDay(w));
  if (returnIndex >= 0 && isHardWorkout(week[returnIndex])) {
    const workout = week[returnIndex];
    week[returnIndex] = downgradedEasy(workout, "Easy Return Run");
    changes.push({
      workout_id: workout.workout_id,
      change_type: "downgraded",
      rationale: "Your first run back is an easy session to test how you feel.",
    });
  }
}

function violatesSafetyRules(
  originalWeek: FlexWeekWorkoutDTO[],
  restructuredWeek: FlexWeekWorkoutDTO[],
  changes: FlexWeekChangeDTO[],
): boolean {
  if (restructuredWeek.length !== originalWeek.length) return true;
  if (changes.length === 0 || changes.length > MAX_CHANGES) return true;

  const originalIds = new Set(originalWeek.map((w) => w.workout_id));
  if (!restructuredWeek.every((w) => originalIds.has(w.workout_id))) return true;

  const originalLongCount = originalWeek.filter((w) => isLongRun(w)).length;
  const restructuredLongCount = restructuredWeek.filter((w) => isLongRun(w)).length;
  if (restructuredLongCount < originalLongCount) return true;

  if (weeklyMileage(restructuredWeek) > weeklyMileage(originalWeek) * 1.10 + 0.01) return true;
  if (hasBackToBackHard(restructuredWeek)) return true;

  return false;
}

function isTaperWeek(week: FlexWeekWorkoutDTO[]): boolean {
  return week.some((w) => (w.training_phase ?? "").toLowerCase().includes("taper"));
}

function isHardWorkout(workout: FlexWeekWorkoutDTO): boolean {
  const kind = workout.kind.toLowerCase();
  return HARD_KINDS.has(workout.kind) || ["tempo", "intervals", "hills", "long", "race"].some((v) => kind.includes(v));
}

function isEasyWorkout(workout: FlexWeekWorkoutDTO): boolean {
  const kind = workout.kind.toLowerCase();
  return kind.includes("easy") || kind.includes("recovery") || (workout.intensity ?? "").toLowerCase().includes("easy");
}

function isRestDay(workout: FlexWeekWorkoutDTO): boolean {
  return workout.distance_label.toLowerCase().includes("rest") ||
    (workout.kind.toLowerCase().includes("recovery") && workout.distance_label.toLowerCase().includes("rest"));
}

function isLongRun(workout: FlexWeekWorkoutDTO): boolean {
  return workout.kind.toLowerCase().includes("long") || workout.title.toLowerCase().includes("long run");
}

function weeklyMileage(week: FlexWeekWorkoutDTO[]): number {
  return week.reduce((total, workout) => total + distanceKm(workout.distance_label), 0);
}

function distanceKm(label: string): number {
  const match = label.match(/([\d.]+)/);
  return match ? Number(match[1]) : 0;
}

function downgradedEasy(workout: FlexWeekWorkoutDTO, title = "Easy Run"): FlexWeekWorkoutDTO {
  return {
    ...workout,
    kind: "Easy Run",
    title,
    intensity: "easy",
    distance_label: workout.distance_label.toLowerCase().includes("rest") ? "5.0 km" : workout.distance_label,
  };
}

function restDay(workout: FlexWeekWorkoutDTO): FlexWeekWorkoutDTO {
  return {
    ...workout,
    kind: "Recovery",
    title: "Rest",
    distance_label: "Rest",
    intensity: "rest",
    detail_label: "Recovery",
  };
}

function cloneWorkout(workout: FlexWeekWorkoutDTO): FlexWeekWorkoutDTO {
  return { ...workout };
}

function wouldCreateBackToBackHard(week: FlexWeekWorkoutDTO[], moving: FlexWeekWorkoutDTO, targetIndex: number): boolean {
  if (!isHardWorkout(moving)) return false;
  const neighbors = [targetIndex - 1, targetIndex + 1]
    .filter((idx) => idx >= 0 && idx < week.length)
    .map((idx) => week[idx]);
  return neighbors.some(isHardWorkout);
}

function hasBackToBackHard(week: FlexWeekWorkoutDTO[]): boolean {
  for (let index = 0; index < week.length - 1; index++) {
    if (isHardWorkout(week[index]) && isHardWorkout(week[index + 1])) return true;
  }
  return false;
}

function addDays(isoDate: string, days: number): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function sanitizeWorkoutList(value: unknown): FlexWeekWorkoutDTO[] {
  if (!Array.isArray(value)) return [];
  const workouts: FlexWeekWorkoutDTO[] = [];
  for (const item of value.slice(0, 7)) {
    const record = asRecord(item);
    if (!record) continue;
    const workoutID = optionalUUID(record.workoutId ?? record.workout_id ?? record.id);
    const scheduledDate = limitString(record.scheduledDate ?? record.scheduled_date, 20);
    if (!workoutID || !scheduledDate) continue;
    workouts.push({
      workout_id: workoutID,
      scheduled_date: scheduledDate,
      weekday: limitString(record.weekday, 8),
      date_label: limitString(record.dateLabel ?? record.date_label ?? record.date, 8),
      kind: limitString(record.kind, 40),
      title: limitString(record.title, 80),
      distance_label: limitString(record.distanceLabel ?? record.distance_label ?? record.distance, 40),
      detail_label: limitString(record.detailLabel ?? record.detail_label ?? record.detail, 120),
      intensity: limitString(record.intensity, 40) || null,
      training_phase: limitString(record.trainingPhase ?? record.training_phase, 40) || null,
      is_today: Boolean(record.isToday ?? record.is_today),
      is_complete: Boolean(record.isComplete ?? record.is_complete),
      original_workout_id: optionalUUID(record.originalWorkoutId ?? record.original_workout_id),
    });
  }
  return workouts;
}

function extractResponseText(json: Record<string, unknown>): string {
  if (typeof json.output_text === "string") return json.output_text;
  const output = Array.isArray(json.output) ? json.output : [];
  const parts: string[] = [];
  for (const item of output) {
    const record = asRecord(item);
    const content = Array.isArray(record?.content) ? record.content : [];
    for (const contentItem of content) {
      const contentRecord = asRecord(contentItem);
      if (typeof contentRecord?.text === "string") parts.push(contentRecord.text);
    }
  }
  return parts.join("\n").trim();
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function clampInt(value: number | null, min: number, max: number): number | null {
  if (value == null) return null;
  return Math.max(min, Math.min(max, Math.trunc(value)));
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function optionalUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null;
}

function stringArray(value: unknown, max: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => limitString(item, 20))
    .filter(Boolean)
    .slice(0, max);
}

function limitString(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, max);
}
