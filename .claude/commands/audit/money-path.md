---
description: Sweep every path that computes, schedules, allocates or routes money against Kinfold's money invariants (no interest or late fees, integer cents, app never holds money, pay the payee, pools separate, explainable allocation). Use after changes to finance/, requests/, fund settings, or any table or function that carries an amount.
---

Sweep every code path that calculates an amount, builds a repayment schedule, allocates pool money, or decides where money goes, and check it against the invariants in `docs/STACK.md` § Domain rules and `docs/design.md` § Principles.

## Why this command exists

`/check` runs `money-path-reviewer` on a diff. This is the periodic, whole-repo version: a regression that slipped in before the reviewer existed, or arrived through a file nobody thought of as money code, only shows up in a sweep. Kinfold's money bugs are quiet and look right: a schedule that sums to a cent more than the principal is interest; a rounding remainder dropped is a silent fee; a convenience refund to the requester breaks "pay the payee".

## Procedure

### 1. Enumerate the money surface

As of today:

- `apps/web/src/lib/finance/amortization.ts` (+ test): zero-interest repayment schedules.
- `apps/web/src/lib/requests/allocation.ts` (+ test): community-pool allocation by legitimacy band, filled concurrently, pro-rata within a band, friends' money counted first.
- `apps/web/src/lib/core/format.ts`: how amounts render.
- `apps/web/src/lib/landing/SavingsCalculator.svelte`, `RequestBoard.svelte`: amounts shown to the public.
- `apps/backend/supabase/migrations/`: every column, check and function that holds or computes an amount (`public.fund_settings`: `max_request_cents`, `reserve_bps`, `min_score`, `band_size`).
- Edge functions under `apps/backend/supabase/functions/` once they exist (payment-partner calls, webhooks, payouts).

Then search for anything not on the list: `rg -n -i 'cents|amount|principal|payment|payout|interest|fee|rate|balance|refund|reserve|bps' apps/ --glob '!**/node_modules/**'`. A money-handling file missing from the list above is itself a finding (update this list).

### 2. For each path, check the invariants

1. **No interest, no late fees, ever.** No rate, APR, interest, penalty or late-fee field or parameter anywhere; the migrations state "there is no interest column anywhere, by design". A schedule's payments sum **exactly** to the principal. Where a minimum (AFR) rate is required for tax, it is calculated and shown and paired with a forgiveness-as-gift record, never collected.
2. **Integer cents end to end.** `bigint` cents in SQL (never `numeric` dollars, never floats); integer arithmetic in TS. Any division (instalments, pro-rata shares) has an explicit remainder rule that keeps the total exact, applied once. A float literal or `/ 100` in arithmetic (as opposed to display) is a finding.
3. **The app never holds member money.** No balance or wallet table that represents money Kinfold holds; pooled money lives with a licensed partner, reached by API. Kinfold stores records, schedules and documents.
4. **Pay the payee.** Damage requests pay the named shop against its invoice; home requests pay the lender or seller. No path, including refunds, overpayment returns and error handling, sends request money to the requester.
5. **Pools stay separate.** Protection pool, Home Fund and people-to-people lending live in separate schemas or services; no function moves value between them, and no claim decision reads loan exposure (design.md § Risks: conflict between lending and protection).
6. **Allocation follows the published rule.** Highest band first, the whole band concurrently, equal share of remaining need when a band can't be covered, friends' money first; driven by `fund_settings` data, not constants. Never by story, likes or donations (design.md principle 4). Rule changes leave a history row (`private.fund_settings_history`).
7. **Lender protection.** Lending caps tied to the lender's savings, warnings shown; hardship pause without penalty (design.md § Product 1).
8. **Auditability.** Every change to money state or money rules is recorded with who and when; idempotency on any write that will move money through a partner (a retried request must not pay twice).
9. **Tests with real numbers.** Each path has a test that would fail if the bug came back: an indivisible principal (e.g. 100001 cents over 3), a band that can't be fully covered, friends covering the whole need.

### 3. Spawn the reviewer for nuance

```
Agent({
  subagent_type: "money-path-reviewer",
  prompt: "Sweep mode, whole repo (not a diff). Audit every path listed in
  .claude/commands/audit/money-path.md against Kinfold's money invariants.
  For each, cite file:line, and show any finding with numbers."
})
```

### 4. Render the report

```
## /audit/money-path report

### apps/web/src/lib/finance/amortization.ts
  - No interest:      PASS — schedule sums to principal (test: …)
  - Integer cents:    PASS
  - Remainder rule:   FAIL — last instalment absorbs remainder twice (file:line)

Summary: <N>/<total> paths fully compliant. Critical: <N>. Improvement: <N>.
```

Severity follows `money-path-reviewer`: **Critical** charges interest or a fee, pays the wrong party, moves money between pools, or holds member money; **Improvement** misses a real-numbers test, an audit row or a doc update; **Note** doesn't block.

## Output → `reviews/`

Persist the report to `reviews/audit-money-path.md` (git-ignored; see `reviews/README.md`), findings with `[ ]` boxes, updated in place on re-runs. Read-only otherwise.
