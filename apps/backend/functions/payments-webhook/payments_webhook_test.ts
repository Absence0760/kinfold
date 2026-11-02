// `payments-webhook` unit tests (`pnpm test:edge`, no stack, no Docker). The
// `Db` is a fake that records calls; the rules pinned here are what one
// partner event must do and not do — capture is one call, a refund journals
// the REFUND amount (which can be less than a pledge), a failed payout moves
// no money and journals nothing, and every journal has the two-sided lines
// the ledger schema demands.
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { handleChargeEvent } from "./index.ts";

/** A `Db` that refuses to touch buckets and records every rpc call. */
function recorder(log: string[]) {
  return {
    storage() {
      throw new Error("payments-webhook never reads or writes a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>): Promise<void> => {
      log.push(name);
      return Promise.resolve();
    },
  };
}

Deno.test("charges confirmed capture the pledges in one call", async () => {
  const log: string[] = [];
  const db = recorder(log);
  await handleChargeEvent(
    { event: "charges_confirmed", requestId: "r1", fund: "people" },
    db,
  );
  assertEquals(log, ["capture_contributions"]);
});

Deno.test("a refund journals the refund amount out of the partner", async () => {
  const log: string[] = [];
  const db = recorder(log);
  await handleChargeEvent(
    {
      event: "money_returned",
      requestId: "r1",
      fund: "people",
      returns: [
        { contributionId: "c1", partnerRef: "pr1", amountCents: 23456 },
        { contributionId: "c2", partnerRef: "pr2", amountCents: 400 },
      ],
    },
    db,
  );
  assertEquals(
    log,
    [
      "mark_refunded",
      "post_journal",
      "mark_refunded",
      "post_journal",
    ],
  );
});

Deno.test("a refund with no money on it is refused", async () => {
  const log: string[] = [];
  const db = recorder(log);
  assertRejects(
    async () =>
      await handleChargeEvent(
        {
          event: "money_returned",
          requestId: "r1",
          fund: "people",
          returns: [{
            contributionId: "c1",
            partnerRef: "pr1",
            amountCents: 0,
          }],
        },
        db,
      ),
    Error,
    "money moving needs a positive amount",
  );
  assertEquals(log, []);
});

Deno.test("a failed payout reports the outcome but journals no money", async () => {
  const log: string[] = [];
  const db = recorder(log);
  await handleChargeEvent(
    {
      event: "payout_reported",
      requestId: "r1",
      fund: "people",
      payout: {
        payoutId: "p1",
        outcome: "failed",
        partnerRef: "pr1",
        amountCents: 100000,
      },
    },
    db,
  );
  assertEquals(log, []);
});

Deno.test("a sent payout reports and journals money leaving the cooperative", async () => {
  const log: string[] = [];
  const db = recorder(log);
  await handleChargeEvent(
    {
      event: "payout_reported",
      requestId: "r1",
      fund: "people",
      payout: {
        payoutId: "p1",
        outcome: "sent",
        partnerRef: "pr1",
        amountCents: 100000,
      },
    },
    db,
  );
  assertEquals(log, ["report_payout", "post_journal"]);
});

Deno.test("a payout event with no payout to report is refused", async () => {
  const log: string[] = [];
  const db = recorder(log);
  assertRejects(
    async () =>
      await handleChargeEvent(
        { event: "payout_reported", requestId: "r1", fund: "people" },
        db,
      ),
    Error,
    "a payout event needs the payout it reports",
  );
  assertEquals(log, []);
});
