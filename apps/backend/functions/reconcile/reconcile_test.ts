// `reconcile` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { FundCode, monthToPublish, reconcileBooks } from "./index.ts";

const DAY = 24 * 60 * 60 * 1000;

Deno.test("mid-November: October has not passed its settlement lag yet", () => {
  const now = new Date(Date.UTC(2026, 10, 2)); // Nov 2
  assertEquals(monthToPublish(now), null);
});

Deno.test("November 8 publishes October: one day past the lag", () => {
  const now = new Date(Date.UTC(2026, 10, 8)); // Nov 8
  assertEquals(monthToPublish(now), "2026-10-01");
});

Deno.test("January publishes the previous December", () => {
  const now = new Date(Date.UTC(2027, 0, 15)); // Jan 15
  assertEquals(monthToPublish(now), "2026-12-01");
});

Deno.test("due month publishes once and differences are reported", async () => {
  const rpcLog: string[] = [];
  const balances: Record<string, number> = { "protection/partner_cash": -800 };
  const db = {
    storage() {
      throw new Error("reconcile never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcLog.push(name);
      if (name === "ledger_balance") {
        const key = `${args.p_fund}/${args.p_code}`;
        return Promise.resolve(balances[key] ?? 0);
      }
      return Promise.resolve();
    },
  };
  const now = new Date(Date.UTC(2026, 10, 8));
  const statements: FundCode[] = [
    { fund: "protection", code: "partner_cash", amountCents: -800 },
    { fund: "protection", code: "available", amountCents: 999 },
  ];
  const result = await reconcileBooks(now, statements, db);
  assertEquals(result.published, "2026-10-01");
  assertEquals(result.differences, [
    "protection/available: statement 999, ledger 0",
  ]);
});

Deno.test("an already-published month is a skip, not a crash", async () => {
  const db = {
    storage() {
      throw new Error("reconcile never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      if (name === "publish_open_books") {
        return Promise.reject(new Error("duplicate key"));
      }
      return Promise.resolve(0);
    },
  };
  const now = new Date(Date.UTC(2026, 10, 8));
  const result = await reconcileBooks(now, [], db);
  assertEquals(result.published, null);
  assertEquals(result.differences, []);
});

Deno.test("money is never moved from here: no journal calls at all", async () => {
  const rpcLog: string[] = [];
  const db = {
    storage() {
      throw new Error("reconcile never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve(name === "ledger_balance" ? 0 : null);
    },
  };
  const now = new Date(Date.UTC(2026, 10, 8));
  await reconcileBooks(now, [{
    fund: "people",
    code: "available",
    amountCents: 0,
  }], db);
  assertEquals(rpcLog.filter((name) => name === "post_journal"), []);
});
