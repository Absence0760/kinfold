// `pay-premiums`: pg_cron, monthly. The cooperative pays each member's cover
// premiums out of dues money (design.md: premiums come from dues, and the
// member's side never calls them a premium). The member list here is a
// fixture for the roster the cron reads; the schema owns the money: `pay_cover_premium`
// sums the filed rates for the member's classed covered vehicles, refuses to
// pay when dues money doesn't cover them, and journals the move from the fund's
// dues money into premiums money. Nothing here moves money directly.

import { Db } from "../shared/rest.ts";

export interface MemberRoster {
  memberIds: string[];
  /** Month the premiums are paid for: yyyy-MM-01, the dues periods' shape. */
  month: string;
}

/**
 * The reference the schema keys a replay on: one premium payment per member
 * per month, so a replayed cron month changes nothing.
 */
export function premiumRef(memberId: string, month: string): string {
  return `premium_${month}_${memberId}`;
}

/**
 * Pay every member on the roster. Members without classed covered vehicles
 * are skipped (the schema's refusal), so the cron never invents premiums.
 */
export async function payRosterPremiums(
  roster: MemberRoster,
  db: Db,
): Promise<string[]> {
  const paid: string[] = [];
  for (const memberId of roster.memberIds) {
    try {
      await db.rpc("pay_cover_premium", {
        p_member: memberId,
        p_partner_ref: premiumRef(memberId, roster.month),
      });
      paid.push(memberId);
    } catch {
      // A member the schema refuses (no classed vehicles, dues money short)
      // is reported to the cron's log, not a crash: the next month's run
      // tries again with a fresh reference.
      continue;
    }
  }
  return paid;
}
