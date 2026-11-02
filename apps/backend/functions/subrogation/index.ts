// `subrogation`: the partner insurer's subrogation statements (roadmap 2g).
// When another driver is at fault, THEIR insurer should pay — Kinfold's
// deductible cover must not subsidise other insurers (design.md). The partner
// insurer claims the recovery right from the at-fault insurer and reports the
// money that moved; this file plumbs that statement to the schema, which
// records it ALREADY verified and subtracts it from pledge caps and pool
// needs. The money never touches Kinfold's ledger: it moved between insurers.

import { Db } from "../shared/rest.ts";

export interface SubrogationStatement {
  requestId: string;
  amountCents: number;
  /** The day the money moved, yyyy-mm-dd. */
  on: string;
  /** The partner's reference for the claim: what makes the money traceable. */
  partnerRef: string;
  note?: string;
}

/**
 * A statement without a reference or with no money to move is refused BEFORE
 * any write: a bad webhook leaves no half a recovery behind.
 */
export async function handleSubrogationStatement(
  statement: SubrogationStatement,
  db: Db,
): Promise<void> {
  if (statement.partnerRef === "") {
    throw new Error(
      "a subrogation statement needs the partner's reference for the claim",
    );
  }
  if (statement.amountCents <= 0) {
    throw new Error(
      `a subrogation statement needs money to move: ${statement.amountCents}`,
    );
  }
  await db.rpc("record_partner_recovery", {
    p_request: statement.requestId,
    p_source: "insurance",
    p_amount_cents: statement.amountCents,
    p_on: statement.on,
    p_partner_ref: statement.partnerRef,
    p_note: statement.note ?? null,
  });
}
