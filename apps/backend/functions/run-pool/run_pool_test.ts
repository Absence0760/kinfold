// `run-pool` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { runnableFunds, runWeeklyAllocation } from "./index.ts";

Deno.test("only funds with money in custody run", () => {
  const funds = runnableFunds([
    { fund: "protection", availableCents: 500000 },
    { fund: "home_fund", availableCents: 0 },
    { fund: "people", availableCents: 120000 },
  ]);
  assertEquals(funds, ["protection", "people"]);
});

Deno.test("an empty fund never reaches the schema", async () => {
  const rpcLog: string[] = [];
  const db = {
    storage() {
      throw new Error("run-pool never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve();
    },
  };
  const ran = await runWeeklyAllocation(
    [{ fund: "home_fund", availableCents: 0 }],
    db,
  );
  assertEquals(ran, []);
  assertEquals(rpcLog, []);
});

Deno.test("each runnable fund gets exactly one guarded call", async () => {
  const rpcLog: string[] = [];
  const calls: string[] = [];
  const db = {
    storage() {
      throw new Error("run-pool never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcLog.push(name);
      calls.push(`${args.p_fund}:${args.p_available_cents}`);
      return Promise.resolve();
    },
  };
  const ran = await runWeeklyAllocation(
    [
      { fund: "protection", availableCents: 500000 },
      { fund: "people", availableCents: 120000 },
    ],
    db,
  );
  assertEquals(ran, ["protection", "people"]);
  assertEquals(
    calls,
    ["protection:500000", "people:120000"],
  );
});

Deno.test("a refused run from the schema guard skips, not crashes", async () => {
  const db = {
    storage() {
      throw new Error("run-pool never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) =>
      args.p_fund === "protection"
        ? Promise.reject(new Error("available balance cannot be negative"))
        : Promise.resolve(),
  };
  const ran = await runWeeklyAllocation(
    [
      { fund: "protection", availableCents: 500000 },
      { fund: "people", availableCents: 120000 },
    ],
    db,
  );
  assertEquals(ran, ["people"]);
});
