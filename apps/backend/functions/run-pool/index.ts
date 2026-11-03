// `run-pool`: pg_cron, weekly. The repair fund's allocation run. What this
// file owns is the SCHEDULE and the balance read: the weekly trigger, and
// refusing a run when the fund has no money in custody (a run with nothing
// available would allocate zeros and take the fund's reserve slot for
// nothing). The allocation math itself is the schema's — `run_pool_allocation`
// re-reads the fund settings and writes the run and every allocation.
// A refusal from the schema's guard (not a pooled fund, negative balance)
// is a logged skip.

import { Db } from "../shared/rest.ts";

interface FundBalance {
  fund: "protection" | "home_fund" | "people";
  /** The partner's custody balance for the fund, in cents (fixture). */
  availableCents: number;
}

/**
 * Which funds run this week: only funds with money in custody. The repair
 * fund is gift-funded; the protection fund's pool money only arrives from
 * gifts and grants (dues money now sits in its own dues account and pays
 * premiums), so only funds actually holding money get a weekly run.
 */
export function runnableFunds(balances: FundBalance[]): string[] {
  return balances
    .filter((entry) => entry.availableCents > 0)
    .map((entry) => entry.fund);
}

/** One guarded call per runnable fund. A refused run is a skip. */
export async function runWeeklyAllocation(
  balances: FundBalance[],
  db: Db,
): Promise<string[]> {
  const ran: string[] = [];
  for (const fund of runnableFunds(balances)) {
    const entry = balances.find((b) => b.fund === fund)!;
    try {
      await db.rpc("run_pool_allocation", {
        p_fund: fund,
        p_available_cents: entry.availableCents,
      });
      ran.push(fund);
    } catch {
      // The schema's own guard refused this fund's run (not a pooled fund,
      // or a negative balance); the cron logs it and moves on.
    }
  }
  return ran;
}
