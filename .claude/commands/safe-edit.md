---
description: Implement a non-trivial change with a code-reviewer agent loop — coder → review → fix → review → ready-to-commit. Costs ~2-3x a normal edit; use when the change warrants the extra rigor.
argument-hint: <task description>
---

Implement the task `$ARGUMENTS` with a project-specific code-reviewer agent in the loop.

## When to use this command

**Right fit:**
- Money-path changes — anything that computes, stores or moves an amount: `apps/web/src/lib/finance/` (loan maths, repayment schedules), `apps/web/src/lib/requests/allocation.ts` (community-pool allocation by legitimacy band, mirrored by `run_pool_allocation`), any `*_cents` column, `family_loans` / `loan_installments` / pauses / forgiveness, `contributions`, `payouts`, `pool_runs`, the `private.ledger_*` tables, subscriptions, the `payments-webhook` edge function. The domain rules in `docs/STACK.md` § Domain rules and `docs/backend.md` § "Where each rule is enforced" are load-bearing here: no interest and no late fees in any code path, pay the payee not the member, the app never holds member money, the pools stay separate.
- Scoring and eligibility changes — the `score-request` edge function, `record_score`, the `scores` table, the request status guard and `request_transitions`, `record_review`, its inputs or prompt, `fund_settings` (`min_score`, `band_size`, `reserve_bps`), the Home Fund needs formula, anything that routes a request to review. Scores are explained, versioned, and never refuse on their own.
- Access and data-protection changes — RLS policies, grants, anything moved between the `public` and `private` schemas, `security definer` functions, Supabase Auth config in `apps/backend/supabase/config.toml`, identity / KYC records, the `evidence-original` / `evidence-redacted` buckets and redaction, the `board_requests` view, `private.audit_log`.
- Schema changes — anything under `apps/backend/supabase/migrations/` (pair with `/safe-migration`).
- Edge functions under `apps/backend/supabase/functions/` that hold a service-role key, call the AI scorer, or receive a partner webhook.
- Infra changes once `infra/` exists — OIDC trust policy, S3 bucket policy, CloudFront security headers.
- Cross-workspace changes that touch `apps/web` and `apps/backend` at once.
- Anything you want a second pair of eyes on before commit.

**Wrong fit — refuse and tell the user to edit directly:**
- Typos and one-line doc corrections.
- Comment edits.
- Single-property CSS / Svelte template changes.
- Dependency-version bumps that don't change source.
- Anything where the diff is going to be < ~10 lines and touches no project invariant.

The cost of this loop is real (~2-3x tokens, ~30-60s extra latency, one or two `code-reviewer` agent runs). Don't burn it on changes that don't warrant it. **If the task is trivial, abort and tell the user to just edit it normally.**

## The loop

1. **Coder pass.** Implement the task as you normally would. Use TaskCreate to track multi-step work. Do NOT commit yet.

2. **Round 1 review.** Spawn the `code-reviewer` agent with the prompt below. When the diff reaches the money path, also spawn `money-path-reviewer`; when it reaches scoring, eligibility or allocation, also spawn `scoring-fairness-reviewer` (same prompt, in parallel). Treat their findings exactly like `code-reviewer`'s — the round is `CLEAN` only when every reviewer spawned says so.
   > "Review the working diff against this project's documented conventions. The task being implemented is: `$ARGUMENTS`. Output the strict format from your spec."

   The reviewer reads `git diff`, cross-references project rules, and outputs:
   - `Status: CLEAN` → go to step 5.
   - `Status: NEEDS_CHANGES` with a numbered list of concrete file:line changes → go to step 3.

3. **Apply fixes.** Read the reviewer's findings. For each Critical / Improvement item:
   - If the finding is correct, apply the suggested change.
   - If the finding is wrong (the reviewer misread, missed context, or cited a rule that doesn't apply here), state explicitly *why* you're not applying it. Do NOT silently skip — the user needs to see the disagreement.
   - If the finding is borderline, apply it; the reviewer is configured to be willing to retract on the next round, so over-applying is safe.

4. **Round 2 review.** Spawn the same reviewer(s) again with the same prompt. Three branches:
   - `Status: CLEAN` → go to step 5.
   - `Status: NEEDS_CHANGES` again → **stop the loop**. Surface the remaining findings to the user along with what you tried in Round 1. Do not auto-cycle to Round 3 — at this point either the reviewer is being pedantic, the coder is missing something, or the change needs more thought than a tight loop can give. The user decides.
   - Reviewer retracts Round 1 findings → also `CLEAN`; go to step 5.

5. **Ready-to-commit handoff.** Tell the user:
   - What was changed (one-line summary, not a recap of the diff).
   - Which review round produced the clean status.
   - Any Notes or Out-of-scope observations the reviewer surfaced (worth knowing, not blocking).
   - Ask whether to commit (the root `CLAUDE.md` § "Working alongside other Claude sessions" says to land each finished piece as its own path-scoped commit and never push; follow the operator's call).

6. **On user "yes":** commit path-scoped — `git commit -m "…" -- <your paths>` (the `git-scope-guard.py` hook blocks `git add -A` and bare `git commit`, since other sessions share this checkout). Draft a message in the project's style (no `Co-Authored-By`, no Claude footer, conventional-commit prefix per the recent log). Never push.

## Loop-termination guarantees

- Hard cap: 2 review cycles. Round 3 is forbidden.
- The reviewer cannot trigger a re-cycle with abstract concerns alone — its spec requires concrete numbered file:line diff changes for `NEEDS_CHANGES`. If it tries to cycle on vague "consider X" findings, treat as `CLEAN` and surface the comments to the user.
- The reviewer's `Out-of-scope observations` are informational only and never trigger a cycle, no matter how many.
- If the coder disagrees with a Round 1 finding and doesn't apply it, that disagreement must be visible in the Round 2 prompt context — quote the disagreement so the reviewer can re-evaluate.

## What this command does NOT replace

- `/check` is the lighter pre-commit gate — review + test-gap + doc-hygiene, single pass, advisory. Use it for everyday changes that don't warrant `/safe-edit`'s 2-3x cost. The two are complementary.
- `pnpm check` / `pnpm test` still run when you'd normally run them. The reviewer is on top of them, not instead.
- `/audit/*` is still the right tool for periodic broad sweeps. `/safe-edit` is per-change.

## Tone

Don't narrate the loop step-by-step in user-facing text. The user sees:
- Your normal coder updates (one sentence per significant step).
- A short "Round 1 review found N findings: [list]; applied them" or "Round 1 review came back clean."
- A short "Round 2 review came back clean — ready to commit. Want me to?" handoff.
- Or, if the loop terminates without consensus: a clear summary of what's still contested and a request for the user's call.
