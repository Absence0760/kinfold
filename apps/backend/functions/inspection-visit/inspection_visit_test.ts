// `inspection-visit` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import { handleVisitStatement } from "./index.ts";

Deno.test("a clear visit reaches the schema once", async () => {
  const calls: unknown[] = [];
  const db = {
    storage() {
      throw new Error("inspection-visit never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push([name, args]);
      return Promise.resolve(null);
    },
  };
  await handleVisitStatement(
    {
      requestId: "r1",
      result: "clear",
      inspectorRef: "insp_1",
      note: "The invoice matches.",
    },
    db,
  );
  assertEquals(calls.length, 1);
  const [name, args] = calls[0] as [string, Record<string, unknown>];
  assertEquals(name, "record_inspection");
  assertEquals(args["p_result"], "clear");
  assertEquals(args["p_inspector_ref"], "insp_1");
});

Deno.test("an untraceable visit is refused before any write", async () => {
  const names: string[] = [];
  const db = {
    storage() {
      throw new Error("inspection-visit never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      names.push(name);
      return Promise.resolve(null);
    },
  };
  let refused = false;
  try {
    await handleVisitStatement(
      { requestId: "r1", result: "clear", inspectorRef: "" },
      db,
    );
  } catch {
    refused = true;
  }
  assertEquals(refused, true);
  assertEquals(names, []);
});

Deno.test("money is never moved here: no journal or payout calls", async () => {
  const names: string[] = [];
  const db = {
    storage() {
      throw new Error("inspection-visit never touches a bucket");
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      names.push(name);
      return Promise.resolve(null);
    },
  };
  await handleVisitStatement(
    { requestId: "r1", result: "issue_found", inspectorRef: "insp_2" },
    db,
  );
  assertEquals(
    names.filter((name) => name === "post_journal" || name === "create_payout"),
    [],
  );
});
