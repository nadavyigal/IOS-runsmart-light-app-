// C8.5: coach-locked workouts, read as the signed-in athlete (workouts RLS).
// Before Batch C (M6a) is applied there is no `locked` column: the query errors
// and every row counts as unlocked, so solo athletes and old schemas behave as today.

import type { LockedWorkoutSummary } from "./coach_prompts.ts";

type LockQueryResult = { data: unknown; error: unknown };

// The slice of the supabase-js query builder this file uses. Tests pass a fake.
export type LockQuery = PromiseLike<LockQueryResult> & {
  eq(column: string, value: unknown): LockQuery;
  in(column: string, values: string[]): LockQuery;
  gte(column: string, value: string): LockQuery;
  order(column: string): LockQuery;
  limit(count: number): LockQuery;
};

export type LockClient = { from(table: string): { select(columns: string): LockQuery } };

const LOOKBACK_DAYS = 7;
const MAX_ROWS = 60;

/** With `workoutIds`, only those rows (flex week). Without, the recent and upcoming locked rows (chat). */
export async function loadLockedWorkouts(
  client: LockClient,
  workoutIds?: string[],
  now: Date = new Date(),
): Promise<LockedWorkoutSummary[]> {
  if (workoutIds && workoutIds.length === 0) return [];
  try {
    let query = client.from("workouts").select("id, scheduled_date, type").eq("locked", true);
    if (workoutIds) {
      query = query.in("id", workoutIds);
    } else {
      const since = new Date(now.getTime() - LOOKBACK_DAYS * 86_400_000).toISOString().slice(0, 10);
      query = query.gte("scheduled_date", since).order("scheduled_date").limit(MAX_ROWS);
    }
    const { data, error } = await query;
    if (error || !Array.isArray(data)) return [];
    return data.flatMap((row) => {
      const record = row as Record<string, unknown>;
      if (typeof record.id !== "string") return [];
      return [{
        id: record.id,
        scheduledDate: typeof record.scheduled_date === "string" ? record.scheduled_date : "",
        type: typeof record.type === "string" ? record.type : "",
      }];
    });
  } catch {
    return [];
  }
}
