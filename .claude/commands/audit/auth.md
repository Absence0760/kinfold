---
description: Sweep every Supabase-exposed surface (tables, views, RPCs, storage buckets, edge functions) for auth gating, explicit grants, and RLS keyed on auth.uid()
---

Audit auth gating and per-member data isolation across the Kinfold backend.

## Goal

Kinfold's backend is Supabase (`apps/backend/supabase`). There is no hand-written API router: PostgREST exposes whatever the `anon` and `authenticated` roles are granted, and RLS decides which rows each caller sees. So the two bug classes are:

1. **A grant or policy too wide** — an object reachable by `anon` (or by any `authenticated` member) that should be owner-only, staff-only or private. One missing `enable row level security` or one `using (true)` exposes every member's rows.
2. **A path that skips RLS** — a `security definer` function, an edge function using the service-role key, or a storage bucket policy that doesn't re-check that the caller owns the resource.

Find both classes in one pass. The intended model is written down in `docs/backend.md` § Access model (who can do what, per role) and § Architecture (edge functions run as `service_role` and are the only callers of service-only functions: `record_score`, `run_pool_allocation`, `apply_default_plan`, `private.post_journal`); every status change goes through a `security definer` function. Kinfold's migration conventions (header of `apps/backend/supabase/migrations/20261030120000_members.sql`) are the baseline: Supabase's default "grant all to anon, authenticated" is revoked at the end of every migration and clients get explicit grants only; anything clients must never read lives in the `private` schema; `security definer` functions pin `search_path = ''` and qualify every name.

## What to check

1. **Grants inventory.** For every object in `public` (tables, views, sequences, functions), list what `anon` and `authenticated` are granted. Against a running local stack (`pnpm dev:db:up`; DB on port 54722) query `information_schema.role_table_grants` and `information_schema.routine_privileges`; otherwise read the `grant` / `revoke` statements in each migration in order. Anything granted to `anon` must be on the documented list (fund rules, subscription formulas, `open_books` — `docs/backend.md` § Access model) and say so in a comment. The `board_requests` view is for **verified members only**, never `anon`. Each migration ends with the default-grant revoke — flag any that doesn't.

2. **RLS on every table.** Every table in `public` has `enable row level security` in the migration that created it, and at least one policy for each granted verb. A granted table with RLS off is Critical. Policies key on `(select auth.uid())`, and on member status / role where it matters (a `suspended` or `pending_verification` member must not post requests or fund them; reviewer / panel / admin powers come from the `member_roles` table, never from a JWT claim the client can set or from `user_metadata`).

3. **The `private` schema stays private.** `usage` on `private` is revoked from `public, anon, authenticated`. Identity (`private.member_identity`), `private.fraud_signals`, `private.audit_log`, the `private.ledger_*` tables, settings history — no grant, no view in `public` that selects them without filtering to the owner, no `security definer` function that returns them to a non-owner.

4. **`security definer` functions.** Each one pins `search_path = ''`, revokes `execute` from `public`, grants only the roles that need it, and checks `auth.uid()` against the resource owner or role before acting — or is documented as intentionally caller-agnostic (e.g. a trigger function). A definer function exposed as an RPC that takes a member id argument and trusts it is Critical. The service-only functions listed above have `execute` granted to `service_role` only; `my_reliability()` and `my_giving_record()` return only the caller's own data.

5. **Resource-level checks on writes.** A member can only create a request for themselves, only add evidence to their own request, only pledge through `pledge` (which requires an accepted invite, and an active member for a loan), never write `contributions`, `payouts` or ledger rows directly, never verify a payee, and never set their own score, status, role or `verified_at`. Supporters read only the requests they were invited to; reviewers never their own or their own region's (`record_review`). Check `with check` clauses as well as `using` — an UPDATE policy without `with check` lets a member move a row to another owner.

6. **Storage buckets.** Per `docs/backend.md` § Access model: `evidence-original` holds files under the member's own folder and is readable only by that member — reviewers get short-lived signed URLs from the `evidence-url` edge function, which writes `private.audit_log`; `evidence-redacted` is readable by the owner and by verified members once the request is on the board. Policies on `storage.objects` key on the folder prefix and `auth.uid()`. Any bucket marked public, or a reviewer policy granting direct read on originals, is Critical (`docs/STACK.md` § Domain rules: shared evidence is redacted; originals are private). `/audit/storage` goes deeper.

7. **Edge functions** (planned under `apps/backend/supabase/functions/`; the list is `docs/backend.md` § "Edge functions (to build)"). Each one either verifies the caller's JWT (`verify_jwt` left on in `config.toml`, or an explicit `supabase.auth.getUser()`), or is a partner webhook that verifies the partner's signature over the raw body with a constant-time compare. A function that creates a service-role client must re-implement the ownership check RLS would have done; one that doesn't is Critical.

8. **Auth config.** `apps/backend/supabase/config.toml` `[auth]`: email confirmation on, sign-up policy matches the design (no anonymous requests — `docs/design.md` § Fraud-proofing), JWT expiry sane, `site_url` / redirect allowlist not wildcarded, rate limits set. MFA for reviewer / panel / admin roles once those UIs exist.

9. **Reviewer separation.** Per `docs/design.md` § Fraud-proofing, reviewers never see their own region's requests and never review their own. Once review tables exist, confirm the policy enforces it in the database, not only in the UI.

## Report

Group findings by severity:

- **Critical** — a table, view, RPC, bucket or edge function exposes one member's data (or `private` data) to `anon` or to another member; a member can write their own score / status / role; a service-role path with no ownership check.
- **High** — RLS on but a policy is `using (true)` for a sensitive verb; an UPDATE policy without `with check`; a definer function missing `search_path = ''` or the `public` execute revoke; a webhook without signature verification.
- **Medium** — a migration missing the default-grant revoke; an `anon` grant with no comment saying why it's public; role checks read from client-editable claims.
- **Low** — a public-by-design object missing its explanatory comment.

For each: migration file:line (or function path), the concrete fix, the worst-case blast radius. If a surface doesn't exist yet (functions, buckets), say "not present yet".

## Useful starting points

- `apps/backend/supabase/migrations/` — read in timestamp order; later migrations may redefine a policy or function
- `apps/backend/supabase/config.toml` — `[auth]`, `[storage]`, `[api]` (`schemas` exposed, `extra_search_path`)
- `apps/backend/supabase/tests/` — pgTAP tests (`rls_test` and siblings); every "cannot see" test should have a positive control
- `docs/backend.md` § Access model, § Architecture, § "Where each rule is enforced"
- `docs/STACK.md` § Domain rules
- `docs/design.md` § Fraud-proofing

## Delegate to

Use the `repo-security-auditor` agent: `"Audit auth gating, grants and RLS across every Supabase-exposed surface (tables, views, RPCs, storage buckets, edge functions)."`

Read-only. Findings only.
