// `evidence-url` unit tests (`pnpm test:edge`, no stack, no Docker). The
// issuer is a fake that signs locally; the `Db` records calls. Rules pinned:
// same-region and self pairings sign NOTHING (no URL, no audit); a clean
// pairing signs and audits; the bucket is always the originals one.
import { assertEquals } from "jsr:@std/assert";
import { issueEvidenceUrl } from "./index.ts";

const REQUEST = { id: "r-1", member_id: "member-1", region: "CA" };

function issuer(log: string[]) {
  return {
    issue: (bucket: string, path: string, seconds: number) => {
      log.push(`${bucket}/${path}@${seconds}`);
      return Promise.resolve(`signed:${path}`);
    },
  };
}

function recordDb(log: string[]) {
  return {
    storage() {
      throw new Error("evidence-url never touches a bucket itself");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      log.push(name);
      return Promise.resolve();
    },
  };
}

Deno.test("a same-region reviewer sees no original at all", async () => {
  const issuerLog: string[] = [];
  const dbLog: string[] = [];
  const url = await issueEvidenceUrl(
    REQUEST.id,
    "member-2",
    "member-1/r-1/capture.jpg",
    REQUEST,
    "CA",
    issuer(issuerLog),
    recordDb(dbLog),
  );
  assertEquals(url, null);
  assertEquals(issuerLog, []);
  assertEquals(dbLog, []);
});

Deno.test("the requester reviewing their own request signs nothing", async () => {
  const issuerLog: string[] = [];
  const dbLog: string[] = [];
  const url = await issueEvidenceUrl(
    REQUEST.id,
    "member-1",
    "member-1/r-1/capture.jpg",
    REQUEST,
    "OR",
    issuer(issuerLog),
    recordDb(dbLog),
  );
  assertEquals(url, null);
  assertEquals(issuerLog, []);
  assertEquals(dbLog, []);
});

Deno.test("a clean pairing signs a short-lived URL and audits it", async () => {
  const issuerLog: string[] = [];
  const dbLog: string[] = [];
  const url = await issueEvidenceUrl(
    REQUEST.id,
    "member-2",
    "member-1/r-1/capture.jpg",
    REQUEST,
    "OR",
    issuer(issuerLog),
    recordDb(dbLog),
  );
  assertEquals(url, "signed:member-1/r-1/capture.jpg");
  assertEquals(issuerLog, ["evidence-original/member-1/r-1/capture.jpg@900"]);
  assertEquals(dbLog, ["record_evidence_url"]);
});
