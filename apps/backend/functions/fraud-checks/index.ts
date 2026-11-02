// `fraud-checks`: triggered by evidence and request events. Today it runs the
// duplicate-photo check: a photo whose perceptual hash matches a photo on a
// DIFFERENT request means the same picture was reused — money on someone else's
// damage — so a high-severity signal goes to the console, where a person decides.
// Cross-request, cross-vehicle and cross-shop patterns are fraud v2 (roadmap
// 2f) and join this file when they're built.
//
// The signal itself is written only through `record_fraud_signal` (service-only
// and audit-logged); this file decides WHEN to flag, the database owns the flag.

import { Db } from "../shared/rest.ts";

interface NewEvidence {
  id: string;
  request_id: string;
  perceptual_hash: string | null;
}

interface ExistingEvidence {
  request_id: string;
  perceptual_hash: string;
}

/**
 * A reuse flag: the new photo's perceptual hash matches an older photo on a
 * different request. A row without a perceptual hash (redaction not run yet)
 * can match nothing — no signal, and nothing to accuse.
 */
export function duplicatePhotoSignals(
  fresh: NewEvidence,
  existing: ExistingEvidence[],
): {
  detail: unknown;
}[] {
  if (fresh.perceptual_hash === null) {
    return [];
  }
  return existing
    .filter((row) => row.perceptual_hash === fresh.perceptual_hash)
    .filter((row) => row.request_id !== fresh.request_id)
    .map((row) => ({
      detail: {
        matched_request: row.request_id,
        matched_evidence_hash: row.perceptual_hash,
        new_evidence: fresh.id,
      },
    }));
}

/**
 * Flag every reuse the check found. One signal per match: the same picture
 * reused on three requests is three signals, each its own decision trail.
 */
export async function flagDuplicatePhotos(
  fresh: NewEvidence,
  existing: ExistingEvidence[],
  db: Db,
): Promise<number> {
  const signals = duplicatePhotoSignals(fresh, existing);
  for (const signal of signals) {
    await db.rpc("record_fraud_signal", {
      p_request: fresh.request_id,
      p_kind: "duplicate_photo",
      p_severity: "high",
      p_detail: signal.detail,
    });
  }
  return signals.length;
}
