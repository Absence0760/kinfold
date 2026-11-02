// `evidence-url`: the review console opens an original file for a request
// that needs a person. The rules here mirror the review rules the schema
// enforces elsewhere (self-review and same-region review are refused),
// because the URL is the only door through which an original leaves the
// member's folder:
//
//   * the reviewer isn't the requester and isn't in the requester's region
//     (regions compared as a boolean — the value never leaves the read);
//   * the URL is SHORT-LIVED (the review window is minutes, not a day);
//   * every issuing is audit-logged through `record_evidence_url`, so the
//     PII read leaves a trail.

import { Db } from "../shared/rest.ts";

interface RequestRow {
  id: string;
  member_id: string;
  region: string;
}

interface UrlIssuer {
  /** Mint a short-lived signed URL for a private bucket path. */
  issue(
    bucket: string,
    path: string,
    expiresInSeconds: number,
  ): Promise<string>;
}

const REVIEW_WINDOW_SECONDS = 15 * 60; // fifteen minutes, a review's length

/**
 * Issue the URL if the review rules allow it. Returns null when the pairing
 * is refused — a reviewer never sees an original they shouldn't, and nothing
 * is signed or audited for a refusal.
 */
export async function issueEvidenceUrl(
  requestId: string,
  reviewerId: string,
  path: string,
  request: RequestRow,
  reviewerRegion: string,
  issuer: UrlIssuer,
  db: Db,
): Promise<string | null> {
  if (request.member_id === reviewerId || request.region === reviewerRegion) {
    return null;
  }
  const url = await issuer.issue(
    "evidence-original",
    path,
    REVIEW_WINDOW_SECONDS,
  );
  await db.rpc("record_evidence_url", { p_request: requestId, p_path: path });
  return url;
}
