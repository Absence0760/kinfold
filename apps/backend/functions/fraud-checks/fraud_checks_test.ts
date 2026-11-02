// `fraud-checks` unit tests (`pnpm test:edge`, no stack, no Docker). The `Db`
// is a fake that records calls. Fraud v1 (duplicate photos) and fraud v2
// patterns (cross-shop, cross-vehicle, cross-request — all low severity, each
// other member's request its own signal, a member's own requests excluded)
// are pinned here.
import { assertEquals } from "jsr:@std/assert";
import {
  crossShopSignals,
  crossTextSignals,
  crossVehicleSignals,
  duplicatePhotoSignals,
  flagDuplicatePhotos,
  flagPatterns,
} from "./index.ts";

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

function recordArgs(log: Array<[string, unknown]>) {
  return {
    storage() {
      throw new Error("fraud-checks never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      log.push([name, args]);
      return Promise.resolve();
    },
  };
}

const fresh = {
  id: "r-new",
  member_id: "m-a",
  payee_id: "p-shop",
  asset_id: "v-1",
  public_summary: "Bumper after a slow backing-in",
};

Deno.test("a shop already carrying two other members' requests flags twice, low", async () => {
  const log: Array<[string, unknown]> = [];
  const db = recordArgs(log);
  const count = await flagPatterns(
    fresh,
    [
      {
        request_id: "r-b",
        member_id: "m-b",
        payee_id: "p-shop",
        asset_id: null,
        public_summary: null,
        created_at: "t1",
      },
      {
        request_id: "r-c",
        member_id: "m-c",
        payee_id: "p-shop",
        asset_id: null,
        public_summary: null,
        created_at: "t2",
      },
      {
        request_id: "r-a2",
        member_id: "m-a",
        payee_id: "p-shop",
        asset_id: null,
        public_summary: null,
        created_at: "t3",
      },
      {
        request_id: "r-d",
        member_id: "m-d",
        payee_id: null,
        asset_id: null,
        public_summary: null,
        created_at: "t4",
      },
    ],
    null,
    [],
    {},
    db,
  );
  assertEquals(count, 2);
  const kinds = log.map(([, a]) => (a as { p_kind: string }).p_kind);
  assertEquals(kinds, ["cross_shop", "cross_shop"]);
  assertEquals((log[0][1] as { p_severity: string }).p_severity, "low");
});

Deno.test("an exact-asset match on another member's request flags cross_vehicle", async () => {
  const log: Array<[string, unknown]> = [];
  const db = recordArgs(log);
  const asset = {
    id: "v-1",
    member_id: "m-a",
    description: "Blue hatchback, dented left fender",
    value_cents: 1200000,
  };
  const count = await flagPatterns(
    fresh,
    [
      {
        request_id: "r-b",
        member_id: "m-b",
        payee_id: null,
        asset_id: "v-2",
        public_summary: null,
        created_at: "t1",
      },
      {
        request_id: "r-c",
        member_id: "m-c",
        payee_id: null,
        asset_id: "v-3",
        public_summary: null,
        created_at: "t2",
      },
    ],
    asset,
    [
      {
        id: "v-1",
        member_id: "m-a",
        description: "Blue hatchback, dented left fender",
        value_cents: 1200000,
      },
      {
        id: "v-2",
        member_id: "m-b",
        description: "Blue hatchback, dented left fender",
        value_cents: 1200000,
      },
      {
        id: "v-3",
        member_id: "m-c",
        description: "Blue hatchback, dented RIGHT fender",
        value_cents: 1200000,
      },
    ],
    {},
    db,
  );
  assertEquals(count, 1);
  assertEquals(
    (log[0][1] as Record<string, unknown>)["p_kind"],
    "cross_vehicle",
  );
  assertEquals(
    (log[0][1] as unknown as { p_detail: unknown }).p_detail,
    { other_member_request: "r-b" },
  );
});

Deno.test("a copied public summary on another member's request flags cross_request", async () => {
  const log: Array<[string, unknown]> = [];
  const db = recordArgs(log);
  const count = await flagPatterns(
    fresh,
    [
      {
        request_id: "r-b",
        member_id: "m-b",
        payee_id: null,
        asset_id: null,
        public_summary: null,
        created_at: "t1",
      },
      {
        request_id: "r-a2",
        member_id: "m-a",
        payee_id: null,
        asset_id: null,
        public_summary: null,
        created_at: "t2",
      },
    ],
    null,
    [],
    {
      "r-b": "Bumper after a slow backing-in",
      "r-a2": "Bumper after a slow backing-in",
    },
    db,
  );
  assertEquals(count, 1);
  assertEquals(
    (log[0][1] as Record<string, unknown>)["p_kind"],
    "cross_request",
  );
});

Deno.test("a member's own matching requests never cross-flag", async () => {
  const log: Array<[string, unknown]> = [];
  const db = recordArgs(log);
  const count = await flagPatterns(
    fresh,
    [
      {
        request_id: "r-a2",
        member_id: "m-a",
        payee_id: "p-shop",
        asset_id: "v-1",
        public_summary: null,
        created_at: "t1",
      },
    ],
    null,
    [],
    {},
    db,
  );
  assertEquals(count, 0);
  assertEquals(log.length, 0);
});

Deno.test("no shop, no asset and no summary yet flag nothing", async () => {
  const log: Array<[string, unknown]> = [];
  const db = recordArgs(log);
  const bare = {
    id: "r-new",
    member_id: "m-a",
    payee_id: null,
    asset_id: null,
    public_summary: null,
  };
  const count = await flagPatterns(
    bare,
    [{
      request_id: "r-b",
      member_id: "m-b",
      payee_id: "p-shop",
      asset_id: "v-2",
      public_summary: "Bumper after a slow backing-in",
      created_at: "t1",
    }],
    null,
    [],
    { "r-b": "Bumper after a slow backing-in" },
    db,
  );
  assertEquals(count, 0);
  assertEquals(log.length, 0);
});
