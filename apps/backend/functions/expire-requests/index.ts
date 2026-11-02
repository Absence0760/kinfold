// `expire-requests`: pg_cron, daily. A request nobody tends goes stale and
// expires — which releases its pledges and cancels unsigned loans through the
// existing close trigger, the same path a withdrawal takes. What the cron
// decides and what the database enforces split cleanly:
//
//   * the cron decides STALENESS (this file): a request is stale once its
//     newest pledge (open) or newest evidence (needs_evidence) — its
//     `last_touched` — sits `fund_settings.waiting_days` in the past.
//   * the database enforces the rest (`expire_request`, service-guarded):
//     only open/needs-evidence move, and the payout guard keeps money with
//     the payee a person's, so a guarded skip is a catch, not a crash.

import { Db } from "../shared/rest.ts";

const DAY_MS = 24 * 60 * 60 * 1000;

export interface StaleRow {
  id: string;
  status: "open" | "needs_evidence";
  submitted_at: number;
  /** The pledge/evidence newest since submission; `null` when there is none. */
  last_touched: number | null;
  waiting_days: number;
}

/**
 * A request is stale once nothing touched it for its fund's waiting period:
 * the newest activity — the submission itself if nothing ever followed —
 * sits `waiting_days` in the past. `waiting_days = 0` makes everything stale
 * at once; that's a setting, not a special case.
 */
export function isStale(row: StaleRow, now: number): boolean {
  const lastSeen = row.last_touched ?? row.submitted_at;
  return now - lastSeen >= row.waiting_days * DAY_MS;
}

/** Ids to expire, in row order. A refused move (the payout guard) is a skip. */
export async function expireStaleRows(
  rows: StaleRow[],
  now: number,
  db: Db,
): Promise<string[]> {
  const expired: string[] = [];
  for (const row of rows) {
    if (!isStale(row, now)) {
      continue;
    }
    try {
      await db.rpc("expire_request", { p_request: row.id });
      expired.push(row.id);
    } catch {
      // The guard said this one belongs to a person; the job moves on.
    }
  }
  return expired;
}
