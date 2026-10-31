---
description: Sweep Supabase RLS policies, grants, the private schema and SECURITY DEFINER functions for missing or weak auth checks
---

Audit Row-Level Security, table/function grants and `security definer` functions across `apps/backend/supabase/migrations/`.

## Goal

Kinfold stores identity references, earnings, hardship details, loan amounts and unredacted evidence. One missing `auth.uid()` check, one leftover Supabase default grant, or one table in `public` that belonged in `private` is a mass-exfiltration bug. Find every table without RLS, every policy broader than its documented intent, every grant that exceeds what the client needs, and every definer function that doesn't gate on the caller.

## The conventions this audit checks against

They are written at the top of `apps/backend/supabase/migrations/20261030120000_members.sql` and apply to every migration:

- Money is `bigint` cents; there is no interest column anywhere (out of scope here; see `/audit/money-path`).
- **Clients get explicit grants only.** Supabase's default "grant all to anon, authenticated" is revoked at the end of each migration.
- **Anything clients must never read through the API lives in `private`**, and `private` is revoked from `public`, `anon` and `authenticated`.
- **Security definer functions pin `search_path = ''`** and schema-qualify every name.

Plus the domain rules in `docs/STACK.md` § Domain rules: identity, income, hardship and loan data are PII with least-privilege, audit-logged reads; shared evidence is redacted, originals private; the giving record is private; lending and protection data stay separate.

## What to check

1. **RLS on every `public` table.** For every `create table public.*`, confirm `enable row level security` in the same migration and at least one policy. A table with RLS and no policy denies everything, including its owner; that's a bug if the app reads it.
2. **Default grants revoked.** Every migration ends by revoking Supabase's default privileges (tables, sequences, functions) from `anon` and `authenticated`, then grants back exactly what each table needs. A migration that creates a table without the revoke leaves it fully writable by any signed-in user (and readable by `anon`) wherever RLS is missing or permissive. Compare grants against `docs/` intent and the web code that queries the table.
3. **`private` schema discipline.** `private` has no `usage` grant to `anon`/`authenticated`; no view in `public` selects from `private` without `security_invoker = true` or an equivalent gate; no `public` function returns `private` rows to a caller who shouldn't see them. Identity (`private.member_identity`), audit history (`private.fund_settings_history`) and unredacted evidence belong here.
4. **Policy strength.** Classify each policy: owner-only (`auth.uid() = member_id`), role-gated (reviewer / panel / admin via `public.member_roles`), anon-read (only the open-books objects in `docs/backend.md` § Access model: fund rules, subscription formulas, `pool_runs`, `public_stats`), verified-member read (the `board_requests` view: redacted summary, kind, amount, score, state, week), service-role-only. Flag any `using (true)`, any public-read that exposes a PII column, and any reviewer policy that lets a reviewer see their own region's requests (design.md § Fraud-proofing: reviewers never see their own region).
5. **`security definer` functions.** For each: `set search_path = ''`, every name schema-qualified, the body checks `auth.uid()` against the resource owner or role, or is documented as caller-agnostic (e.g. a trigger function like `private.log_fund_settings_change`). Execute is revoked from `public` and granted only to the roles that need it.
6. **`grant execute ... to anon`.** Anon execution of any function needs a per-function justification.
7. **Policy chains.** A `using (... in (select ... from other_table))` relies on `other_table`'s RLS; check for recursion and for leaking hidden rows.
8. **Pool separation at the DB layer.** Policies and functions must not let a path read or write across the protection pool, Home Fund and people-to-people lending data (STACK.md § Domain rules: the money pools stay separate).
9. **Tests with positive controls.** Every "cannot see" pgTAP test under `apps/backend/supabase/tests/` pairs with a "can see" case for the rightful owner/role; a deny-only test passes against a table nobody can read. If the tests directory doesn't exist yet, say so as a finding against the tables it should cover.

## Report

- **High**: `anon` or any authenticated member can read or write data they shouldn't (PII, another member's request internals, unredacted evidence, a fund setting).
- **Medium**: overscoped but no concrete leak today (`using (true)` on a table with no PII yet, a grant wider than any client use).
- **Low**: undocumented policy intent, a definer function without a comment saying why it's definer.

Each finding: file:line, the policy/function/grant, what's missing, the worst-case blast radius, and the forward fix (a new migration; applied migrations are never edited). Report only; don't edit migrations without explicit instruction.

## Useful starting points

- `apps/backend/supabase/migrations/` in order; the header of the first migration states the conventions
- `apps/backend/supabase/config.toml` (`[api] schemas`, `extra_search_path`: confirm `private` is not exposed through the API)
- `apps/backend/supabase/tests/` (pgTAP; `rls_test` and the suites in `docs/backend.md` § Where each rule is enforced)
- `docs/backend.md` § Access model — the role-by-role spec every policy is checked against
- `docs/design.md` § Fraud-proofing, § Risks and safeguards

## Delegate to

The `repo-security-auditor` agent (`.claude/agents/audit/`), area `rls`, with the audit as the prompt's first sentence: `"Audit RLS policies, grants, the private schema and SECURITY DEFINER functions for missing or weak auth checks."`

## Output → `reviews/`

Persist findings to `reviews/audit-rls.md` (git-ignored working notes; see `reviews/README.md`), one finding per entry with a `[ ]` status box, grouped by severity. If the file exists from a prior run, update it in place (`[x]` resolved with the fix commit, `[~]` deferred with reason) instead of overwriting. Writing this one file is the only change the audit makes.
