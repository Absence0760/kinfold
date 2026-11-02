// `verify-identity` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { assertRejects } from "jsr:@std/assert";
import { fakeVendorApproves, startIdentityCheck } from "./index.ts";

const MEMBER = "00000000-0000-0000-000a-0000000000000001";

function makeDb(rpcLog: string[]) {
  return {
    storage() {
      throw new Error("verify-identity never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve();
    },
  };
}

Deno.test("a passing check calls record_identity_check once", async () => {
  const rpcLog: string[] = [];
  const db = makeDb(rpcLog);
  const result = await startIdentityCheck(MEMBER, "nia@test.com", db);
  assertEquals(result.completed, true);
  assertEquals(result.vendorUrl, null);
  assertEquals(rpcLog, ["record_identity_check"]);
});

Deno.test("a real email leaves the check to the vendor's flow", async () => {
  const rpcLog: string[] = [];
  const db = makeDb(rpcLog);
  const result = await startIdentityCheck(MEMBER, "real@email.com", db);
  assertEquals(result.completed, false);
  assertEquals(result.vendorUrl, `https://vendor.example/verify/${MEMBER}`);
  assertEquals(rpcLog, []);
});

Deno.test("an empty email is refused before any call", async () => {
  const rpcLog: string[] = [];
  const db = makeDb(rpcLog);
  assertRejects(
    async () => await startIdentityCheck(MEMBER, "", db),
    Error,
    "the vendor needs an email",
  );
  assertEquals(rpcLog, []);
});
