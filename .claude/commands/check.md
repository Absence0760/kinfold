---
description: Pre-commit gate — runs code-reviewer + test-gap-checker + doc-hygiene-checker in parallel against the working diff, plus money-path-reviewer / scoring-fairness-reviewer / migration-coordinator / ui-polisher review when the diff reaches their surface. Advisory output. Cheaper than /safe-edit; use it before every non-trivial commit.
---

Run a parallel agent audit on the working diff, aggregate findings, and report. Advisory only — you don't apply fixes here, the user decides which to land.

## When to use this command

**Right fit:**
- Right before committing a non-trivial change.
- After a bug fix lands, to confirm a regression test went with it.
- After a feature change, to confirm test + doc updates went with it.

**Wrong fit — refuse:**
- Trivial diffs (typos, comment edits, dep-version bumps with no source change, Svelte template / CSS-only tweaks). The agents skip these, and running the command burns ~30s of agent time for nothing.
- Empty `git status` — there's nothing to audit. Tell the user.

## What this command does NOT do

- It does NOT apply any fixes. Each agent is read-only by design. The output is a list of gaps; the user picks what to fix.
- It does NOT replace `/safe-edit`'s coder ↔ reviewer loop. `/safe-edit` is for security-sensitive or migration-style changes that warrant the 2-3x cost of a fix-and-re-review cycle. `/check` is the lighter pre-commit gate.

## Procedure

### 1. Sanity-check the diff exists

Run `git status`. If both staged and unstaged are empty, abort: tell the user there's nothing to audit.

### 2. Confirm it's not trivial

If the diff is trivial (typo, comment, single-line dep bump, generated-file regen only, Svelte template / CSS-only), abort with a one-line "trivial — skipping `/check`" message. The agents would each independently bail on the same diff.

### 3. Spawn the agents in parallel

Send a single message with one Agent tool call per agent. Always the three
engineering gates (`.claude/agents/engineering/`):

- `code-reviewer` — prompt: "Review the working diff against Kinfold's documented conventions. Output the strict format from your spec."
- `test-gap-checker` — prompt: "Audit the working diff for missing test surface (Vitest in `apps/web`, pgTAP in `apps/backend/supabase/tests/`) per the root CLAUDE.md tests-and-docs rule. Output the format from your spec."
- `doc-hygiene-checker` — prompt: "Audit the working diff against the root CLAUDE.md doc-update rule. Output which docs need updating."

Plus, only when the diff reaches their surface (`git diff --name-only` +
`git diff --staged --name-only`):

| Agent | Spawn when the diff touches |
|---|---|
| `money-path-reviewer` (engineering) | `apps/web/src/lib/finance/`, `apps/web/src/lib/requests/allocation.ts`, SQL touching `contributions`, `family_loans`, `loan_installments`, `loan_pauses`, `loan_forgiveness`, `pool_runs` / `pool_allocations` / `run_pool_allocation`, `payouts`, `payees`, `subscriptions` / `subscription_payments`, `private.ledger_*` / `private.post_journal`, or the `payments-webhook` / `run-pool` / `reconcile` / `loan-servicing` edge functions — or any `*_cents` column |
| `scoring-fairness-reviewer` (engineering) | legitimacy scoring, eligibility or allocation logic: `apps/web/src/lib/requests/`, `fund_settings` / `min_score` / `band_size`, `scores` / `record_score`, `reviews` / `record_review` / `appeals`, the request status guard or `request_transitions`, `private.fraud_signals`, the `score-request` / `fraud-checks` edge functions or the scorer prompt, the Home Fund needs formula |
| `migration-coordinator` (engineering) | anything under `apps/backend/supabase/migrations/` |
| `ui-polisher` (design) | a screen or component under `apps/web/src/routes/` or `apps/web/src/lib/**/*.svelte` (markup or styles, not only logic) — prompt it in review mode: "review: the working diff" |

Prompts: "Review the working diff. Output the format from your spec." (for
`migration-coordinator`, name the migration file).

Parallel because they're independent — every agent only reads the diff and the files around it (the migration coordinator also applies the migration to the local Supabase database).

If the diff is committed on a branch rather than in the working tree, say so in each prompt ("the diff is `git diff origin/main...HEAD`").

### 4. Aggregate

When every spawned agent returns, build a single short report:

```
## /check report

**Change:** <one-sentence summary, take from whichever agent said it best>

### Code review (`code-reviewer`)
Status: <CLEAN | NEEDS_CHANGES>
<verbatim findings list, or "no concrete findings">

### Test gaps (`test-gap-checker`)
<verbatim verdicts list, or "test surface is consistent">

### Doc gaps (`doc-hygiene-checker`)
<verbatim verdicts list, or "doc set is clean">

### Domain reviews (only the ones spawned)
`money-path-reviewer` / `scoring-fairness-reviewer` / `migration-coordinator` / `ui-polisher` review — status + verbatim findings each.

### Recommendation
<one of:>
- Every agent came back clean — ready to commit.
- Code review and docs are clean; <N> test gap(s) — the user should decide whether to land tests now or in a follow-up.
- <N> code-review finding(s) — apply or push back before committing.
- Multiple gaps across review / tests / docs — list and let the user pick.
```

### 5. Hand off

Ask the user how they want to proceed. **Do not** apply any fixes automatically. Do not commit.

## Tone

Don't narrate the parallel-agent fan-out in user-facing text. The user sees:
- A one-line "Running review + test-gap + doc-hygiene checks (+ domain reviewers where the diff reaches them)…"
- The aggregated report.
- A short "Want me to apply the test gaps? Land it as-is? Add a follow-up task?" question at the end.
