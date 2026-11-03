// `payments-webhook`: called by the payment partner when it confirms what
// happened to money the cooperative put in motion. Every write goes through a
// guarded service function — `record_charge_confirmation`, `mark_refunded`,
// `report_payout`, `post_journal` — never a direct table write, so this
// function's word is bounded by those guards' own rules (they're idempotent
// for replayed webhooks; this function keeps to one journal per event).
//
// Events, as the partner's test mode sends them:
//   * charges_confirmed: the partner confirmed a funded request's charges.
//     `record_charge_confirmation` owns the capture AND the journal in one
//     transaction: the pledges flip to captured and their money moves from
//     the partner's side into the fund's `available` account, the account
//     the pool allocates from - money is never captured without its ledger
//     entry, and the figure journaled is the schema's own pledged sum.
//   * money_returned: one contribution's money came back to the partner (its
//     request ended unpaid). One refund journal per contribution: journals are
//     keyed by the partner's reference, so each refund is its own journal.
//   * payout_created: the console asked for a payout and the partner confirms
//     opening it — the row starts `pending`; money moves on `payout_reported`.
//   * payout_reported: a payout was sent, failed or came back.
//   * loan_repaid: a borrower returned money against a loan installment;
//     `record_loan_payment` owns the rules (collecting loans, owed ceiling).
//   * dues_captured: the partner confirmed a member's monthly dues charge;
//     `capture_dues` owns the row, the journal moves the money to the dues
//     account (it pays premiums, it never buys a pool grant).
//   * fund_loan_disbursed: the lending Fund's partner handed a fund loan its
//     money; `activate_fund_loan` owns the status, audit trails the statement.
//   * fund_loan_paid: the borrower returned money to the Fund; `record_fund_loan_payment`
//     owns the schedule or income-cap rules. No journal: fund loan money sits
//     with the lending Fund, not on this partner's side.

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

interface DuesCaptured {
  paymentId: string;
  partnerRef: string;
}

interface FundLoanEvent {
  loanId: string;
  /** Month number of the payment (income schedules count months too). */
  seq?: number;
  amountCents?: number;
}

export interface ChargeEvent {
  event:
    | "charges_confirmed"
    | "money_returned"
    | "payout_created"
    | "payout_reported"
    | "loan_repaid"
    | "dues_captured"
    | "fund_loan_disbursed"
    | "fund_loan_paid";
  requestId: string;
  fund: "protection" | "home_fund" | "people";
  /** Only for charges_confirmed: the reference the capture journal replays against. */
  partnerRef?: string;
  /** Only for money_returned: the refunds the partner sent back. */
  returns?: ReturnLine[];
  payout?: PayoutReport;
  /** Only for loan_repaid: the installment the borrower returned. */
  repayment?: LoanRepaid;
  /** Only for dues_captured: the dues payment the partner confirmed. */
  dues?: DuesCaptured;
  /** Only for fund loan events: the loan the partner is acting on. */
  fundLoan?: FundLoanEvent;
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
      if (event.partnerRef === undefined) {
        throw new Error(
          "a charge confirmation needs the partner\'s reference for its journal",
        );
      }
      // One door owns both halves: `record_charge_confirmation` captures the
      // pledges and journals their money in the same transaction, so money is
      // never captured without its ledger entry. The figure is the schema\'s
      // own pledged sum, never the partner\'s word.
      await db.rpc("record_charge_confirmation", {
        p_request: event.requestId,
        p_partner_ref: event.partnerRef,
      });
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
    case "dues_captured": {
      const dues = event.dues;
      if (dues === undefined) {
        throw new Error("a dues-capture event needs the payment it confirms");
      }
      // The DB's answer is the figure the schema stored on the row; the
      // journal mirrors that number, moving it from the partner's side
      // (pending charges sit there) into the fund's dues account — dues money
      // pays premiums and never buys a pool grant.
      const amountCents = Number(
        await db.rpc("capture_dues", {
          p_payment: dues.paymentId,
          p_partner_ref: dues.partnerRef,
        }),
      );
      await db.rpc("post_journal", {
        p_fund: event.fund,
        p_kind: "dues",
        p_ref: dues.paymentId,
        p_partner_ref: dues.partnerRef,
        p_lines: transferLines("partner_cash", "dues", amountCents),
      });
      return;
    }
    case "fund_loan_disbursed": {
      const loan = event.fundLoan;
      if (loan === undefined) {
        throw new Error(
          "a fund-loan disbursement event needs the loan it opens",
        );
      }
      // Money moving is the partner's statement: the schema refuses to
      // activate a loan that isn't signed and awaiting it.
      await db.rpc("activate_fund_loan", { p_loan: loan.loanId });
      return;
    }
    case "fund_loan_paid": {
      const loan = event.fundLoan;
      if (
        loan === undefined || loan.seq === undefined ||
        loan.amountCents === undefined
      ) {
        throw new Error(
          "a fund-loan payment event needs the loan, month and amount",
        );
      }
      if (loan.amountCents <= 0) {
        throw new Error(
          `money moving needs a positive amount: ${loan.amountCents}`,
        );
      }
      // The schema owns every rule here: collecting loans, the owed ceiling
      // on monthly schedules, and income payments capped at the month's
      // income share. No journal: fund loan money sits with the lending Fund.
      await db.rpc("record_fund_loan_payment", {
        p_loan: loan.loanId,
        p_seq: loan.seq,
        p_amount_cents: loan.amountCents,
      });
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
