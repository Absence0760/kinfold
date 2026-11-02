// `verify-income` unit tests (`pnpm test:edge`, no stack, no Docker). The `Db`
// is a fake that records calls. Rules pinned: annual income becomes a floored
// monthly figure; a credential-touching report is refused before any write;
// and a bank-linked check carries the vendor's reference.
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { monthlyIncomeCents, recordIncomeCheck } from "./index.ts";

function recorder(log: string[]) {
  return {
    storage() {
      throw new Error("verify-income never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
}

Deno.test("annual income becomes a floored monthly figure", () => {
  assertEquals(monthlyIncomeCents(5400000), 450000);
  assertEquals(monthlyIncomeCents(5400001), 450000);
  assertEquals(monthlyIncomeCents(0), 0);
});

Deno.test("a negative income figure is refused", () => {
  assertRejects(
    () => {
      try {
        monthlyIncomeCents(-1);
      } catch (error) {
        return Promise.reject(error);
      }
      return Promise.resolve();
    },
    Error,
    "income figures can't be negative",
  );
});

Deno.test("a clean report posts the monthly figure and the vendor ref", async () => {
  const log: string[] = [];
  const calls: string[] = [];
  const db = {
    storage: () => {
      throw new Error("verify-income never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      log.push(name);
      calls.push(JSON.stringify(args));
      return Promise.resolve();
    },
  };
  const done = await recordIncomeCheck(
    "member-1",
    {
      annual_income_cents: 5400000,
      provider_ref: "bank-ref-1",
      fields: ["income"],
    },
    db,
  );
  assertEquals(done, true);
  assertEquals(log, ["record_income_verification"]);
  assertEquals(
    calls,
    [
      JSON.stringify({
        p_member: "member-1",
        p_method: "bank_link",
        p_monthly_income_cents: 450000,
        p_provider_ref: "bank-ref-1",
      }),
    ],
  );
});

Deno.test("a report that touched a credential writes nothing", async () => {
  const log: string[] = [];
  const db = {
    storage: () => {
      throw new Error("verify-income never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
  assertRejects(
    async () =>
      await recordIncomeCheck(
        "member-1",
        {
          annual_income_cents: 5400000,
          provider_ref: "bank-ref-1",
          fields: ["Income", "PASSWORD"],
        },
        db,
      ),
    Error,
    "income only",
  );
  assertEquals(log, []);
});

Deno.test("a bank-linked report with no vendor reference writes nothing", async () => {
  const log: string[] = [];
  const db = {
    storage: () => {
      throw new Error("verify-income never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
  assertRejects(
    async () =>
      await recordIncomeCheck(
        "member-1",
        { annual_income_cents: 5400000, provider_ref: "", fields: ["income"] },
        db,
      ),
    Error,
    "needs the vendor's reference",
  );
  assertEquals(log, []);
});
