import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { PlanUpdateRow } from "./digest.ts";
import { supabaseDigestStore } from "./store.ts";

// The compare-and-set lives in the PostgREST filters (AC4). These tests pin every
// filter each queue call sends, using a recording stand-in for supabase-js.

interface Call {
  table: string;
  op: string;
  payload?: unknown;
  filters: [string, string, unknown][];
  select?: string;
  order?: [string, unknown];
  limit?: number;
}

function recorder(result: { data: unknown; error: unknown }) {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, op: "", filters: [] };
      calls.push(call);
      const builder = {
        select(columns: string) {
          if (!call.op) call.op = "select";
          call.select = columns;
          return builder;
        },
        update(payload: unknown) {
          call.op = "update";
          call.payload = payload;
          return builder;
        },
        delete() {
          call.op = "delete";
          return builder;
        },
        eq(column: string, value: unknown) {
          call.filters.push(["eq", column, value]);
          return builder;
        },
        is(column: string, value: unknown) {
          call.filters.push(["is", column, value]);
          return builder;
        },
        lt(column: string, value: unknown) {
          call.filters.push(["lt", column, value]);
          return builder;
        },
        order(column: string, options: unknown) {
          call.order = [column, options];
          return builder;
        },
        limit(n: number) {
          call.limit = n;
          return builder;
        },
        then(resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) {
          return Promise.resolve(result).then(resolve, reject);
        },
      };
      return builder;
    },
    rpc() {
      throw new Error("not used");
    },
  };
  return { client, calls };
}

const ROW: PlanUpdateRow = {
  athlete_id: "aaaaaaaa-0000-4000-8000-00000000000a",
  coach_id: "cccccccc-0000-4000-8000-00000000000c",
  first_change_at: "2026-11-27T10:00:00.123456+00:00",
  last_change_at: "2026-11-27T10:04:00.654321+00:00",
  change_count: 3,
  sent_at: null,
};
const COLUMNS = "athlete_id, coach_id, first_change_at, last_change_at, change_count, sent_at";

Deno.test("pendingPlanUpdates: unsent rows older than the cutoff, oldest first, limited", async () => {
  const { client, calls } = recorder({ data: [ROW], error: null });
  const rows = await supabaseDigestStore(client).pendingPlanUpdates("2026-11-27T10:00:00.000Z", 500);
  assertEquals(rows, [ROW]);
  assertEquals(calls, [{
    table: "athlete_plan_update_queue",
    op: "select",
    select: COLUMNS,
    filters: [["is", "sent_at", null], ["lt", "last_change_at", "2026-11-27T10:00:00.000Z"]],
    order: ["last_change_at", { ascending: true }],
    limit: 500,
  }]);
});

Deno.test("claimPlanUpdate: sets sent_at only where the row is unsent and unchanged since the read", async () => {
  const { client, calls } = recorder({ data: [{ ...ROW, sent_at: "2026-11-27T10:15:00.000Z" }], error: null });
  const claimed = await supabaseDigestStore(client).claimPlanUpdate(ROW, "2026-11-27T10:15:00.000Z");
  assertEquals(claimed?.sent_at, "2026-11-27T10:15:00.000Z");
  assertEquals(calls, [{
    table: "athlete_plan_update_queue",
    op: "update",
    payload: { sent_at: "2026-11-27T10:15:00.000Z" },
    select: COLUMNS,
    filters: [
      ["eq", "athlete_id", ROW.athlete_id],
      ["is", "sent_at", null],
      ["eq", "last_change_at", ROW.last_change_at],
      ["eq", "change_count", 3],
    ],
  }]);
});

Deno.test("claimPlanUpdate: no matching row (another run, a new change, a publish) returns null", async () => {
  const { client } = recorder({ data: [], error: null });
  assertEquals(await supabaseDigestStore(client).claimPlanUpdate(ROW, "2026-11-27T10:15:00.000Z"), null);
});

Deno.test("dropPlanUpdate: deletes under the same compare-and-set", async () => {
  const { client, calls } = recorder({ data: [{ athlete_id: ROW.athlete_id }], error: null });
  assertEquals(await supabaseDigestStore(client).dropPlanUpdate(ROW), true);
  assertEquals(calls, [{
    table: "athlete_plan_update_queue",
    op: "delete",
    select: "athlete_id",
    filters: [
      ["eq", "athlete_id", ROW.athlete_id],
      ["is", "sent_at", null],
      ["eq", "last_change_at", ROW.last_change_at],
      ["eq", "change_count", 3],
    ],
  }]);
  const none = recorder({ data: [], error: null });
  assertEquals(await supabaseDigestStore(none.client).dropPlanUpdate(ROW), false);
});

Deno.test("queue errors are thrown, never read as 'nothing to do'", async () => {
  const { client } = recorder({ data: null, error: { message: "permission denied" } });
  const store = supabaseDigestStore(client);
  await assertRejects(() => store.pendingPlanUpdates("2026-11-27T10:00:00.000Z", 500), Error, "queue_read_failed");
  await assertRejects(() => store.claimPlanUpdate(ROW, "2026-11-27T10:15:00.000Z"), Error, "queue_claim_failed");
  await assertRejects(() => store.dropPlanUpdate(ROW), Error, "queue_drop_failed");
});
