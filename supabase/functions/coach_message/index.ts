import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  generateFlexWeek,
  sanitizeFlexWeekRequest,
} from "./flex_week.ts";
import { corsHeaders, isOriginAllowed } from "../_shared/cors.ts";

type JsonRecord = Record<string, unknown>;

type CoachSource = "live_ai" | "fallback";
type SupabaseDbClient = ReturnType<typeof createClient<any, "public", any>>;
type ConversationRow = {
  id: string;
  profile_id: string | null;
  auth_user_id: string | null;
};
type MessageRow = {
  id: string;
  role: string;
  content: string;
  created_at: string;
};

const MAX_CHAT_MESSAGE_LENGTH = 2000;

const SYSTEM_PROMPT = `You are RunSmart Coach, a calm AI running coach for beginner and intermediate runners.

Your job is to turn the runner's current context into one clear next action.

Rules:
- Be concise: 3-6 sentences unless the user asks for detail.
- Use only the provided training context.
- If data is missing, say so honestly.
- Do not diagnose injuries or give medical advice.
- If the user mentions pain, dizziness, chest pain, fainting, or severe symptoms, advise stopping activity and consulting a qualified professional.
- Do not shame missed workouts.
- Prefer conservative training guidance under uncertainty.
- Do not claim you changed the training plan unless an action was actually applied.
- Do not expose raw GPS data or private route details.
- Use supportive language: adjust, recover, next best step, still on track.
- Give one practical next action.`;

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

const forbiddenContextKeys = new Set([
  "latitude",
  "longitude",
  "coordinates",
  "coordinate",
  "routepoints",
  "route_points",
  "polyline",
  "gps",
  "points",
]);

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
    return fallbackRunDebrief(context);
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
    if (!text) {
      throw new Error("run_debrief: OpenAI returned empty text");
    }
    const parsed = JSON.parse(text);
    const headline = limitString(parsed.headline, 40);
    const debrief = limitString(parsed.debrief, 300);
    const tomorrow = limitString(parsed.tomorrow, 160);
    if (!headline || !debrief || !tomorrow) {
      throw new Error("run_debrief: AI response missing required fields");
    }
    return {
      headline,
      debrief,
      tomorrow,
      planImpact: parsed.planImpact ? limitString(parsed.planImpact, 60) : null,
      source: "live_ai" as CoachSource,
    };
  } catch (error) {
    console.error("run_debrief AI fallback", error);
    return fallbackRunDebrief(context);
  } finally {
    clearTimeout(timeout);
  }
}

function fallbackRunDebrief(context: JsonRecord): {
  headline: string; debrief: string; tomorrow: string; planImpact: string | null; source: CoachSource;
} {
  const distanceKm = typeof context.runDistanceKm === "number" ? (context.runDistanceKm as number).toFixed(1) : "–";
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
    if (!text) {
      throw new Error("weekly_summary: OpenAI returned empty text");
    }
    const parsed = JSON.parse(text);
    const headline = limitString(parsed.headline, 50);
    const narrative = limitString(parsed.narrative, 400);
    const forwardLook = limitString(parsed.forwardLook, 160);
    const weekLabel = limitString(parsed.weekLabel, 60);
    if (!headline || !narrative || !forwardLook || !weekLabel) {
      throw new Error("weekly_summary: AI response missing required fields");
    }
    return { headline, narrative, forwardLook, weekLabel, source: "live_ai" as CoachSource };
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
  if (runs === 0) {
    return {
      headline: "Rest week",
      narrative: "Every week is a fresh start. Lace up whenever you're ready.",
      forwardLook: "Check Today for your next recommended session.",
      weekLabel: "This week",
      source: "fallback",
    };
  }
  return {
    headline: `${runs} ${runWord} · ${distanceKm} km`,
    narrative: "A solid week of training. RunSmart has logged your effort.",
    forwardLook: "Check Today for your next recommended session.",
    weekLabel: "This week",
    source: "fallback",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    if (!isOriginAllowed(req)) {
      return new Response("Forbidden", { status: 403, headers: corsHeaders(req) });
    }
    return new Response("ok", { headers: corsHeaders(req) });
  }

  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Method not allowed" }, 405);
  }
  if (!isOriginAllowed(req)) {
    return jsonResponse(req, { error: "Origin not allowed" }, 403);
  }

  const supabaseUrl = requireEnv("SUPABASE_URL");
  const anonKey = requireEnv("SUPABASE_ANON_KEY");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();

  if (!jwt) {
    return jsonResponse(req,{ error: "Missing bearer token" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await userClient.auth.getUser(jwt);
  if (authError || !authData.user) {
    return jsonResponse(req,{ error: "Unauthorized" }, 401);
  }

  let body: JsonRecord;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(req,{ error: "Invalid JSON body" }, 400);
  }

  const message = stringValue(body.message).trim();
  const clientMessageId = stringValue(body.clientMessageId).trim();
  const entryPoint = normalizeEntryPoint(stringValue(body.entryPoint));
  const conversationId = optionalUUID(body.conversationId);
  const clientTimestamp = stringValue(body.clientTimestamp).trim();
  const context = asRecord(body.context);
  const intent = stringValue(body.intent) || "chat";

  // Route run_debrief before the chat-specific validation
  if (intent === "run_debrief") {
    // iOS RunDebriefRequestDTO sends run fields at top level (not nested under body.context)
    if (containsForbiddenKeys(body)) {
      return jsonResponse(req,{ error: "Context contains forbidden keys" }, 400);
    }
    const safeContext: JsonRecord = {
      runDistanceKm: typeof body.runDistanceKm === "number" ? body.runDistanceKm : null,
      runDurationSeconds: typeof body.runDurationSeconds === "number" ? body.runDurationSeconds : null,
      averagePaceMinPerKm: typeof body.averagePaceMinPerKm === "number" ? body.averagePaceMinPerKm : null,
      averageHeartRateBPM: typeof body.averageHeartRateBPM === "number" ? body.averageHeartRateBPM : null,
      workoutType: limitString(body.workoutType, 40),
      planPhase: body.planPhase ? limitString(body.planPhase as string, 80) : null,
      recentLoadDays: typeof body.recentLoadDays === "number" ? body.recentLoadDays : 0,
      injurySignal: Boolean(body.injurySignal),
      effortRating: typeof body.effortRating === "number" ? body.effortRating : null,
      limitations: Array.isArray(body.limitations) ? (body.limitations as unknown[]).slice(0, 5).map(l => limitString(l, 160)) : [],
    };
    const debrief = await generateRunDebrief(safeContext);
    return jsonResponse(req,debrief);
  }

  if (intent === "weekly_summary") {
    if (!context) {
      return jsonResponse(req,{ error: "Context is required for weekly_summary" }, 400);
    }
    if (containsForbiddenKeys(context)) {
      return jsonResponse(req,{ error: "Context contains forbidden keys" }, 400);
    }
    const safeContext: JsonRecord = {
      weekStartDate: limitString(context.weekStartDate, 20),
      runsCompleted: typeof context.runsCompleted === "number" ? context.runsCompleted : 0,
      runsPlanned: typeof context.runsPlanned === "number" ? context.runsPlanned : 0,
      totalDistanceKm: typeof context.totalDistanceKm === "number" ? context.totalDistanceKm : 0,
      prevWeekDistanceKm: typeof context.prevWeekDistanceKm === "number" ? context.prevWeekDistanceKm : null,
      planPhase: typeof context.planPhase === "string" ? limitString(context.planPhase, 40) : null,
      isRecoveryWeek: Boolean(context.isRecoveryWeek),
      readinessAverage: typeof context.readinessAverage === "number" ? context.readinessAverage : null,
    };
    const summary = await generateWeeklySummary(safeContext);
    return jsonResponse(req,summary);
  }

  if (intent === "flex_week") {
    if (containsForbiddenKeys(body)) {
      return jsonResponse(req,{ error: "Context contains forbidden keys" }, 400);
    }
    const request = sanitizeFlexWeekRequest(body);
    if (!request) {
      return jsonResponse(req,{ error: "Invalid flex_week payload" }, 400);
    }
    const outcome = await generateFlexWeek(request);
    return jsonResponse(req,{
      restructuredWeek: outcome.restructured_week,
      changes: outcome.changes.map((change) => ({
        workoutId: change.workout_id,
        changeType: change.change_type,
        rationale: change.rationale,
        originalWorkoutId: change.original_workout_id,
      })),
      safetyWarnings: outcome.safety_warnings,
      source: outcome.source,
    });
  }

  if (!message) {
    return jsonResponse(req, { error: "Message is required" }, 400);
  }
  if (message.count > MAX_CHAT_MESSAGE_LENGTH) {
    return jsonResponse(req, { error: `Message must be ${MAX_CHAT_MESSAGE_LENGTH} characters or fewer` }, 400);
  }
  if (!clientMessageId) {
    return jsonResponse(req,{ error: "clientMessageId is required" }, 400);
  }
  if (body.conversationId != null && !conversationId) {
    return jsonResponse(req,{ error: "conversationId must be a UUID" }, 400);
  }
  if (!context || containsForbiddenKeys(context)) {
    return jsonResponse(req,{ error: "Training context contains raw route coordinates" }, 400);
  }

  const sanitizedContext = sanitizeTrainingContext(context);
  const safetyFlags = safetyFlagsFor(message);
  const userId = authData.user.id;

  try {
    const conversation = await resolveConversation(adminClient, userId, conversationId);
    const userMessage = await persistMessage(adminClient, {
      conversationId: conversation.id,
      authUserId: userId,
      role: "user",
      content: message,
      clientMessageId,
      source: "client",
      metadata: { entryPoint, clientTimestamp, context: sanitizedContext },
    });

    const ai = await liveCoachResponse(message, sanitizedContext, safetyFlags);
    const source: CoachSource = ai.source;
    const assistantMessage = await persistMessage(adminClient, {
      conversationId: conversation.id,
      authUserId: userId,
      role: "assistant",
      content: ai.content,
      clientMessageId: `${clientMessageId}:assistant`,
      source,
      metadata: {
        entryPoint,
        safetyFlags,
        model: ai.model,
        fallbackReason: ai.fallbackReason,
      },
    });

    return jsonResponse(req,{
      conversationId: conversation.id,
      userMessageId: userMessage.id,
      assistantMessage: {
        id: assistantMessage.id,
        role: assistantMessage.role,
        content: assistantMessage.content,
        createdAt: assistantMessage.created_at,
      },
      source,
      fallback: source === "fallback",
      suggestedAction: null,
      safetyFlags,
      usage: ai.usage,
    });
  } catch (error) {
    console.error("coach_message failed", error);
    return jsonResponse(req,{ error: "Coach message failed" }, 500);
  }
});

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing ${name}`);
  }
  return value;
}

function jsonResponse(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      "Content-Type": "application/json",
    },
  });
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asRecord(value: unknown): JsonRecord | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as JsonRecord;
}

function optionalUUID(value: unknown): string | null {
  if (value == null || value === "") {
    return null;
  }
  if (typeof value !== "string") {
    return null;
  }
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : null;
}

function normalizeEntryPoint(value: string): string {
  const allowed = new Set(["today", "plan", "run", "report", "profile"]);
  const normalized = value.trim().toLowerCase();
  return allowed.has(normalized) ? normalized : "today";
}

function containsForbiddenKeys(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some(containsForbiddenKeys);
  }
  if (!value || typeof value !== "object") {
    return false;
  }

  for (const [key, nested] of Object.entries(value as JsonRecord)) {
    const normalized = key.replace(/[^a-z0-9_]/gi, "").toLowerCase();
    if (forbiddenContextKeys.has(normalized)) {
      return true;
    }
    if (containsForbiddenKeys(nested)) {
      return true;
    }
  }
  return false;
}

function sanitizeTrainingContext(context: JsonRecord): JsonRecord {
  return {
    generatedAt: limitString(context.generatedAt, 40),
    entryPoint: normalizeEntryPoint(stringValue(context.entryPoint)),
    runner: pickRecord(context.runner, ["goal", "level", "streak", "totalRuns", "totalDistanceKm", "totalTime"]),
    today: pickRecord(context.today, [
      "readiness",
      "readinessLabel",
      "workoutTitle",
      "distance",
      "pace",
      "coachMessage",
      "weeklyProgress",
      "recovery",
      "hrv",
    ]),
    plan: {
      ...pickRecord(context.plan, ["activePlanTitle", "planType", "totalWeeks", "weeklyWorkoutCount"]),
      upcomingWorkouts: limitArray(asRecord(context.plan)?.upcomingWorkouts, 3).map((item) =>
        pickRecord(item, ["scheduledDate", "title", "kind", "distance", "detail", "isToday", "isComplete"])
      ),
    },
    recovery: pickRecord(context.recovery, ["readiness", "bodyBattery", "sleep", "hrv", "stress", "recommendation"]),
    wellness: pickRecord(context.wellness, ["hydration", "soreness", "mood", "checkInStatus"]),
    activity: {
      ...pickRecord(context.activity, ["recentRunCount", "sources", "averageWeeklyDistanceKm"]),
      recentRuns: limitArray(asRecord(context.activity)?.recentRuns, 5).map((item) =>
        pickRecord(item, [
          "source",
          "startedAt",
          "distanceKm",
          "movingTimeSeconds",
          "paceLabel",
          "averageHeartRateBPM",
          "hasRoute",
          "routePointCount",
        ])
      ),
    },
    routes: limitArray(context.routes, 3).map((item) =>
      pickRecord(item, [
        "name",
        "distanceKm",
        "elevationGainMeters",
        "estimatedDurationMinutes",
        "kind",
        "recommendationReason",
        "isFavorite",
        "hasGeometry",
      ])
    ),
    reports: limitArray(context.reports, 3).map((item) =>
      pickRecord(item, ["title", "dateLabel", "distance", "pace", "score", "insight", "hasGeneratedReport"])
    ),
    limitations: limitArray(context.limitations, 5).map((item) => limitString(item, 160)),
  };
}

function pickRecord(value: unknown, keys: string[]): JsonRecord {
  const source = asRecord(value) ?? {};
  const result: JsonRecord = {};
  for (const key of keys) {
    if (source[key] == null) {
      continue;
    }
    if (typeof source[key] === "string") {
      result[key] = limitString(source[key], 240);
    } else {
      result[key] = source[key];
    }
  }
  return result;
}

function limitArray(value: unknown, max: number): unknown[] {
  return Array.isArray(value) ? value.slice(0, max) : [];
}

function limitString(value: unknown, max: number): string {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, max);
}

function safetyFlagsFor(message: string): string[] {
  const lower = message.toLowerCase();
  const flags: string[] = [];
  if (/(pain|injur|dizzi|chest pain|faint|fainting|severe|shortness of breath)/i.test(lower)) {
    flags.push("medical_caution");
  }
  return flags;
}

async function resolveConversation(client: SupabaseDbClient, userId: string, conversationId: string | null): Promise<ConversationRow> {
  if (conversationId) {
    const { data, error } = await client
      .from("conversations")
      .select("id,profile_id,auth_user_id")
      .eq("id", conversationId)
      .or(`auth_user_id.eq.${userId},profile_id.eq.${userId}`)
      .maybeSingle();
    if (error) {
      throw error;
    }
    if (!data) {
      throw new Error("Conversation not found");
    }
    return data as ConversationRow;
  }

  const { data: existing, error: existingError } = await client
    .from("conversations")
    .select("id,profile_id,auth_user_id")
    .or(`auth_user_id.eq.${userId},profile_id.eq.${userId}`)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }
  if (existing) {
    return existing as ConversationRow;
  }

  const { data: inserted, error: insertError } = await client
    .from("conversations")
    .insert({
      auth_user_id: userId,
      profile_id: userId,
      title: "RunSmart Coach",
    })
    .select("id,profile_id,auth_user_id")
    .single();
  if (insertError) {
    throw insertError;
  }
  return inserted as ConversationRow;
}

async function persistMessage(
  client: SupabaseDbClient,
  input: {
    conversationId: string;
    authUserId: string;
    role: "user" | "assistant";
    content: string;
    clientMessageId: string;
    source: string;
    metadata: JsonRecord;
  },
): Promise<MessageRow> {
  const { data: existing, error: existingError } = await client
    .from("conversation_messages")
    .select("id,role,content,created_at")
    .eq("conversation_id", input.conversationId)
    .eq("client_message_id", input.clientMessageId)
    .limit(1)
    .maybeSingle();
  if (existingError) {
    throw existingError;
  }
  if (existing) {
    return existing as MessageRow;
  }

  const { data, error } = await client
    .from("conversation_messages")
    .insert({
      conversation_id: input.conversationId,
      auth_user_id: input.authUserId,
      role: input.role,
      content: input.content,
      client_message_id: input.clientMessageId,
      source: input.source,
      metadata: input.metadata,
    })
    .select("id,role,content,created_at")
    .single();
  if (error) {
    throw error;
  }
  return data as MessageRow;
}

async function liveCoachResponse(message: string, context: JsonRecord, safetyFlags: string[]) {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL") || "gpt-4.1-mini";
  if (!apiKey) {
    return {
      content: fallbackCoachResponse(message, context, safetyFlags),
      source: "fallback" as CoachSource,
      model,
      fallbackReason: "missing_openai_api_key",
      usage: null,
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        instructions: SYSTEM_PROMPT,
        input: [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: `Runner message: ${message}\n\nSanitized training context:\n${JSON.stringify(context)}`,
              },
            ],
          },
        ],
        max_output_tokens: 260,
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI status ${response.status}`);
    }

    const json = await response.json();
    const content = extractResponseText(json).trim();
    if (!content) {
      throw new Error("OpenAI returned empty text");
    }

    return {
      content,
      source: "live_ai" as CoachSource,
      model,
      fallbackReason: null,
      usage: {
        inputTokens: json.usage?.input_tokens ?? null,
        outputTokens: json.usage?.output_tokens ?? null,
        totalTokens: json.usage?.total_tokens ?? null,
      },
    };
  } catch (error) {
    console.error("OpenAI coach fallback", error);
    return {
      content: fallbackCoachResponse(message, context, safetyFlags),
      source: "fallback" as CoachSource,
      model,
      fallbackReason: error instanceof Error ? error.message : "openai_failed",
      usage: null,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function extractResponseText(json: JsonRecord): string {
  if (typeof json.output_text === "string") {
    return json.output_text;
  }
  const output = Array.isArray(json.output) ? json.output : [];
  const parts: string[] = [];
  for (const item of output) {
    const record = asRecord(item);
    const content = Array.isArray(record?.content) ? record.content : [];
    for (const contentItem of content) {
      const contentRecord = asRecord(contentItem);
      const text = contentRecord?.text;
      if (typeof text === "string") {
        parts.push(text);
      }
    }
  }
  return parts.join("\n").trim();
}

function fallbackCoachResponse(message: string, context: JsonRecord, safetyFlags: string[]): string {
  if (safetyFlags.includes("medical_caution")) {
    return "If you are feeling pain, dizziness, chest pain, fainting, or severe symptoms, stop the activity and speak with a qualified professional. Keep today's decision conservative. Once you are safe and symptoms are resolved, use the next easy planned session as the next best step.";
  }

  const today = asRecord(context.today) ?? {};
  const plan = asRecord(context.plan) ?? {};
  const workouts = limitArray(plan.upcomingWorkouts, 1);
  const nextWorkout = asRecord(workouts[0]);
  const readiness = typeof today.readiness === "number" ? today.readiness : 0;
  const title = stringValue(nextWorkout?.title) || stringValue(today.workoutTitle) || "easy running";
  const distance = stringValue(nextWorkout?.distance) || stringValue(today.distance);

  if (readiness > 0) {
    return `I see readiness at ${readiness}, so keep the next step conservative and clear. Today, aim for ${title}${distance ? ` (${distance})` : ""} at a comfortable effort. If your legs feel heavier than expected, shorten the run or switch to recovery and stay on track.`;
  }

  return "I have limited training context, so the safest next step is an easy effort or recovery day rather than forcing intensity. Use the next planned workout only if you feel normal in warmup. Keep it calm, and adjust based on how your body responds.";
}
