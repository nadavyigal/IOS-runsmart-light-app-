// Mixed-direction text for server-composed copy (Coach Experience v2, C7.15,
// folded into C7.3). Every sender that puts a name or user text into a push uses
// these, so the Swift side (Core/Text/BidiText.swift) and the server agree.
//
// - isolate(): wraps a name in FSI ... PDI (U+2068 ... U+2069), so a Hebrew name
//   never reorders the English punctuation around it.
// - fill(): fills {Coach} / {Athlete} placeholders with isolated values. Never
//   concatenate names into copy.
// - truncateGraphemes(): cuts to at most n code points (the unit of Postgres
//   char_length) without splitting a grapheme cluster or a surrogate pair, and
//   appends "…" when it cut. The ellipsis counts toward n.

const FSI = "⁨";
const PDI = "⁩";

export function isolate(text: string): string {
  return `${FSI}${text}${PDI}`;
}

export function fill(template: string, values: Record<string, string>): string {
  let out = template;
  for (const [key, value] of Object.entries(values)) {
    out = out.split(`{${key}}`).join(isolate(value));
  }
  return out;
}

/** Code points, like Postgres char_length. */
export function codePointLength(text: string): number {
  return Array.from(text).length;
}

export function truncateGraphemes(text: string, n: number): string {
  if (n <= 0) return "";
  if (codePointLength(text) <= n) return text;
  const budget = n - 1;
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  let kept = "";
  let used = 0;
  for (const { segment } of segmenter.segment(text)) {
    const size = codePointLength(segment);
    if (used + size > budget) break;
    kept += segment;
    used += size;
  }
  return `${kept}…`;
}
