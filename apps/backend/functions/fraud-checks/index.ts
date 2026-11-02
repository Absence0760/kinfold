// `fraud-checks`: triggered by evidence and request events. Today it runs the
// duplicate-photo check: a photo whose perceptual hash matches a photo on a
// DIFFERENT request means the same picture was reused — money on someone else's
// damage — so a high-severity signal goes to the console, where a person decides.
// Fraud v2 (roadmap 2f) now joins this file: cross-shop, cross-vehicle and
// cross-request patterns. These are ADVISORY signals (severity low): a pattern
// can be innocent (a popular shop, the same car damaged twice, a copied
// summary quote), so a person decides — nothing here refuses or accuses.
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

interface PatternRow {
  request_id: string;
  member_id: string;
  payee_id: string | null;
  asset_id: string | null;
  public_summary: string | null;
  created_at: string;
}

interface AssetRow {
  id: string;
  member_id: string;
  description: string;
  value_cents: number;
}

interface FreshRequest {
  id: string;
  member_id: string;
  payee_id: string | null;
  asset_id: string | null;
  public_summary: string | null;
}

/**
 * Cross-shop: this member's request names a shop that already carries requests
 * from other members. Popular shops are innocent, so the signal is low.
 */
export function crossShopSignals(
  fresh: FreshRequest,
  rows: PatternRow[],
): {
  detail: unknown;
}[] {
  if (fresh.payee_id === null) {
    return [];
  }
  const seen = new Set<string>();
  const out: { detail: unknown }[] = [];
  for (const row of rows) {
    if (row.payee_id !== fresh.payee_id) continue;
    if (row.member_id === fresh.member_id) continue;
    if (seen.has(row.member_id)) continue;
    seen.add(row.member_id);
    out.push({ detail: { other_member_request: row.request_id } });
  }
  return out;
}

/**
 * Cross-vehicle: another member's request is about an asset that reads exactly
 * like this member's (same description and value). Two members claiming the
 * same car is money on someone else's damage.
 */
export function crossVehicleSignals(
  freshAsset: AssetRow,
  fresh: FreshRequest,
  rows: PatternRow[],
  assets: AssetRow[],
): {
  detail: unknown;
}[] {
  if (fresh.asset_id === null) {
    return [];
  }
  const otherAssets = assets
    .filter((a) => a.member_id !== freshAsset.member_id)
    .filter((a) =>
      a.description === freshAsset.description &&
      a.value_cents === freshAsset.value_cents
    )
    .map((a) => a.id);
  if (otherAssets.length === 0) {
    return [];
  }
  return rows
    .filter((row) =>
      row.asset_id !== null && otherAssets.includes(row.asset_id!)
    )
    .map((row) => ({
      detail: { other_member_request: row.request_id },
    }));
}

/**
 * Cross-request: another member's request carries the exact same public
 * summary. Copied stories are worth a look, not an accusation.
 */
export function crossTextSignals(
  fresh: FreshRequest,
  rows: PatternRow[],
  summaries: Record<string, string | null>,
): {
  detail: unknown;
}[] {
  if (fresh.public_summary === null) {
    return [];
  }
  return rows
    .filter((row) => row.member_id !== fresh.member_id)
    .filter((row) => summaries[row.request_id] === fresh.public_summary)
    .map((row) => ({
      detail: { other_member_request: row.request_id },
    }));
}

/**
 * Write every pattern the checks found. Kinds: cross_shop, cross_vehicle,
 * cross_request — all low severity; a person decides at the console.
 */
export async function flagPatterns(
  fresh: FreshRequest,
  rows: PatternRow[],
  assetOfFresh: AssetRow | null,
  assets: AssetRow[],
  summaries: Record<string, string | null>,
  db: Db,
): Promise<number> {
  let written = 0;
  const groups: Array<[string, { detail: unknown }[]]> = [
    ["cross_shop", crossShopSignals(fresh, rows)],
    [
      "cross_vehicle",
      crossVehicleSignals(
        assetOfFresh ??
          { id: "", member_id: "", description: "", value_cents: 0 },
        fresh,
        rows,
        assets,
      ),
    ],
    ["cross_request", crossTextSignals(fresh, rows, summaries)],
  ];
  for (const [kind, signals] of groups) {
    for (const signal of signals) {
      await db.rpc("record_fraud_signal", {
        p_request: fresh.id,
        p_kind: kind,
        p_severity: "low",
        p_detail: signal.detail,
      });
      written += 1;
    }
  }
  return written;
}
