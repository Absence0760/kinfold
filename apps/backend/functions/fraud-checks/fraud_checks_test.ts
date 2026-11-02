// `fraud-checks` unit tests (`pnpm test:edge`, no stack, no Docker). The `Db`
// is a fake that records calls. The rules pinned here: a perceptual-hash match
// on ANOTHER request flags a high-severity duplicate-photo signal; the same
// request's own re-upload doesn't; evidence without a perceptual hash flags
// nothing; and every match is its own signal.
import { assertEquals } from "jsr:@std/assert";
import { duplicatePhotoSignals, flagDuplicatePhotos } from "./index.ts";

const H1 = "h-aaa";

function makeRecorder(log: string[]) {
  return {
    storage() {
      throw new Error("fraud-checks never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
}

Deno.test("a photo reused on another request flags high", async () => {
  const log: string[] = [];
  const db = makeRecorder(log);
  const count = await flagDuplicatePhotos(
    { id: "n1", request_id: "r-new", perceptual_hash: H1 },
    [{ request_id: "r-other", perceptual_hash: H1 }],
    db,
  );
  assertEquals(count, 1);
  assertEquals(log, ["record_fraud_signal"]);
});

Deno.test("a member's own second photo of the same damage flags nothing", async () => {
  const log: string[] = [];
  const db = makeRecorder(log);
  const count = await flagDuplicatePhotos(
    { id: "n2", request_id: "r-new", perceptual_hash: H1 },
    [{ request_id: "r-new", perceptual_hash: H1 }],
    db,
  );
  assertEquals(count, 0);
  assertEquals(log, []);
});

Deno.test("different hashes never match", async () => {
  assertEquals(
    duplicatePhotoSignals(
      { id: "n3", request_id: "r-new", perceptual_hash: "h-aaa" },
      [{ request_id: "r-other", perceptual_hash: "h-bbb" }],
    ),
    [],
  );
});

Deno.test("evidence still awaiting redaction flags nothing", async () => {
  assertEquals(
    duplicatePhotoSignals(
      { id: "n4", request_id: "r-new", perceptual_hash: null },
      [{ request_id: "r-other", perceptual_hash: H1 }],
    ),
    [],
  );
});

Deno.test("the same picture on three other requests is three signals", async () => {
  const log: string[] = [];
  const db = makeRecorder(log);
  const count = await flagDuplicatePhotos(
    { id: "n5", request_id: "r-new", perceptual_hash: H1 },
    [
      { request_id: "r-a", perceptual_hash: H1 },
      { request_id: "r-b", perceptual_hash: H1 },
      { request_id: "r-c", perceptual_hash: H1 },
    ],
    db,
  );
  assertEquals(count, 3);
  assertEquals(log, [
    "record_fraud_signal",
    "record_fraud_signal",
    "record_fraud_signal",
  ]);
});
