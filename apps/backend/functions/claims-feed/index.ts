// `claims-feed`: the insured insurer's claims feed. What this file owns is
// the event plumbing: the insurer records a deductible claim and, separately,
// confirms it was paid in full (LESS the member's share). Money the feed
// confirms as paid is journaled through the fund ledger: out of the partner
// side (the insurer), into `paid_out` (the shop got it). The row rules —
// paid = gross minus share, unique partner references, denials by a person —
// stay in the schema.

import { Db } from "../shared/rest.ts";

interface ClaimRecorded {
  requestId: string;
  partnerRef: string;
  grossCents: number;
  memberShareCents: number;
}

interface ClaimPaid {
  claimId: string;
  partnerRef: string;
  grossCents: number;
  memberShareCents: number;
}

export interface FeedEvent {
  event: "claim_recorded" | "claim_paid";
  fund: "protection" | "home_fund" | "people";
  claim?: ClaimRecorded | ClaimPaid;
}

/**
 * One journal per confirmed payment: the insurer's money, out of its side
 * and into paid-out, for exactly gross minus the member's share — the same
 * figure the schema stored on the row (a check enforces it there too).
 */
function paidLines(grossCents: number, memberShareCents: number): unknown[] {
  const paid = grossCents - memberShareCents;
  if (paid <= 0) {
    throw new Error(
      `an insured payment needs money to move: gross ${grossCents}, share ${memberShareCents}`,
    );
  }
  return [
    { code: "partner_cash", amount_cents: -paid },
    { code: "paid_out", amount_cents: paid },
  ];
}

export async function handleFeedEvent(event: FeedEvent, db: Db): Promise<void> {
  const claim = event.claim;
  if (claim === undefined) {
    throw new Error("a feed event needs the claim it carries");
  }
  switch (event.event) {
    case "claim_recorded": {
      const recorded = claim as ClaimRecorded;
      await db.rpc("record_claim", {
        p_request: recorded.requestId,
        p_partner_ref: recorded.partnerRef,
        p_gross_cents: recorded.grossCents,
        p_member_share_cents: recorded.memberShareCents,
      });
      return;
    }
    case "claim_paid": {
      const paid = claim as ClaimPaid;
      // The figures are checked before any write: a bad event leaves no half
      // a paid claim behind.
      const lines = paidLines(paid.grossCents, paid.memberShareCents);
      await db.rpc("mark_claim_paid", {
        p_claim: paid.claimId,
        p_partner_ref: paid.partnerRef,
      });
      await db.rpc("post_journal", {
        p_fund: event.fund,
        p_kind: "claim",
        p_ref: paid.claimId,
        p_partner_ref: paid.partnerRef,
        p_lines: lines,
      });
      return;
    }
  }
}
