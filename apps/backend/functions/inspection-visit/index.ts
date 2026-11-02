// `inspection-visit`: the partner's in-person inspection statements (roadmap 2f).
// A big request (at or above the fund's large-amount line, a rule the schema
// owns) needs a person the partner sends to visit the shop; this file plumbs
// that visit's report to the schema, which records it append-only and keeps a
// large request short of funding until a visit reports it clear. Nothing here
// decides what the visit found, and money is never moved from this file.

import { Db } from "../shared/rest.ts";

export interface VisitStatement {
  requestId: string;
  result: "clear" | "issue_found" | "inconclusive";
  inspectorRef: string;
  note?: string;
}

/**
 * A statement without a reference cannot be filed: a visit that cannot be
 * traced to the person who made it would leave a record no operator could check.
 */
export async function handleVisitStatement(
  statement: VisitStatement,
  db: Db,
): Promise<void> {
  if (statement.inspectorRef === "") {
    throw new Error(
      "an inspection statement needs the inspector's reference",
    );
  }
  await db.rpc("record_inspection", {
    p_request: statement.requestId,
    p_result: statement.result,
    p_inspector_ref: statement.inspectorRef,
    p_note: statement.note ?? null,
  });
}
