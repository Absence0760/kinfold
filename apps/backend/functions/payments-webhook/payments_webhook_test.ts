// `payments-webhook` unit tests (`pnpm test:edge`, no stack, no Docker). The
// `Db` is a fake that records calls; the rules pinned here are what one
// partner event must do and not do — capture is one call, a refund journals
// the REFUND amount (which can be less than a pledge), a failed payout moves
// no money and journals nothing, and every journal has the two-sided lines
// the ledger schema demands, on the fund's seeded account codes
// (`partner_cash`, `available`, `paid_out` — never codes the schema doesn't have).
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { handleChargeEvent } from "./index.ts";

/** A `Db` that refuses to touch buckets and records every rpc call. */
function recorder(log: string[], lines?: string[]) {
  return {
    storage() {
      throw new Error("payments-webhook never reads or writes a bucket");
    },
    // `mark_refunded` answers with the figure the schema stored; this fake
    // echoes what the caller asked for, unless overridden by `refundsDue`.
    rpc: (name: string, args: Record<string, unknown>): Promise<unknown> => {
      log.push(name);
      if (lines !== undefined && args.p_lines !== undefined) {
        lines.push(JSON.stringify(args.p_lines));
      }
      return Promise.resolve(args.p_amount_cents ?? null);
    },
  };
}

function refundRecorder(log: string[], journals: string[], due: number) {
  return {
    storage() {
      throw new Error("payments-webhook never reads or writes a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>): Promise<unknown> => {
      log.push(name);
      if (args.p_lines !== undefined) {
        journals.push(JSON.stringify(args.p_lines));
      }
      return Promise.resolve(name === "mark_refunded" ? due : null);
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

Deno.test("a refund journals the refund amount back into the fund", async () => {
  const log: string[] = [];
  const journals: string[] = [];
  const db = refundRecorder(log, journals, 23456);
  await handleChargeEvent(
    {
      event: "money_returned",
      requestId: "r1",
      fund: "people",
      returns: [
        { contributionId: "c1", partnerRef: "pr1", amountCents: 23456 },
      ],
    },
    db,
  );
  assertEquals(log, ["mark_refunded", "post_journal"]);
  // Codes are the fund's seeded accounts; money comes from the partner's
  // side and becomes the fund's own money again.
  assertEquals(
    journals,
    [JSON.stringify([
      { code: "partner_cash", amount_cents: -23456 },
      { code: "available", amount_cents: 23456 },
    ])],
  );
});

Deno.test("a partner figure that doesn't match the schema's split is refused", async () => {
  const log: string[] = [];
  const journals: string[] = [];
  const db = refundRecorder(log, journals, 10000);
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
            amountCents: 12345,
          }],
        },
        db,
      ),
    Error,
    "doesn't match the split",
  );
  // The refund itself went through; the journal that would mirror the wrong
  // figure was refused before writing.
  assertEquals(log, ["mark_refunded"]);
  assertEquals(journals, []);
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

Deno.test("a sent payout journals money out of the fund's money, into paid out", async () => {
  const log: string[] = [];
  const journals: string[] = [];
  const db = recorder(log, journals);
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
  assertEquals(
    journals,
    [JSON.stringify([
      { code: "available", amount_cents: -100000 },
      { code: "paid_out", amount_cents: 100000 },
    ])],
  );
});

Deno.test("a returned payout journals the money back the other way", async () => {
  const log: string[] = [];
  const journals: string[] = [];
  const db = recorder(log, journals);
  await handleChargeEvent(
    {
      event: "payout_reported",
      requestId: "r1",
      fund: "people",
      payout: {
        payoutId: "p1",
        outcome: "returned",
        partnerRef: "pr1",
        amountCents: 100000,
      },
    },
    db,
  );
  assertEquals(log, ["report_payout", "post_journal"]);
  assertEquals(
    journals,
    [JSON.stringify([
      { code: "paid_out", amount_cents: -100000 },
      { code: "available", amount_cents: 100000 },
    ])],
  );
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

// Payout opening (`payout_created`): the webhook calls `create_payout` once
// and journals NOTHING — a pending payout has moved no money.
Deno.test("a payout-created event opens one payout and journals no money", async () => {
  const rpcLog: string[] = [];
  const db = {
    storage() {
      throw new Error("payments-webhook never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve();
    },
  };
  const event = {
    event: "payout_created" as const,
    requestId: "req-1",
    fund: "protection" as const,
    opening: {
      payeeId: "payee-1",
      amountCents: 30000,
      invoiceEvidenceId: "inv-1",
      partnerRef: "po_1",
    },
  };
  await handleChargeEvent(event, db);
  assertEquals(rpcLog, ["create_payout"]);
});
// Loan repayment (`loan_repaid`): one guarded `record_loan_payment` call and
// no journal — loan money sits with the family, not on the partner's side.
Deno.test("a loan-repayment event calls record_loan_payment once and journals no money", async () => {
  const rpcLog: string[] = [];
  const db = {
    storage() {
      throw new Error("payments-webhook never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve(5000);
    },
  };
  const event = {
    event: "loan_repaid" as const,
    requestId: "req-1",
    fund: "protection" as const,
    repayment: { loanId: "loan-1", seq: 3, amountCents: 10000 },
  };
  await handleChargeEvent(event, db);
  assertEquals(rpcLog, ["record_loan_payment"]);
});

Deno.test("a repayment with zero money is refused before any call", async () => {
  const rpcLog: string[] = [];
  const db = {
    storage() {
      throw new Error("payments-webhook never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve(0);
    },
  };
  const event = {
    event: "loan_repaid" as const,
    requestId: "req-1",
    fund: "protection" as const,
    repayment: { loanId: "loan-1", seq: 3, amountCents: 0 },
  };
  assertRejects(
    async () => await handleChargeEvent(event, db),
    Error,
    "money moving needs a positive amount",
  );
  assertEquals(rpcLog, []);
});

// Dues capture (`dues_captured`): `capture_dues` answers with the figure the
// schema stored, and the journal moves exactly that number into the fund.
Deno.test("a dues-capture event closes the row and journals the DB figure", async () => {
  const journals: string[] = [];
  const db = {
    storage() {
      throw new Error("payments-webhook never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "capture_dues") {
        return Promise.resolve(4000);
      }
      if (name === "post_journal") {
        journals.push(JSON.stringify(args.p_lines));
      }
      return Promise.resolve();
    },
  };
  const event = {
    event: "dues_captured" as const,
    requestId: "req-1",
    fund: "protection" as const,
    dues: { paymentId: "pay-1", partnerRef: "dues_p1" },
  };
  await handleChargeEvent(event, db);
  assertEquals(journals, [
    JSON.stringify([
      { code: "partner_cash", amount_cents: -4000 },
      { code: "available", amount_cents: 4000 },
    ]),
  ]);
});
