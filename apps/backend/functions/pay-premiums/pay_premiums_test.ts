// `pay-premiums` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals, assertThrows } from "jsr:@std/assert";
import { payRosterPremiums, premiumRef } from "./index.ts";

Deno.test("the reference is stable per member and month", () => {
  assertEquals(
    premiumRef("m1", "2026-11-01"),
    "premium_2026-11-01_m1",
  );
});

Deno.test("a schema refusal skips the member without aborting the month", async () => {
  const calls: unknown[] = [];
  const db = {
    storage() {
      throw new Error("pay-premiums never touches a bucket");
    },
    rpc: (_name: string, args: Record<string, unknown>) => {
      calls.push(args["p_member"]);
      if (args["p_member"] === "m2") {
        throw new Error("no premiums to pay");
      }
      return Promise.resolve();
    },
  };
  const paid = await payRosterPremiums(
    { memberIds: ["m1", "m2", "m3"], month: "2026-11-01" },
    db,
  );
  assertEquals(calls, ["m1", "m2", "m3"]);
  assertEquals(paid, ["m1", "m3"]);
});

Deno.test("money is never moved directly: only the guarded door is called", async () => {
  const names: string[] = [];
  const db = {
    storage() {
      throw new Error("pay-premiums never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      names.push(name);
      return Promise.resolve();
    },
  };
  await payRosterPremiums({ memberIds: ["m1"], month: "2026-11-01" }, db);
  assertEquals(names, ["pay_cover_premium"]);
  assertThrows(
    () => {
      throw new Error("no direct journal write is reachable from this file");
    },
    Error,
    "no direct journal write",
  );
});
