# Voice cue tone change for the web route

Date: 2026-11-01
State: proposed. Not applied. The web repo was not edited.

The iOS change sends `coachingStyle` on the next build. Live 1.2.2 does not. The route still has to read `profiles.coaching_style` for the signed-in user, or current installs keep one prompt and one voice.

Apply this on the web repo that contains `v0/app/api/coach/voice-cue/route.ts`. Source checked: the audits worktree copy of that file on 2026-11-01. Re-read the file before applying. Do not deploy from this note.

Keys stay server-side. `OPENAI_VOICE_KEY`, falling back to `OPENAI_API_KEY`. The app sends the Supabase access token and the style string. No new provider.

## What the diff does

- Map the stored style to one of three prompts.
- `encouraging` and `challenging` (old Strict) use the motivating prompt.
- `supportive` uses the calm prompt. Old Direct was stored as `supportive`, so it speaks as calm.
- `analytical` uses the technical prompt.
- A missing or unknown style uses the motivating prompt. That matches the app default.
- Prefer `body.coachingStyle` when it is present. Otherwise read `profiles.coaching_style` for `auth.user.id` with the caller's bearer token, under row security. Do not use the service role.
- Throttle on `user:<auth user id>`. Stop using the client IP for an authenticated call.
- Keep `tts-1`, voice `nova`, speed `0.95`, AAC. The proposed per-tone voices are in the new module and are not sent.
- Keep `Cache-Control: no-store`.

## Cost and cache

Checked against the OpenAI pricing page on 2026-11-01.

- `tts-1` is $15 per 1 million characters. A 140 character cue is about $0.0021.
- `gpt-4o-mini` on the standard table is $0.15 per 1 million input tokens and $0.60 per 1 million output tokens. The three prompts are a few dozen tokens longer than the one prompt today. That adds well under $0.0001 per cue.
- Text plus speech stays about $0.0022 per AI cue. About $0.013 for six cues in 30 minutes. About $0.026 for twelve cues in 60 minutes. The on-device tone change costs $0.
- A different `tts-1` voice is the same character price. It is not turned on here.
- `tts-1`, `tts-1-hd`, and `gpt-4o-mini-tts` are marked deprecated, with removal listed for 2027-01-06. Moving to another model is a new provider choice. It needs the founder's yes. It is not in this diff.
- Do not cache the audio. Each cue names that runner's pace and distance. A shared cache would speak the wrong numbers. A per-user cache would almost never hit, because the numbers change every five minutes. The static prompts live in the module. No cache key is worth adding.
- ElevenLabs is not in this diff.

## Proposed voice map (not applied)

Same provider, `tts-1`. Do not send these until the founder says yes after a listening test.

| Tone | Voice | Speed |
| --- | --- | --- |
| Motivating | nova | 1.0 |
| Calm | shimmer | 0.9 |
| Technical | onyx | 0.95 |

The route keeps nova at 0.95 for every tone.

## Tests to add

File: `v0/lib/server/voice-cue-tone.test.ts`

Run from `v0` after the files exist:

```
npx vitest run lib/server/voice-cue-tone.test.ts
```

These tests were not run. The web repo was not edited.

They should assert:

1. `encouraging` and `Motivating` and `challenging` and `Strict` resolve to `motivating`.
2. `supportive` and `Calm` and `Direct` resolve to `calm`.
3. `analytical` and `Technical` resolve to `technical`.
4. An empty style resolves to `motivating`.
5. The three system prompts differ, and each forbids opening with "Great job" and forbids running through pain.
6. `speechBody` for every tone uses `model: "tts-1"`, `voice: "nova"`, `speed: 0.95`, `response_format: "aac"`.
7. `speechBody` does not use `shimmer` or `onyx`.
8. `throttleKeyForUser("abc")` is `user:abc`.

## Diff

Generated with `diff -u` against `v0/app/api/coach/voice-cue/route.ts` as read on 2026-11-01. The two new files are included as new-file hunks. Apply from the web repo root. Re-read the route first. If the file has moved, do not force this patch.

```diff
diff --git a/v0/lib/server/voice-cue-tone.ts b/v0/lib/server/voice-cue-tone.ts
new file mode 100644
--- /dev/null
+++ b/v0/lib/server/voice-cue-tone.ts
@@ -0,0 +1,65 @@
+export type VoiceTone = "motivating" | "calm" | "technical"
+
+const PROMPTS: Record<VoiceTone, string> = {
+  motivating: `You are RunSmart, a motivating running coach.
+Give one short cue (1 to 2 sentences, max 25 words).
+Sound warm and forward. Name the pace or distance you were given.
+Never open with "Great job". Never advise running through pain. If the runner mentions pain, say stop and consult a professional.
+Sound like a real coach, not a chatbot.`,
+  calm: `You are RunSmart, a calm running coach.
+Give one short cue (1 to 2 sentences, max 25 words).
+Sound quiet and steady. Name the pace or distance you were given.
+Never open with "Great job". Never advise running through pain. If the runner mentions pain, say stop and consult a professional.
+Sound like a real coach, not a chatbot.`,
+  technical: `You are RunSmart, a technical running coach.
+Give one short cue (1 to 2 sentences, max 25 words).
+Lead with the number. No cheerleading.
+Never open with "Great job". Never advise running through pain. If the runner mentions pain, say stop and consult a professional.
+Sound like a real coach, not a chatbot.`,
+}
+
+/** Prepared only. speechBody does not read this. Founder yes required before use. */
+export const PROPOSED_OPENAI_VOICES: Record<VoiceTone, { voice: string; speed: number }> = {
+  motivating: { voice: "nova", speed: 1.0 },
+  calm: { voice: "shimmer", speed: 0.9 },
+  technical: { voice: "onyx", speed: 0.95 },
+}
+
+export function resolveVoiceTone(style: string | null | undefined): VoiceTone {
+  const s = (style ?? "").toLowerCase()
+  if (s.includes("techni") || s.includes("analytic")) return "technical"
+  if (s.includes("calm") || s.includes("support") || s.includes("direct")) return "calm"
+  if (
+    s.includes("motivat") ||
+    s.includes("encourag") ||
+    s.includes("strict") ||
+    s.includes("challeng")
+  ) {
+    return "motivating"
+  }
+  return "motivating"
+}
+
+export function systemPromptForTone(tone: VoiceTone): string {
+  return PROMPTS[tone]
+}
+
+export function speechBody(cueText: string, _tone: VoiceTone): {
+  model: "tts-1"
+  input: string
+  voice: "nova"
+  response_format: "aac"
+  speed: 0.95
+} {
+  return {
+    model: "tts-1",
+    input: cueText,
+    voice: "nova",
+    response_format: "aac",
+    speed: 0.95,
+  }
+}
+
+export function throttleKeyForUser(userId: string): string {
+  return `user:${userId}`
+}
diff --git a/v0/lib/server/voice-cue-tone.test.ts b/v0/lib/server/voice-cue-tone.test.ts
new file mode 100644
--- /dev/null
+++ b/v0/lib/server/voice-cue-tone.test.ts
@@ -0,0 +1,49 @@
+import { describe, expect, it } from "vitest"
+import {
+  resolveVoiceTone,
+  speechBody,
+  systemPromptForTone,
+  throttleKeyForUser,
+} from "./voice-cue-tone"
+
+describe("voice cue tone", () => {
+  it("maps stored styles and labels onto three tones", () => {
+    expect(resolveVoiceTone("encouraging")).toBe("motivating")
+    expect(resolveVoiceTone("Motivating")).toBe("motivating")
+    expect(resolveVoiceTone("challenging")).toBe("motivating")
+    expect(resolveVoiceTone("Strict")).toBe("motivating")
+    expect(resolveVoiceTone("supportive")).toBe("calm")
+    expect(resolveVoiceTone("Calm")).toBe("calm")
+    expect(resolveVoiceTone("Direct")).toBe("calm")
+    expect(resolveVoiceTone("analytical")).toBe("technical")
+    expect(resolveVoiceTone("Technical")).toBe("technical")
+    expect(resolveVoiceTone("")).toBe("motivating")
+    expect(resolveVoiceTone(null)).toBe("motivating")
+  })
+
+  it("uses three different prompts with the same safety lines", () => {
+    const prompts = (["motivating", "calm", "technical"] as const).map(systemPromptForTone)
+    expect(new Set(prompts).size).toBe(3)
+    for (const prompt of prompts) {
+      expect(prompt).toContain('Never open with "Great job"')
+      expect(prompt).toContain("Never advise running through pain")
+      expect(prompt).toContain("say stop and consult a professional")
+    }
+  })
+
+  it("keeps one OpenAI voice until the founder says otherwise", () => {
+    for (const tone of ["motivating", "calm", "technical"] as const) {
+      expect(speechBody("Hold this pace.", tone)).toEqual({
+        model: "tts-1",
+        input: "Hold this pace.",
+        voice: "nova",
+        response_format: "aac",
+        speed: 0.95,
+      })
+    }
+  })
+
+  it("throttles by the authenticated user id", () => {
+    expect(throttleKeyForUser("abc")).toBe("user:abc")
+  })
+})
diff --git a/v0/app/api/coach/voice-cue/route.ts b/v0/app/api/coach/voice-cue/route.ts
--- a/v0/app/api/coach/voice-cue/route.ts
+++ b/v0/app/api/coach/voice-cue/route.ts
@@ -1,9 +1,16 @@
 import { NextResponse } from "next/server"
 import { generateText } from "ai"
 import { createOpenAI } from "@ai-sdk/openai"
+import { createClient } from "@supabase/supabase-js"
 import { captureServerEvent } from "@/lib/server/posthog"
 import { checkVoiceCueThrottle } from "@/lib/server/voice-cue-throttle"
 import { requireApiUser } from "@/lib/api-auth"
+import {
+  resolveVoiceTone,
+  speechBody,
+  systemPromptForTone,
+  throttleKeyForUser,
+} from "@/lib/server/voice-cue-tone"
 
 export const runtime = "nodejs"
 export const dynamic = "force-dynamic"
@@ -29,22 +36,29 @@
   targetPaceMinPerKm?: number
   workoutGoal?: string
   heartRateBPM?: number
+  coachingStyle?: string
   userId?: string
 }
 
-function throttleKey(request: Request, body: VoiceCueRequest): string {
-  if (body.userId && body.userId.trim()) return `user:${body.userId.trim()}`
-  const fwd = request.headers.get("x-forwarded-for") ?? ""
-  const ip = fwd.split(",")[0]?.trim()
-  return ip ? `ip:${ip}` : "anonymous"
+async function storedCoachingStyle(request: Request, userId: string): Promise<string | null> {
+  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()
+  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim()
+  const bearer = request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1]
+  if (!url || !anonKey || !bearer) return null
+  const supabase = createClient(url, anonKey, {
+    global: { headers: { Authorization: `Bearer ${bearer}` } },
+    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
+  })
+  const { data, error } = await supabase
+    .from("profiles")
+    .select("coaching_style")
+    .eq("auth_user_id", userId)
+    .limit(1)
+    .maybeSingle()
+  if (error || typeof data?.coaching_style !== "string") return null
+  return data.coaching_style
 }
 
-const COACH_SYSTEM_PROMPT = `You are RunSmart, a calm encouraging running coach.
-Give one short coaching cue (1–2 sentences, max 25 words).
-Be specific to the data provided. Never open with "Great job".
-Never advise running through pain — if the runner mentions pain, say stop and consult a professional.
-Sound like a real coach, not a chatbot.`
-
 export async function POST(request: Request): Promise<Response> {
   const auth = await requireApiUser(request)
   if (auth.response) return auth.response
@@ -59,11 +73,11 @@
     return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 })
   }
 
-  const key = throttleKey(request, body)
+  const key = throttleKeyForUser(auth.user.id)
   const throttle = checkVoiceCueThrottle(key)
   if (!throttle.allowed) {
     await captureServerEvent("voice_cue_throttled", {
-      userId: body.userId,
+      userId: auth.user.id,
       reason: throttle.reason,
     })
     return NextResponse.json(
@@ -72,6 +86,10 @@
     )
   }
 
+  const style = body.coachingStyle?.trim()
+    ? body.coachingStyle
+    : await storedCoachingStyle(request, auth.user.id)
+  const tone = resolveVoiceTone(style)
   const { elapsedMinutes, distanceKm, currentPaceMinPerKm, targetPaceMinPerKm, workoutGoal, heartRateBPM } = body
 
   const userContext = [
@@ -89,7 +107,7 @@
   try {
     const result = await generateText({
       model: voiceOpenAI("gpt-4o-mini"),
-      system: COACH_SYSTEM_PROMPT,
+      system: systemPromptForTone(tone),
       prompt: userContext,
       maxTokens: 60,
     })
@@ -111,13 +129,7 @@
         Authorization: `Bearer ${apiKey}`,
         "Content-Type": "application/json",
       },
-      body: JSON.stringify({
-        model: "tts-1",
-        input: cueText,
-        voice: "nova",
-        response_format: "aac",
-        speed: 0.95,
-      }),
+      body: JSON.stringify(speechBody(cueText, tone)),
     })
     if (!ttsResponse.ok) {
       return NextResponse.json({ error: "TTS generation failed" }, { status: 500 })
@@ -128,7 +140,7 @@
   }
 
   await captureServerEvent("voice_cue_served", {
-    userId: body.userId,
+    userId: auth.user.id,
     estimatedCostUsd: estimateCueCostUsd(cueText),
     cueChars: cueText.length,
   })
```

The route hunk is the edit. After it applies, run `npx vitest run lib/server/voice-cue-tone.test.ts` from `v0`, and the existing voice-cue case in `v0/__tests__/openai-routes-auth-gate.api.test.ts`. That auth test must still return 401 with no token. Do not print env values while checking `VOICE_COACH_ENABLED`.
