// `subrogation` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { handleSubrogationStatement } from "./index.ts";

Deno.test("a statement reaches the schema once, already verified there", async () => {
  const calls: unknown[] = [];
  const db = {
    storage() {
      throw new Error("subrogation never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push([name, args]);
      return Promise.resolve(null);
    },
  };
  await handleSubrogationStatement(
    {
      requestId: "r1",
      amountCents: 30000,
      on: "2026-10-20",
      partnerRef: "pi_sub_1",
    },
    db,
  );
  assertEquals(calls.length, 1);
  const [name, args] = calls[0] as [string, Record<string, unknown>];
  assertEquals(name, "record_partner_recovery");
  assertEquals(args["p_partner_ref"], "pi_sub_1");
  assertEquals(args["p_source"], "insurance");
});

Deno.test("a statement with no money is refused before any write", async () => {
  const calls: string[] = [];
  const db = {
    storage() {
      throw new Error("subrogation never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      calls.push(name);
      return Promise.resolve(null);
    },
  };
  await expectThrown(async () => {
    await handleSubrogationStatement(
      {
        requestId: "r1",
        amountCents: 0,
        on: "2026-10-20",
        partnerRef: "pi_sub_1",
      },
      db,
    );
  });
  assertEquals(calls, []);
});

Deno.test("a statement with no reference is refused before any write", async () => {
  const calls: string[] = [];
  const db = {
    storage() {
      throw new Error("subrogation never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      calls.push(name);
      return Promise.resolve(null);
    },
  };
  await expectThrown(async () => {
    await handleSubrogationStatement(
      { requestId: "r1", amountCents: 30000, on: "2026-10-20", partnerRef: "" },
      db,
    );
  });
  assertEquals(calls, []);
});

async function expectThrown(fn: () => unknown): Promise<void> {
  try {
    await fn();
  } catch {
    return;
  }
  throw new Error("the statement was not refused");
}
