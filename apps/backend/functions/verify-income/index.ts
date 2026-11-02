// `verify-income`: the member clicked "link my bank", the vendor read the
// income account (income only — never a password, never a transfer), and this
// function turns the vendor's report into an income check the schema stores.
// The stored check is what prices dues (`subscription_amount`).
//
//   * the vendor reports ANNUAL income; dues formulas are monthly, so the
//     conversion lives here and floors to whole cents;
//   * a report that carries a credential field is refused before anything is
//     written — the bank link reads income only;
//   * the vendor's own reference is required, so a bank-linked figure can be
//     traced back to the read that produced it.
//
// The write itself is `record_income_verification` (service-guarded): this
// function decides the figure, the schema owns the record.

import { Db } from "../shared/rest.ts";

interface IncomeReport {
  /** The vendor's annual income figure for the member. */
  annual_income_cents: number;
  /** The bank link's own reference for the read that produced the figure. */
  provider_ref: string;
  /** Field names the vendor touched; a credential field is refused. */
  fields: string[];
}

const CREDENTIAL_FIELDS = ["password", "login", "transfer", "account_id"];

/**
 * A monthly income figure from the vendor's annual one. Whole cents, floored
 * (an unproven fraction of income doesn't buy dues).
 */
export function monthlyIncomeCents(annualIncomeCents: number): number {
  if (annualIncomeCents < 0) {
    throw new Error(`income figures can't be negative: ${annualIncomeCents}`);
  }
  return Math.floor(annualIncomeCents / 12);
}

export async function recordIncomeCheck(
  memberId: string,
  report: IncomeReport,
  db: Db,
): Promise<boolean> {
  const touched = report.fields.map((field) => field.toLowerCase());
  const credential = CREDENTIAL_FIELDS.filter((name) => touched.includes(name));
  if (credential.length > 0) {
    // Nothing is written: a bank link that reports touching credentials is
    // refused, not trimmed — the figure is untrustworthy as a whole.
    throw new Error(
      `the bank link touched credential fields (${
        credential.join(", ")
      }): income only`,
    );
  }
  if (report.provider_ref === "") {
    throw new Error("a bank-linked income check needs the vendor's reference");
  }
  await db.rpc("record_income_verification", {
    p_member: memberId,
    p_method: "bank_link",
    p_monthly_income_cents: monthlyIncomeCents(report.annual_income_cents),
    p_provider_ref: report.provider_ref,
  });
  return true;
}
