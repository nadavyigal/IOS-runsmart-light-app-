const DEFAULT_ALLOWED_ORIGINS = [
  "https://runsmart.app",
  "https://www.runsmart.app",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
];

function configuredOrigins(): string[] {
  const raw = Deno.env.get("ALLOWED_CORS_ORIGINS")?.trim();
  if (!raw) {
    return DEFAULT_ALLOWED_ORIGINS;
  }
  return raw.split(",").map((value) => value.trim()).filter(Boolean);
}

export function isOriginAllowed(req: Request): boolean {
  const origin = req.headers.get("Origin");
  // Native iOS clients typically omit Origin.
  if (!origin) {
    return true;
  }
  return configuredOrigins().includes(origin);
}

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  const allowed = configuredOrigins();
  const allowOrigin = !origin
    ? (allowed[0] ?? "null")
    : allowed.includes(origin)
    ? origin
    : "null";

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
