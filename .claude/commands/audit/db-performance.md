---
description: Audit Postgres indexing and query patterns: missing, redundant or unused indexes, composite-column order, N+1 query shapes, and queries that will seq-scan as data grows
---

Audit the indexes in `apps/backend/supabase/migrations/*.sql` and the queries that hit them (supabase-js `.from()`/`.rpc()` calls in `apps/web`, edge functions under `apps/backend/supabase/functions/`, SQL functions and RLS policy subqueries): is every hot path indexed, is the index set right-sized, and will any query shape table-scan as requests and contributions grow?

## Goal

A query-performance audit. Distinct from `/audit/migration-locks` (whether *adding* an index blocks production) and `/audit/rls` (policy coverage). One overlap: **RLS policies are queries too.** A policy like `auth.uid() = member_id` runs on every row read; without an index on `member_id` every member's request list scans the table.

**Kinfold is pre-launch with one migration and no member-app queries yet.** Report what applies, mark row-count-dependent claims "confirm against real data", and don't invent hot paths; derive them from `docs/design.md` and the code that exists.

## What to check

1. **Hot paths from the design** (once their tables exist):
   - **The members-only board** (`board_requests`): requests by status ordered by score band and time.
   - **Pool allocation**: requests by fund and score band ≥ `fund_settings.min_score` (the band rule in `apps/web/src/lib/requests/allocation.ts`); a scan here runs every allocation cycle.
   - **A member's own requests, loans and schedules**: by `member_id` (also the RLS predicate).
   - **Reviewer queues**: by status and region, excluding the reviewer's own region.
   - **Fraud cross-checks**: photo fingerprint lookups across all requests (design.md § Fraud-proofing) need an index fitting the fingerprint type, not a scan.
2. **RLS predicate columns indexed.** Every column a policy compares to `auth.uid()` or joins through.
3. **Foreign keys indexed.** Postgres doesn't index the referencing side; deletes on `public.members` (cascading from `auth.users`) scan every child table without one.
4. **Composite ordering.** Equality columns first, then range/sort. Flag queries that filter on a composite's second column alone.
5. **Redundant indexes.** `(a)` when `(a, b)` exists.
6. **Unused / speculative indexes.** No matching query in the codebase; suggest `pg_stat_user_indexes.idx_scan = 0` as confirmation once there's a production database.
7. **N+1 in application code.** A loop issuing one query per item (fetch requests, then each request's evidence or score separately) instead of an embedded select or `in (…)`.
8. **Scan-at-scale shapes.** `ilike '%x%'` search, deep `offset` pagination on the board, `order by` an unindexed column with `limit`, jsonb filters into score reasons with no expression index.
9. **Function cost.** `security definer` and trigger functions: no per-row whole-table subqueries.

## Report

- **High**: a hot, member-facing path (board, allocation, own requests, reviewer queue) or an RLS predicate that will seq-scan a growing table; an N+1 on a per-request path.
- **Medium**: missing FK index, redundant or mis-ordered composite, deep-offset pagination.
- **Low**: speculative index that's cheap to keep; a bounded query worth a note.

Each finding: the index or query `file:line`, the table and its growth profile, why it scans / is redundant / is N+1, and the concrete fix (the exact `create index` with column order, noting `/audit/migration-locks` governs how to add it; the rewritten query).

## Delegate to

This is a performance lens, not a security or compliance one, so use a `general-purpose` agent with this file's body as the prompt: `"Audit Postgres indexing and query performance for Kinfold per .claude/commands/audit/db-performance.md. Read-only. Write the report to reviews/audit-db-performance.md."`

## Output → `reviews/`

Persist findings to `reviews/audit-db-performance.md` (git-ignored; see `reviews/README.md`), one finding per entry with a `[ ]` status box, grouped by severity, updated in place on re-runs. Writing this one file is the only change the audit makes.
