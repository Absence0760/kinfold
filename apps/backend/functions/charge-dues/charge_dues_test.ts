// `charge-dues` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { collectDues, dueForDues, duesPeriodFor } from "./index.ts";

Deno.test("the dues period is the month the run fires in", () => {
  assertEquals(duesPeriodFor(new Date(Date.UTC(2026, 10, 3))), "2026-11-01");
});

Deno.test("only active, non-$0, not-yet-charged subscriptions are due", () => {
  const subs = [
    { id: "s1", member_id: "m1", monthly_cents: 4000, ends_on: null },
    { id: "s2", member_id: "m2", monthly_cents: 6000, ends_on: null },
    { id: "s3", member_id: "m3", monthly_cents: 0, ends_on: null },
    { id: "s4", member_id: "m4", monthly_cents: 5000, ends_on: "2026-09-01" },
  ];
  const payments = [{ subscription_id: "s1", period: "2026-11-01" }];
  assertEquals(dueForDues(subs, payments, "2026-11-01"), ["m2"]);
});

Deno.test("each due member gets exactly one guarded ask", async () => {
  const calls: string[] = [];
  const read = (table: string, params: Record<string, string>) =>
    table === "subscriptions"
      ? Promise.resolve([
        { id: "s1", member_id: "m1", monthly_cents: 4000, ends_on: null },
      ] as unknown[])
      : Promise.resolve([] as unknown[]);
  const rpc = {
    call: (name: string, args: Record<string, unknown>) => {
      calls.push(`${args.p_member}@${args.p_period}`);
      return undefined;
    },
  };
  const now = new Date(Date.UTC(2026, 10, 3));
  const asked = await collectDues(now, read, rpc);
  assertEquals(asked, ["m1"]);
  assertEquals(calls, ["m1@2026-11-01"]);
});

Deno.test("a schema refusal skips the run, not a crash", async () => {
  const rpc = {
    call: (_name: string, _args: Record<string, unknown>) => {
      throw new Error("member not found or not active");
    },
  };
  const read = (table: string, _params: Record<string, string>) =>
    table === "subscriptions"
      ? Promise.resolve([
        { id: "s1", member_id: "m1", monthly_cents: 4000, ends_on: null },
      ] as unknown[])
      : Promise.resolve([] as unknown[]);
  const now = new Date(Date.UTC(2026, 10, 3));
  const asked = await collectDues(now, read, rpc);
  assertEquals(asked, []);
});
