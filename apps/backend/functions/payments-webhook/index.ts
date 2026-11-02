// `payments-webhook`: called by the payment partner when it confirms what
// happened to money the cooperative put in motion. Every write goes through a
// guarded service function — `capture_contributions`, `mark_refunded`,
// `report_payout`, `post_journal` — never a direct table write, so this
// function's word is bounded by those guards' own rules (they're idempotent
// for replayed webhooks; this function keeps to one journal per event).
//
// Events, as the partner's test mode sends them:
//   * charges_confirmed: the partner confirmed a funded request's charges.
//   * money_returned: one contribution's money came back to the partner (its
//     request ended unpaid). One refund journal per contribution: journals are
//     keyed by the partner's reference, so each refund is its own journal.
//   * payout_created: the console asked for a payout and the partner confirms
//     opening it — the row starts `pending`; money moves on `payout_reported`.
//   * payout_reported: a payout was sent, failed or came back.
//   * loan_repaid: a borrower returned money against a loan installment;
//     `record_loan_payment` owns the rules (collecting loans, owed ceiling).

import { Db } from "../shared/rest.ts";

interface ReturnLine {
  contributionId: string;
  partnerRef: string;
  amountCents: number;
}

interface PayoutReport {
  payoutId: string;
  outcome: "sent" | "failed" | "returned";
  partnerRef: string;
  amountCents: number;
}

interface PayoutCreation {
  payeeId: string;
  amountCents: number;
  invoiceEvidenceId: string;
  partnerRef: string;
}

interface LoanRepaid {
  loanId: string;
  seq: number;
  amountCents: number;
}

export interface ChargeEvent {
  event:
    | "charges_confirmed"
    | "money_returned"
    | "payout_created"
    | "payout_reported"
    | "loan_repaid";
  requestId: string;
  fund: "protection" | "home_fund" | "people";
  /** Only for charges_confirmed: nothing else is needed, capture reads the row. */
  returns?: ReturnLine[];
  payout?: PayoutReport;
  /** Only for loan_repaid: the installment the borrower returned. */
  repayment?: LoanRepaid;
  /** Only for payout_created: the payout the partner opens. */
  opening?: PayoutCreation;
}

/**
 * A journal needs at least two lines: money always records both sides, the
 * account it left and the account it entered — the codes are the fund's
 * seeded ledger accounts (`partner_cash`: money sitting with the payment
 * partner, `available`: the cooperative's money in the fund, `paid_out`:
 * money delivered to a payee).
 */
function transferLines(
  fromCode: string,
  toCode: string,
  amountCents: number,
): unknown[] {
  if (amountCents <= 0) {
    throw new Error(`money moving needs a positive amount: ${amountCents}`);
  }
  return [
    { code: fromCode, amount_cents: -amountCents },
    { code: toCode, amount_cents: amountCents },
  ];
}

export async function handleChargeEvent(
  event: ChargeEvent,
  db: Db,
): Promise<void> {
  switch (event.event) {
    case "charges_confirmed": {
      await db.rpc("capture_contributions", { p_request: event.requestId });
      return;
    }
    case "money_returned": {
      for (const line of event.returns ?? []) {
        // Amounts are checked before any write: a bad event leaves no half a
        // refund behind.
        if (line.amountCents <= 0) {
          throw new Error(
            `money moving needs a positive amount: ${line.amountCents}`,
          );
        }
        // The DB's answer is the figure it stored (`refunded_cents`, from
        // the `refunds_due` split); the journal mirrors that, never the
        // partner's word — a disagreement is refused loudly.
        const refunded = Number(
          await db.rpc("mark_refunded", {
            p_contribution: line.contributionId,
            p_partner_ref: line.partnerRef,
          }),
        );
        if (refunded !== line.amountCents) {
          throw new Error(
            `the partner's refund figure (${line.amountCents}) doesn't match the split (${refunded})`,
          );
        }
        // The refund journal says the money came back: out of the partner's
        // side, into the fund's own money.
        await db.rpc("post_journal", {
          p_fund: event.fund,
          p_kind: "refund",
          p_ref: line.contributionId,
          p_partner_ref: line.partnerRef,
          // Money back from the partner's side into the fund's own money.
          p_lines: transferLines("partner_cash", "available", line.amountCents),
        });
      }
      return;
    }
    case "loan_repaid": {
      const repaid = event.repayment;
      if (repaid === undefined) {
        throw new Error(
          "a loan-repayment event needs the installment it returns",
        );
      }
      if (repaid.amountCents <= 0) {
        throw new Error(
          `money moving needs a positive amount: ${repaid.amountCents}`,
        );
      }
      // The schema owns every rule here: only loans actually collecting,
      // and never more than the installment still owed. No journal: loan
      // money sits with the family, not on the payment partner's side.
      await db.rpc("record_loan_payment", {
        p_loan: repaid.loanId,
        p_seq: repaid.seq,
        p_amount_cents: repaid.amountCents,
      });
      return;
    }
    case "payout_created": {
      const creation = event.opening;
      if (creation === undefined) {
        throw new Error("a payout-created event needs the payout it opens");
      }
      // Opening is the schema's `create_payout`: idempotent by the partner
      // payout reference, guarded by the same rules the payout must honour
      // (funded request, named verified payee, final invoice, captured
      // ceiling). Nothing is journaled: a pending payout has moved no money.
      await db.rpc("create_payout", {
        p_request: event.requestId,
        p_payee: creation.payeeId,
        p_amount_cents: creation.amountCents,
        p_invoice_evidence: creation.invoiceEvidenceId,
        p_partner_ref: creation.partnerRef,
      });
      return;
    }
    case "payout_reported": {
      const report = event.payout;
      if (report === undefined) {
        throw new Error("a payout event needs the payout it reports");
      }
      if (report.outcome !== "failed") {
        // A payout that was sent or came back moved money through the payee;
        // a failed payout moved none, so there is no journal to write.
        await db.rpc("report_payout", {
          p_payout: report.payoutId,
          p_outcome: report.outcome,
        });
        // `sent` moved money to the payee (out of the fund's money, into
        // paid-out); `returned` moved it back the other way. A failed payout
        // moved no money, so there is no journal to write.
        await db.rpc("post_journal", {
          p_fund: event.fund,
          p_kind: "payout",
          p_ref: report.payoutId,
          p_partner_ref: report.partnerRef,
          p_lines: report.outcome === "sent"
            ? transferLines("available", "paid_out", report.amountCents)
            : transferLines("paid_out", "available", report.amountCents),
        });
      }
      return;
    }
  }
}
