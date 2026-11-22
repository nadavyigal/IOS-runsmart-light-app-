import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { codePointLength, fill, isolate, truncateGraphemes } from "./text.ts";

Deno.test("isolate wraps in FSI and PDI", () => {
  assertEquals(isolate("דנה"), "⁨דנה⁩");
});

Deno.test("fill isolates a Hebrew name and keeps the punctuation in place", () => {
  assertEquals(fill("{Coach} left you a note.", { Coach: "דנה" }), "⁨דנה⁩ left you a note.");
  assertEquals(fill("Hi {Athlete}, {Athlete}!", { Athlete: "Ron" }), "Hi ⁨Ron⁩, ⁨Ron⁩!");
  assertEquals(fill("No placeholder", { Coach: "x" }), "No placeholder");
});

Deno.test("truncateGraphemes leaves short text alone", () => {
  assertEquals(truncateGraphemes("6×800 ב-4:00", 80), "6×800 ב-4:00");
});

Deno.test("truncateGraphemes never splits an emoji or a surrogate pair", () => {
  // 78 Hebrew letters, then a family emoji (7 code points, one grapheme).
  const text = "א".repeat(78) + "👨‍👩‍👧‍👦" + " end";
  const cut = truncateGraphemes(text, 80);
  assertEquals(cut, "א".repeat(78) + "…");
  assertEquals(codePointLength(cut) <= 80, true);
});

Deno.test("truncateGraphemes keeps a whole emoji that fits", () => {
  const cut = truncateGraphemes("ab🏃cdefgh", 5);
  assertEquals(cut, "ab🏃c…");
  assertEquals(codePointLength(cut), 5);
});

Deno.test("code points match Postgres char_length for emoji", () => {
  assertEquals(codePointLength("🏃".repeat(1000)), 1000);
  assertEquals("🏃".repeat(1000).length, 2000); // UTF-16 length is not the server unit
});
