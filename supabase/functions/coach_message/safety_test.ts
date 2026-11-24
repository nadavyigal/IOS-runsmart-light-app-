import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  containsHebrew,
  INJURY_DEBRIEF,
  MEDICAL_CAUTION_FALLBACK,
  medicalCautionFallback,
  resolveLanguage,
  safetyFlagsFor,
} from "./safety.ts";

Deno.test("English medical terms still flag (unchanged behavior)", () => {
  for (const message of [
    "my knee has pain",
    "I think I'm injured",
    "felt dizzy at km 3",
    "chest pain on the hill",
    "almost fainted",
    "severe cramp",
    "shortness of breath after intervals",
  ]) {
    assertEquals(safetyFlagsFor(message), ["medical_caution"], message);
  }
});

Deno.test("Hebrew medical terms flag, with prefixes and endings", () => {
  for (const message of [
    "כואב לי בברך",
    "יש לי כאבים בשוק",
    "הברך מכאיבה לי",
    "נפצעתי בריצה אתמול",
    "יש לי פציעה בקרסול",
    "נקע בקרסול",
    "הרגשתי סחרחורת",
    "אני מסוחרר",
    "כמעט התעלפתי",
    "יש לי לחץ בחזה",
    "קוצר נשימה בעלייה",
    "דקירה בצד",
  ]) {
    assertEquals(safetyFlagsFor(message), ["medical_caution"], message);
  }
});

Deno.test("ordinary messages do not flag, in either language", () => {
  for (const message of [
    "How fast should my easy run be?",
    "מה הקצב לריצה קלה?",
    "עשיתי מתיחות אחרי הריצה",
    "רוצה לרוץ 10 ק״מ בשבת",
  ]) {
    assertEquals(safetyFlagsFor(message), [], message);
  }
});

Deno.test("chat medical fallback follows the message language", () => {
  assertEquals(medicalCautionFallback("my knee has pain"), MEDICAL_CAUTION_FALLBACK.en);
  assertEquals(medicalCautionFallback("כואב לי בברך"), MEDICAL_CAUTION_FALLBACK.he);
  assertEquals(MEDICAL_CAUTION_FALLBACK.he.includes("לעזרה רפואית"), true);
  assertEquals(MEDICAL_CAUTION_FALLBACK.he.includes("איש מקצוע מוסמך"), true);
});

Deno.test("language is explicit only; default English", () => {
  assertEquals(resolveLanguage({ language: "he" }), "he");
  assertEquals(resolveLanguage({ language: "en" }), "en");
  assertEquals(resolveLanguage({ language: "HE" }), "en");
  assertEquals(resolveLanguage({}), "en");
  assertEquals(resolveLanguage(null), "en");
});

Deno.test("injury debrief text exists in both languages; English unchanged", () => {
  assertEquals(INJURY_DEBRIEF.en.headline, "Rest up — listen to your body");
  assertEquals(INJURY_DEBRIEF.en.tomorrow, "Take a full rest day tomorrow.");
  assertEquals(containsHebrew(INJURY_DEBRIEF.he.headline), true);
  assertEquals(INJURY_DEBRIEF.he.headline.length <= 40, true);
});
