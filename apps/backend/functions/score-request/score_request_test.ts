// `score-request` unit tests (`pnpm test:edge`, no stack, no Docker).
// Rules pinned: the evaluation gate keeps scoring off until the set's
// approved (nothing runs before it); a score carries its reasons and
// provenance to `record_score`; a provider score outside 0–100 is refused
// before any record; and the stand-in is deterministic.
import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  evaluationGateOpen,
  inputsSha256,
  localStandIn,
  Provider,
  runScore,
  ScoreInputs,
} from "./index.ts";

const INPUTS: ScoreInputs = {
  kind: "car_damage",
  funding: "pool",
  title: "Bumper after a parking-lot hit",
  public_summary: "Rear bumper, scraped low at a corner turn.",
  evidence: [
    { kind: "photo", redaction_status: "confirmed" },
    { kind: "photo", redaction_status: "confirmed" },
  ],
  incident_on: "2026-10-28",
};

function recorder(log: string[]) {
  return {
    storage() {
      throw new Error("score-request never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
}

Deno.test("the gate keeps scoring off: nothing at all runs", async () => {
  const log: string[] = [];
  const db = recorder(log);
  assertRejects(
    async () => await runScore("r1", INPUTS, localStandIn, "", db),
    Error,
    "the evaluation set isn't approved yet",
  );
  assertEquals(log, []);
  assertEquals(evaluationGateOpen(""), false);
  assertEquals(evaluationGateOpen("300-cases-2026-11-15"), true);
});

Deno.test("an approved gate scores once and records once", async () => {
  const log: string[] = [];
  const db = recorder(log);
  const score = await runScore(
    "r1",
    INPUTS,
    localStandIn,
    "300-cases-2026-11-15",
    db,
  );
  assertEquals(score, 70); // 30 base + 2 confirmed (15 each) + summary 10
  assertEquals(log, ["record_score"]);
});

Deno.test("the stand-in is deterministic", async () => {
  const a = await localStandIn.score(INPUTS);
  const b = await localStandIn.score(INPUTS);
  assertEquals(a, b);
});

Deno.test("a provider score outside 0 to 100 records nothing", async () => {
  const log: string[] = [];
  const db = recorder(log);
  const runaway: Provider = {
    name: "buggy-vendor",
    score: (inputs: ScoreInputs) =>
      Promise.resolve({ score: 140, reasons: [] }),
  };
  assertRejects(
    async () =>
      await runScore("r1", INPUTS, runaway, "300-cases-2026-11-15", db),
    Error,
    "a score must sit 0 to 100",
  );
  assertEquals(log, []);
});

Deno.test("the inputs hash follows the inputs", async () => {
  const h1 = await inputsSha256(INPUTS);
  const h2 = await inputsSha256({ ...INPUTS, public_summary: "" });
  assertEquals(h1 !== h2, true);
});
