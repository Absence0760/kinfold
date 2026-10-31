---
description: Generate a canonical inventory of everything Kinfold's Supabase backend exposes — PostgREST tables and views, RPC functions, storage buckets, edge functions — read from the migrations and function source, not the docs. Feeds the persona-integrator agent and an /audit/auth or /audit/rls pass.
---

Produce a canonical, table-shaped inventory of every surface the backend exposes by **reading the source** — not by trusting any doc.

Kinfold has no hand-written router. Its API surface is whatever Supabase exposes from `apps/backend/supabase`: PostgREST serves every table, view and function in the exposed schemas that a client role (`anon`, `authenticated`) has been granted; Storage serves buckets under their `storage.objects` policies; edge functions under `apps/backend/supabase/functions/` serve HTTP directly (none built yet — `docs/backend.md` § "Edge functions (to build)" lists the plan). The migrations in `apps/backend/supabase/migrations/` (read in timestamp order — a later migration can redefine a grant, policy or function) are the route source.

`docs/backend.md` § Access model describes the intended surface; this command records the actual one, so the two can be diffed. It flattens it into one artifact consumers can read without spelunking the migrations.

This is a **generator**, not a findings audit. It describes what the API *is*; it does not flag bugs. Read-only on the codebase except for writing the one output file.

## What it produces

`reviews/endpoint-inventory.md` — four tables:

1. **Tables and views** (PostgREST `/rest/v1/<name>`): name, schema, verbs granted to `anon` / `authenticated` (and column-level grants), RLS on/off, policies per verb in one line each, notes.
2. **RPC functions** (`/rest/v1/rpc/<name>`): name, args, returns, `security definer` or invoker, roles with `execute`, the auth check inside (e.g. `auth.uid()` owner check, `member_roles` role check, service-only), notes.
3. **Storage buckets**: bucket, public flag, size / MIME limits, `storage.objects` policies per verb.
4. **Edge functions** (`/functions/v1/<name>`): method, `verify_jwt` setting (`config.toml`), caller (member / reviewer / partner webhook / pg_cron), what it calls with `service_role`, request and response shape.

For tables 1–3 the columns map onto the generic shape below; for edge functions use it directly:

| Method | Path | Auth | Authz scope | Request params | Response shape | Notes |
|--------|------|------|-------------|----------------|----------------|-------|

Fill each column from the **actual handler code**, never inferred from a doc or a name:

- **Method** — for tables, the verbs granted (`select` → GET, `insert` → POST, `update` → PATCH, `delete` → DELETE); RPCs are POST; edge functions per their handler.
- **Path** — the full path as Supabase serves it (`/rest/v1/<table>`, `/rest/v1/rpc/<fn>`, `/storage/v1/object/<bucket>/…`, `/functions/v1/<name>`).
- **Auth** — `anon`, `authenticated`, `service_role` only, or a partner signature, read from the grants / `verify_jwt` / the function body itself — classify each object individually.
- **Authz scope** — how access is scoped: the RLS policy (owner via `auth.uid()`, verified member, invited supporter, reviewer / panel via `member_roles`, service-only) or the check inside a definer function / edge function. Flag the exceptions explicitly — a granted object with RLS off, a `using (true)` policy, a definer function that trusts a member-id argument, an edge function that uses `service_role` without re-checking ownership. These are inputs for `/audit/auth` and `/audit/rls`; note them, don't fix them here.
- **Request params** — path params, query params (the real casing the handler reads), and the request body shape for writes. Use the names the handler actually reads, not the doc's names.
- **Response shape** — the response type/schema the handler returns when one is declared; for surfaces with no typed client (webhooks, redirects, raw payloads) say so plainly (e.g. `204 No Content`, `302 → …`, `{ status: "ok" }`, `SVG`).

Then two short cross-reference sections against the client/consumers:

- **Partner- and schedule-facing surface.** Edge functions called by partners (webhooks) or pg_cron rather than a member client. Call these out as the integrator-facing surface.
- **Design drift.** Differences between the actual grants and `docs/backend.md` § Access model (an object `anon` can read that the doc doesn't list, a documented capability with no grant). Today there is no member client (the Flutter app in `apps/mobile` is planned; `apps/web` does not call the backend), so client-call drift is "n/a"; once a client exists, also list client calls (`.from()`, `.rpc()`, `functions.invoke`) that resolve to nothing.

## Procedure

1. **Prefer the live catalogue.** If the local stack is up (`pnpm dev:db:status`), query it — it is the exact result of every migration: `information_schema.role_table_grants`, `information_schema.column_privileges`, `information_schema.routine_privileges`, `pg_policies`, `pg_class.relrowsecurity`, `pg_proc.prosecdef`, `storage.buckets`, and `pg_policies` on `storage.objects`. Use `pnpm dev:db:psql` (read-only queries only). If the stack is down, don't start or reset it — fall back to step 2.
2. **Otherwise read the migrations in order.** Every `create table` / `create view` / `create function` / `grant` / `revoke` / `create policy` / `insert into storage.buckets` in `apps/backend/supabase/migrations/`, applying later redefinitions over earlier ones.
3. **Read `apps/backend/supabase/config.toml`** — `[api] schemas` (which schemas PostgREST exposes; `private` must not be one), `[functions.<name>] verify_jwt`, `[storage]` limits.
4. **Read each edge function** under `apps/backend/supabase/functions/` (if any): its HTTP method handling, auth check, which service-only RPCs it calls.
5. **Write `reviews/endpoint-inventory.md`** (overwrite if present). Lead with a one-line note: *generated from the migrations / local catalogue on `<date>`; regenerate after every migration or new edge function.* This artifact can be **promoted to `docs/`** as a maintained, committed inventory if the team wants it under version control — `reviews/` is typically gitignored, so by default it's a working snapshot.

**Delegate to** the `Explore` (or `general-purpose`) agent: pass this file as the prompt. The agent reads the catalogue or migrations, `config.toml` and the edge functions, and writes the single output file. Read-only on the rest of the codebase — no other edits, no git.

## Notes

- This is a generator, not an audit. It records the current state; it does not grade auth coverage or RLS discipline. For findings, pair it with **`/audit/auth`** and **`/audit/rls`**, and hand the table to the **`persona-integrator`** agent, which consumes the integrator-facing surface it surfaces.
- Types are generated (`pnpm gen:types` → `apps/backend/supabase/database.types.ts`); if that file is stale against the catalogue, note it.
- **Re-run after every migration or new edge function** — a new grant or function makes the inventory stale immediately, and any consumer working from it starts from an out-of-date list.

## Guard rails

Read-only / generator — no commits required beyond writing the one artifact. If you do commit it, path-scope the commit (`git commit -m "…" -- reviews/endpoint-inventory.md`). **Never `git push`.**
