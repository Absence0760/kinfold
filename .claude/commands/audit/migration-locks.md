---
description: Audit the production safety of DDL in apps/backend/supabase/migrations: blocking locks, table rewrites, and CONCURRENTLY inside a wrapped transaction
---

Audit `apps/backend/supabase/migrations/*.sql` for online-DDL safety: classify each DDL statement by the Postgres lock it takes and the work it does, and flag the ones that would block writes or rewrite a table when applied to a populated production database, not the empty local one where everything is instant.

## Goal

Locally, `pnpm dev:db:reset` rebuilds an empty database and every statement looks free. In production the tables that grow are the ones members depend on in a bad week: requests, evidence, scores, contributions, repayment schedules and the audit/history tables. A migration that holds `ACCESS EXCLUSIVE` on one of those blocks every read and write for its duration.

**Kinfold has no production database yet.** Run this audit anyway: it sets the baseline, and the cheapest time to adopt the online forms is before there's data. Say plainly which findings only start to matter once a table has rows.

Distinct from `/audit/rls` (policy and grant coverage) and `/audit/db-performance` (whether an index should exist). Here the question is: given this DDL runs, *what does it lock, and for how long*.

## What to check

1. **`add column` with a default.** Constant defaults are metadata-only on PG11+ (the database is Postgres 17, `apps/backend/supabase/config.toml` `major_version`). A **volatile** default (`now()`, `gen_random_uuid()`, a function) on an existing table rewrites it. Fine inside a brand-new `create table`.
2. **Add / backfill / `set not null`.** `set not null` scans under `ACCESS EXCLUSIVE`. Recommend `add constraint … check (col is not null) not valid`, `validate constraint`, then `set not null`.
3. **`alter column … type`.** Rewrites the table and its indexes. High against a populated table; recommend add-new-column, batched backfill, swap.
4. **Constraints and FKs without `not valid`.** Single-step `add constraint` scans every row under a strong lock. Watch especially for enum-style allowlists widened by drop + re-add, and for `alter type … add value` on the enums in the first migration (`public.request_kind`, `public.member_status`, …): adding an enum value is cheap, but it can't be used in the same transaction that added it.
5. **`create index` vs `create index concurrently`.** A plain build blocks writes for the whole build.
6. **`concurrently` inside a transaction.** It errors inside a transaction block. Check how the apply path wraps migration files (Supabase CLI) before asserting; a `concurrently` statement likely needs its own migration file.
7. **Backfills inside a migration.** Unbatched whole-table `update`/`delete` on a growing table; recommend batching.
8. **Triggers and history tables.** A trigger added to a hot table (the `private.log_fund_settings_change` pattern) adds write cost on every row; fine on `fund_settings`, worth a note if copied onto requests or contributions.
9. **Many strong locks in one file.** Widens the blocking window and deadlock surface; suggest splitting.

## Report

- **High**: rewrites or holds `ACCESS EXCLUSIVE` on a table that will be large (requests, evidence, scores, contributions, schedules, history), or a `concurrently` that will fail inside the wrapped apply.
- **Medium**: a real but brief or bounded lock that the online form avoids.
- **Low**: style; a plain index on a table that will stay small (e.g. `fund_settings`, one row per fund).

Each finding: `file:line`, the statement, the lock and table, what happens against a populated table, and the safe rewrite. Migrations only move forward: fixes are new timestamped files, never edits to applied ones.

## Delegate to

The `migration-coordinator` agent (`.claude/agents/engineering/`) in audit mode: `"Audit migration lock impact and online-DDL safety across apps/backend/supabase/migrations; classify each statement by Postgres lock and rewrite cost against a populated table. Read-only: do not apply or edit migrations. Write the report to reviews/audit-migration-locks.md."` Land any forward fixes through `/safe-migration`.

## Output → `reviews/`

Persist findings to `reviews/audit-migration-locks.md` (git-ignored; see `reviews/README.md`), one finding per entry with a `[ ]` status box, grouped by severity, updated in place on re-runs. Writing this one file is the only change the audit makes.
