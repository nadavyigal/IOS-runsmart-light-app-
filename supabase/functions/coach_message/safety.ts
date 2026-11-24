// Deterministic safety helpers for coach_message. Prompts never replace these:
// they run whether or not the model answers, in English and in Hebrew.

export type CoachLanguage = "en" | "he";

const HEBREW_LETTER = /[֐-׿]/;

// English terms: the original chat detector plus "dizzy" (it only matched "dizziness").
const ENGLISH_MEDICAL_TERMS = /(pain|injur|dizzi|dizzy|chest pain|faint|fainting|severe|shortness of breath)/i;

// Hebrew terms match as substrings so prefixes (ה, ב, ו, ש) and plural or gendered
// endings still match: כאב / כאבים, כואב / כואבת, נפצע / נפצעתי, התעלפ / התעלפתי.
// Not מתיחה: it also means "stretching" and would flag ordinary messages.
const HEBREW_MEDICAL_TERMS = /(כאב|כואב|מכאיב|פציעה|פצוע|נפצע|נקע|סחרחורת|סחרחר|מסוחרר|התעלפ|עילפון|לחץ בחזה|קוצר נשימה|דקירה)/;

export function containsHebrew(text: string): boolean {
  return HEBREW_LETTER.test(text);
}

/** Explicit request field only. Anything other than "he" is English. */
export function resolveLanguage(body: Record<string, unknown> | null | undefined): CoachLanguage {
  return body?.language === "he" ? "he" : "en";
}

export function hasMedicalSignal(text: string): boolean {
  if (!text) return false;
  return ENGLISH_MEDICAL_TERMS.test(text) || HEBREW_MEDICAL_TERMS.test(text);
}

export function safetyFlagsFor(message: string): string[] {
  return hasMedicalSignal(message) ? ["medical_caution"] : [];
}

export const MEDICAL_CAUTION_FALLBACK: Record<CoachLanguage, string> = {
  en: "If you are feeling pain, dizziness, chest pain, fainting, or severe symptoms, stop the activity and speak with a qualified professional. Keep today's decision conservative. Once you are safe and symptoms are resolved, use the next easy planned session as the next best step.",
  he: "אם יש כאב, סחרחורת, כאב בחזה, התעלפות או תסמינים חמורים, כדאי לעצור את הפעילות ולפנות לאיש מקצוע מוסמך. בכאב בחזה, התעלפות או קושי לנשום, יש לפנות מיד לעזרה רפואית. ההחלטה להיום צריכה להיות זהירה.",
};

/** Chat fallback language follows the runner's message. */
export function medicalCautionFallback(message: string): string {
  return MEDICAL_CAUTION_FALLBACK[containsHebrew(message) ? "he" : "en"];
}

export const INJURY_DEBRIEF: Record<CoachLanguage, { headline: string; debrief: string; tomorrow: string }> = {
  en: {
    headline: "Rest up — listen to your body",
    debrief: "Any pain or discomfort after a run needs rest first. Check in with a professional before your next session.",
    tomorrow: "Take a full rest day tomorrow.",
  },
  he: {
    headline: "מנוחה עכשיו, להקשיב לגוף",
    debrief: "כל כאב או אי נוחות אחרי ריצה דורשים קודם מנוחה. כדאי להתייעץ עם איש מקצוע לפני האימון הבא.",
    tomorrow: "מחר יום מנוחה מלא.",
  },
};
