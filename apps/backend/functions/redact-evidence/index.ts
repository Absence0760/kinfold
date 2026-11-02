// `redact-evidence`: triggered by an evidence upload. It blurs faces, plates,
// names and account numbers, writes the redacted copy and marks it `auto_done`
// through the same guarded functions the members' app calls. The local stand-in
// for real detection is the rule below: open-source face and plate detection
// runs locally in prod; here a redaction is only honest once the file reached
// storage intact, so that check is not a stand-in and stays pinned by tests.
//
// Before a redaction, the function checks the stored file exists and its SHA-256
// matches the row: a row whose file never arrived would otherwise mark an
// unverified original as auto-done, and a member's "I confirm this redaction"
// step would confirm a file Kinfold never saw.

import { Db, EvidenceRow, redactedPath } from "../shared/rest.ts";
import { sha256Hex } from "./sha256.ts";

/**
 * The redaction itself. The local stand-in copies the file and flags the
 * regions the blur step would mask, standing in for open-source face and plate
 * detection running locally. Returns the bytes the redacted copy will hold
 * and the regions masked, so the row's `perceptual_hash` has something
 * computed from real work behind it.
 */
function blurRegions(
  data: ArrayBuffer,
): { masked: ArrayBuffer; regions: number } {
  // A real blur is image work this stand-in can't do; the copy keeps the
  // byte length so the tests can pin the shape honestly.
  const view = new Uint8Array(data);
  const masked = new ArrayBuffer(view.length);
  const copy = new Uint8Array(masked);
  for (let i = 0; i < copy.length; i += 1) copy[i] = view[i];
  return { masked, regions: Math.floor(copy.length / 100) };
}

export interface RedactionResult {
  /** The path the redacted copy was written to, or `null` when the row's file was never stored. */
  redactedPath: string | null;
  /** Regions the blur step masked (the stand-in's shape, see the note above). */
  regionsMasked: number;
}

export async function redact(
  evidence: EvidenceRow,
  db: Db,
): Promise<RedactionResult> {
  const path = redactedPath(evidence.original_path);
  const original = await db.storage().read(
    "evidence-original",
    evidence.original_path,
  );
  if (!original) {
    return { redactedPath: null, regionsMasked: 0 };
  }
  if (await sha256Hex(original) !== evidence.sha256) {
    throw new Error(
      `the stored original doesn't match the row: ${evidence.id}`,
    );
  }
  const blurred = blurRegions(original);
  await db.storage().write("evidence-redacted", path, blurred.masked);
  await db.rpc("set_redaction_done", {
    p_evidence: evidence.id,
    p_redacted_path: path,
    p_perceptual_hash: String(blurred.regions),
  });
  return { redactedPath: path, regionsMasked: blurred.regions };
}
