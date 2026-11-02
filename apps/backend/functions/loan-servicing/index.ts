// `loan-servicing`: pg_cron, daily. The job behind a borrower's autopay.
// Three decisions, kept pure where the decision is the job's and guarded
// functions where the write is the schema's:
//
//   * dueForCollection — an installment whose due date arrived gets collected
//     while its loan is still collecting (a paused installment or a
//     signed/forgiven/defaulted/repaid loan moves no money);
//   * the database owns the default check: `loan_default_due` is the view the
//     schema computes (three missed, a pause allowance used, loan not
//     paused by agreement), and this job calls apply_default_plan on what it
//     lists;
//   * ended pauses: the job calls resume_ended_pauses once; the schema
//     decides which loans' pauses ran out.
//   * agreements: the job calls finalize_signed_loan_agreements once per run;
//     the schema writes the written agreement for every loan both sides
//     signed that has none yet, and never rewrites one.

import { Db } from "../shared/rest.ts";

interface Installment {
  loan_id: string;
  seq: number;
  due_on: string;
  amount_cents: number;
  paid_cents: number;
  paused: boolean;
}

interface LoanRow {
  id: string;
  status: string;
}

/** A loan only moves money while it is still collecting. */
function isCollecting(status: string): boolean {
  return status === "active" || status === "paused";
}

/**
 * What to collect: due date reached (a `YYYY-MM-DD` string compares in
 * order), money still owed, installment not paused and its loan still
 * collecting. Order: loan then seq, so a loan's installments collect in turn.
 */
export function dueForCollection(
  installments: Installment[],
  loans: LoanRow[],
  now: string,
): { loanId: string; seq: number }[] {
  const collecting = loans.filter((loan) => isCollecting(loan.status));
  const ids = new Set<string>(collecting.map((loan) => loan.id));
  const due = installments.filter(
    (i) =>
      !i.paused && i.paid_cents < i.amount_cents && i.due_on <= now &&
      ids.has(i.loan_id),
  );
  due.sort((a, b) => {
    if (a.loan_id !== b.loan_id) return a.loan_id < b.loan_id ? -1 : 1;
    return a.seq - b.seq;
  });
  return due.map((i) => ({ loanId: i.loan_id, seq: i.seq }));
}

/** Record every due installment in full (autopay pays the payday amount). */
export async function collectDueInstallments(
  installments: Installment[],
  loans: LoanRow[],
  now: string,
  db: Db,
): Promise<number> {
  const due = dueForCollection(installments, loans, now);
  for (const row of due) {
    const installment = installments.find(
      (i) => i.loan_id === row.loanId && i.seq === row.seq,
    )!;
    await db.rpc("record_loan_payment", {
      p_loan: row.loanId,
      p_seq: row.seq,
      p_amount_cents: installment.amount_cents - installment.paid_cents,
    });
  }
  return due.length;
}

/** One call per loan the schema's `loan_default_due` view lists. */
export async function applyDueDefaultPlans(
  defaultDueLoanIds: string[],
  db: Db,
): Promise<string[]> {
  const applied: string[] = [];
  for (const loanId of defaultDueLoanIds) {
    try {
      await db.rpc("apply_default_plan", { p_loan: loanId });
      applied.push(loanId);
    } catch {
      // Someone changed this loan between reading and calling; next run is
      // right, the job doesn't crash over it.
    }
  }
  return applied;
}

/**
 * Write the agreement paperwork once per run: the schema sweeps exactly the
 * signed loans with no agreement yet (and replaying a finalized one is a
 * no-op), so this job only asks and reports how many were written.
 */
export async function finalizeLoanAgreements(db: Db): Promise<number> {
  const written = await db.rpc("finalize_signed_loan_agreements", {});
  return Number(written ?? 0);
}
