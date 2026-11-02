// `reconcile`: pg_cron, daily. Two jobs of this file, both honest about what
// stands in:
//
//   * publish the open books for the month that ended over a week ago
//     (`publish_open_books` owns the rules: a week's settlement lag, one
//     publish per month). A payout returned after its month was published
//     stays counted in THAT month — corrections land in the NEXT month's
//     numbers when the return arrives; republishing never happens, so this
//     file only ever asks for the newest ended month;
//   * compare each fund-level ledger account (`ledger_balance`) with the
//     partner's statement of the same account. The statements here are a
//     fixture; the partner's feed is what swaps in. Differences are REPORTED
//     to the caller (the cron's log) — money is never moved from here.

import { Db } from "../shared/rest.ts";

const DAY_MS = 24 * 60 * 60 * 1000;
const SETTLEMENT_LAG_DAYS = 7; // publish_open_books' own rule, kept in step.

export interface FundCode {
  fund: "protection" | "home_fund" | "people";
  code: string;
  /** The partner's statement of the same fund-level account, in cents. */
  amountCents: number;
}

/**
 * The month to publish: the last month that ENDED over a week ago (UTC
 * month edges, the same ones publish_open_books uses). `now` is a UTC
 * Date; returns the first day of that month, or null while no month is due
 * yet (mid-November still waits for October's lag to pass).
 */
export function monthToPublish(now: Date): string | null {
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth(); // 0-based
  const monthStart = new Date(Date.UTC(year, month, 1));
  const ended =
    now.valueOf() - monthStart.valueOf() >= SETTLEMENT_LAG_DAYS * DAY_MS;
  if (!ended) {
    return null;
  }
  const prevStart = new Date(Date.UTC(year, month - 1, 1));
  return toYyyyMmDd(prevStart);
}

function toYyyyMmDd(d: Date): string {
  const m = `${d.getUTCMonth() + 1}`.padStart(2, "0");
  const day = `${d.getUTCDate()}`.padStart(2, "0");
  return `${d.getUTCFullYear()}-${m}-${day}`;
}

/**
 * Publish if due, and report the ledger's differences against the partners'
 * statements. Already-published months (the schema refuses a second row per
 * fund per month) and months not yet due are skips, not crashes.
 */
export async function reconcileBooks(
  now: Date,
  partnerStatements: FundCode[],
  db: Db,
): Promise<{ published: string | null; differences: string[] }> {
  let published: string | null = null;
  const month = monthToPublish(now);
  if (month !== null) {
    try {
      await db.rpc("publish_open_books", { p_month: month });
      published = month;
    } catch {
      // Already published (a replayed cron day) or the lag refuses it: the
      // books stay as the schema wrote them.
    }
  }
  const differences: string[] = [];
  for (const entry of partnerStatements) {
    const schemaCents = Number(
      await db.rpc("ledger_balance", {
        p_fund: entry.fund,
        p_code: entry.code,
      }),
    );
    // Statements carry the partner's figure for the same account.
    const statementCents = entry.amountCents;
    if (schemaCents === statementCents) {
      continue;
    }
    differences.push(
      `${entry.fund}/${entry.code}: statement ${statementCents}, ledger ${schemaCents}`,
    );
    // The alert is also RECORDED (append-only, audit-logged), not just a
    // log line: an operator can find it later. Money is never moved here.
    try {
      await db.rpc("record_ledger_difference", {
        p_fund: entry.fund,
        p_code: entry.code,
        p_statement_cents: statementCents,
        p_ledger_cents: schemaCents,
      });
    } catch {
      // A replayed cron day or a refused write: the log line still says it.
    }
  }
  return { published, differences };
}
