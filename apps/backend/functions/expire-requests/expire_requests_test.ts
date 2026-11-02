// `expire-requests` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { expireStaleRows, isStale, type StaleRow } from "./index.ts";

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_760_000_000_000;

function row(over: {
  id: string;
  status: "open" | "needs_evidence";
  submitted_at: number;
  last_touched: number | null;
  waiting_days: number;
}): StaleRow {
  return over;
}

Deno.test("nothing touched for the waiting period is stale", () => {
  const r = row({
    id: "a",
    status: "open",
    submitted_at: NOW - 61 * DAY,
    last_touched: null,
    waiting_days: 60,
  });
  assertEquals(isStale(r, NOW), true);
});

Deno.test("a pledge yesterday keeps a request fresh", () => {
  const r = row({
    id: "a",
    status: "open",
    submitted_at: NOW - 90 * DAY,
    last_touched: NOW - DAY,
    waiting_days: 60,
  });
  assertEquals(isStale(r, NOW), false);
});

Deno.test("the waiting period is exact: exactly waiting_days is stale", () => {
  const r = row({
    id: "a",
    status: "needs_evidence",
    submitted_at: NOW - 60 * DAY,
    last_touched: null,
    waiting_days: 60,
  });
  assertEquals(isStale(r, NOW), true);
  const fresher = row({ ...r, last_touched: NOW - 59 * DAY });
  assertEquals(isStale(fresher, NOW), false);
});

Deno.test("zero waiting days expires whatever the cron sees", () => {
  const r = row({
    id: "a",
    status: "open",
    submitted_at: NOW,
    last_touched: null,
    waiting_days: 0,
  });
  assertEquals(isStale(r, NOW), true);
});

Deno.test("a guarded skip (money with the payee) doesn't crash the run", async () => {
  const rows: StaleRow[] = [
    {
      id: "stale",
      status: "open",
      submitted_at: NOW - 90 * DAY,
      last_touched: null,
      waiting_days: 60,
    },
    {
      id: "money-out",
      status: "open",
      submitted_at: NOW - 90 * DAY,
      last_touched: null,
      waiting_days: 60,
    },
  ];
  const db = {
    storage() {
      throw new Error("expire-requests never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      if (args.p_request === "money-out") {
        return Promise.reject(
          new Error(
            "a payout to the payee is pending or sent; a person handles this request until it is returned",
          ),
        );
      }
      return Promise.resolve();
    },
  };
  const expired = await expireStaleRows(rows, NOW, db);
  assertEquals(expired, ["stale"]);
});

Deno.test("a fresh request never reaches the database at all", async () => {
  const log: string[] = [];
  const db = {
    storage() {
      throw new Error("expire-requests never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
  const fresh: StaleRow[] = [
    {
      id: "fresh",
      status: "open",
      submitted_at: NOW,
      last_touched: NOW,
      waiting_days: 60,
    },
  ];
  const expired = await expireStaleRows(fresh, NOW, db);
  assertEquals(expired, []);
  assertEquals(log, []);
});
