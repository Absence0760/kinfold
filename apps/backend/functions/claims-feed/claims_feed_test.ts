// `claims-feed` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { handleFeedEvent } from "./index.ts";

Deno.test("recorded claims reach record_claim once, no journal yet", async () => {
  const log: string[] = [];
  const db = {
    storage() {
      throw new Error("claims-feed never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
  const event = {
    event: "claim_recorded" as const,
    fund: "protection" as const,
    claim: {
      requestId: "req-1",
      partnerRef: "ins_c1",
      grossCents: 40000,
      memberShareCents: 1000,
    },
  };
  await handleFeedEvent(event, db);
  assertEquals(log, ["record_claim"]);
});

Deno.test("a paid claim closes the row and journals gross minus share", async () => {
  const journals: string[] = [];
  const log: string[] = [];
  const db = {
    storage() {
      throw new Error("claims-feed never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      log.push(name);
      if (name === "post_journal") journals.push(JSON.stringify(args.p_lines));
      return Promise.resolve();
    },
  };
  const event = {
    event: "claim_paid" as const,
    fund: "protection" as const,
    claim: {
      claimId: "cl-1",
      partnerRef: "pay_evt_1",
      grossCents: 40000,
      memberShareCents: 1000,
    },
  };
  await handleFeedEvent(event, db);
  assertEquals(log, ["mark_claim_paid", "post_journal"]);
  assertEquals(journals, [
    JSON.stringify([
      { code: "partner_cash", amount_cents: -39000 },
      { code: "paid_out", amount_cents: 39000 },
    ]),
  ]);
});

Deno.test("a claim whose whole gross is the member's share writes nothing", async () => {
  const log: string[] = [];
  const db = {
    storage() {
      throw new Error("claims-feed never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
  assertRejects(
    async () =>
      await handleFeedEvent(
        {
          event: "claim_paid" as const,
          fund: "protection" as const,
          claim: {
            claimId: "cl-1",
            partnerRef: "p",
            grossCents: 5000,
            memberShareCents: 5000,
          },
        },
        db,
      ),
    Error,
    "an insured payment needs money to move",
  );
  assertEquals(log, []);
});

Deno.test("a feed event with no claim is refused", async () => {
  const db = {
    storage() {
      throw new Error("no bucket");
    },
    rpc: (_name: string, _args: Record<string, unknown>) => Promise.resolve(),
  };
  assertRejects(
    async () =>
      await handleFeedEvent({ event: "claim_paid", fund: "protection" }, db),
    Error,
    "a feed event needs the claim it carries",
  );
});
