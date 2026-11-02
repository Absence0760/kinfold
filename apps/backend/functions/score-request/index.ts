// `score-request`: runs behind a provider interface. Design rule: the AI
// never refuses — `record_score` routes only to open, needs-evidence or in
// review (the schema owns that), and every score carries its reasons and its
// provenance (model, versions, inputs hash) so the console can retrace it.
//
// THE EVALUATION GATE: scoring turns on only after a labelled evaluation set
// (at least 300 real-shaped cases) has been built and reviewed. Until then
// this function refuses to run, and requests stay in the queue. The stamp
// (e.g. "300-cases-2026-11-15") arrives from the function's deploy config;
// blank means the set isn't approved yet.
//
// The bundled provider is an honest LOCAL STAND-IN (a completeness heuristic,
// not a vendor): prod swaps it for Ollama locally or a hosted model. The
// schema's rules don't change with the swap.

import { sha256Hex } from "../redact-evidence/sha256.ts";

import { Db } from "../shared/rest.ts";

export interface ScoreInputs {
  kind: string;
  funding: string;
  title: string;
  public_summary: string;
  /** Evidence rows that exist for this request (kinds, counts). */
  evidence: { kind: string; redaction_status: string }[];
  incident_on: string;
}

export interface Provider {
  /** A name for the provenance columns, and the scoring call itself. */
  name: string;
  score(inputs: ScoreInputs): Promise<{ score: number; reasons: string[] }>;
}

/**
 * The stand-in: an evidence completeness heuristic. Photos with redaction
 * confirmed weigh most; a summary and an incident date count; nothing about
 * a picture is understood. Clearly a stand-in — replace with Ollama
 * (local) or a hosted model (prod) without touching the schema's rules.
 */
export const localStandIn: Provider = {
  name: "local-stand-in",
  score: (inputs: ScoreInputs) => {
    let score = 30;
    const confirmed =
      inputs.evidence.filter((e) => e.redaction_status === "confirmed").length;
    score += Math.min(50, confirmed * 15);
    if (inputs.public_summary !== "") score += 10;
    return Promise.resolve({
      score,
      reasons: [
        `evidence files confirmed: ${confirmed} (worth 15 each, capped at 50)`,
        `a written summary ${
          inputs.public_summary === "" ? "missing" : "present"
        }`,
      ],
    });
  },
};

/** The evaluation-set gate: a blank stamp keeps scoring off. */
export function evaluationGateOpen(stamp: string): boolean {
  return stamp !== "";
}

/** Score provenance hash: over the exact inputs the provider saw. */
export async function inputsSha256(inputs: ScoreInputs): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(inputs)).buffer;
  return await sha256Hex(bytes);
}

export async function runScore(
  requestId: string,
  inputs: ScoreInputs,
  provider: Provider,
  evalSetStamp: string,
  db: Db,
): Promise<number> {
  if (!evaluationGateOpen(evalSetStamp)) {
    // The queue waits: no provider call, no score row, nothing recorded.
    throw new Error(
      "the evaluation set isn't approved yet: scoring stays off (300+ labelled cases needed)",
    );
  }
  const result = await provider.score(inputs);
  if (result.score < 0 || result.score > 100) {
    throw new Error(`a score must sit 0 to 100: ${result.score}`);
  }
  const inputs_sha256 = await inputsSha256(inputs);
  await db.rpc("record_score", {
    p_request: requestId,
    p_score: result.score,
    p_reasons: result.reasons,
    p_model: provider.name,
    p_model_version: evalSetStamp,
    p_prompt_version: "v1",
    p_inputs_sha256: inputs_sha256,
  });
  return result.score;
}
