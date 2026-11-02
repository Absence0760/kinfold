// `loan-servicing` unit tests (`pnpm test:edge`, no stack, no Docker).
import { assertEquals } from "jsr:@std/assert";
import {
  applyDueDefaultPlans,
  collectDueInstallments,
  dueForCollection,
} from "./index.ts";

const NOW = "2026-11-02";

const ACTIVE = { id: "loan-active", status: "active" };
const SIGNED = { id: "loan-signed", status: "signed" };
const FORGIVEN = { id: "loan-forgiven", status: "forgiven" };

function installments(
  rows: {
    loan_id: string;
    seq: number;
    due_on: string;
    amount_cents: number;
    paid_cents: number;
    paused: boolean;
  }[],
) {
  return rows;
}

Deno.test("a due installment on a collecting loan is collected", () => {
  const due = dueForCollection(
    installments([
      {
        loan_id: "loan-active",
        seq: 1,
        due_on: "2026-11-01",
        amount_cents: 15000,
        paid_cents: 0,
        paused: false,
      },
    ]),
    [ACTIVE],
    NOW,
  );
  assertEquals(due, [{ loanId: "loan-active", seq: 1 }]);
});

Deno.test("a due date in the future is not collected", () => {
  const due = dueForCollection(
    installments([
      {
        loan_id: "loan-active",
        seq: 1,
        due_on: "2026-11-03",
        amount_cents: 15000,
        paid_cents: 0,
        paused: false,
      },
    ]),
    [ACTIVE],
    NOW,
  );
  assertEquals(due, []);
});

Deno.test("the due day itself is collected", () => {
  const due = dueForCollection(
    installments([
      {
        loan_id: "loan-active",
        seq: 1,
        due_on: NOW,
        amount_cents: 15000,
        paid_cents: 0,
        paused: false,
      },
    ]),
    [ACTIVE],
    NOW,
  );
  assertEquals(due, [{ loanId: "loan-active", seq: 1 }]);
});

Deno.test("a paused installment is never collected", () => {
  const due = dueForCollection(
    installments([
      {
        loan_id: "loan-active",
        seq: 1,
        due_on: "2026-10-01",
        amount_cents: 15000,
        paid_cents: 0,
        paused: true,
      },
    ]),
    [ACTIVE],
    NOW,
  );
  assertEquals(due, []);
});

Deno.test("a loan money hasn't moved on (signed) or is over (forgiven) collects nothing", () => {
  const due = dueForCollection(
    installments([
      {
        loan_id: "loan-signed",
        seq: 1,
        due_on: "2026-10-01",
        amount_cents: 15000,
        paid_cents: 0,
        paused: false,
      },
      {
        loan_id: "loan-forgiven",
        seq: 1,
        due_on: "2026-10-01",
        amount_cents: 15000,
        paid_cents: 0,
        paused: false,
      },
    ]),
    [SIGNED, FORGIVEN],
    NOW,
  );
  assertEquals(due, []);
});

Deno.test("installments collect loan by loan, then seq by seq", () => {
  const loanA = { id: "loan-a", status: "active" };
  const loanB = { id: "loan-b", status: "active" };
  const due = dueForCollection(
    installments([
      {
        loan_id: "loan-b",
        seq: 2,
        due_on: "2026-01-01",
        amount_cents: 100,
        paid_cents: 0,
        paused: false,
      },
      {
        loan_id: "loan-a",
        seq: 2,
        due_on: "2026-01-01",
        amount_cents: 100,
        paid_cents: 0,
        paused: false,
      },
      {
        loan_id: "loan-a",
        seq: 1,
        due_on: "2026-01-01",
        amount_cents: 100,
        paid_cents: 0,
        paused: false,
      },
    ]),
    [loanA, loanB],
    NOW,
  );
  assertEquals(due, [
    { loanId: "loan-a", seq: 1 },
    { loanId: "loan-a", seq: 2 },
    { loanId: "loan-b", seq: 2 },
  ]);
});

Deno.test("collecting calls record_loan_payment with the owed amount", async () => {
  const log: string[] = [];
  const db = {
    storage() {
      throw new Error("loan-servicing never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      log.push(`${name}:${args.p_loan ?? ""}`);
      return Promise.resolve();
    },
  };
  const count = await collectDueInstallments(
    installments([
      {
        loan_id: "loan-active",
        seq: 1,
        due_on: "2026-11-01",
        amount_cents: 15000,
        paid_cents: 5000,
        paused: false,
      },
    ]),
    [ACTIVE],
    NOW,
    db,
  );
  assertEquals(count, 1);
  assertEquals(log, ["record_loan_payment:loan-active"]);
});

Deno.test("a refused default plan (someone changed the loan) skips, not crashes", async () => {
  const db = {
    storage() {
      throw new Error("loan-servicing never touches a bucket");
    },
    rpc: (name: string, args: Record<string, unknown>) =>
      args.p_loan === "loan-changed"
        ? Promise.reject(new Error("loan is repaid"))
        : Promise.resolve(),
  };
  const applied = await applyDueDefaultPlans(["loan-one", "loan-changed"], db);
  assertEquals(applied, ["loan-one"]);
});
