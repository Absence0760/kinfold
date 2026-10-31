---
description: Add or land a Supabase migration with the migration-coordinator agent in the loop. Applies locally (pnpm dev:db:reset), verifies RLS + explicit grants + the public/private split + cents-only money, surfaces type-sync edits, proposes pgTAP tests, flags doc updates.
argument-hint: <migration slug or path>
---

Run the new-migration workflow for `$ARGUMENTS`. Either author + coordinate the migration, or coordinate one the user has already drafted.

## When to use this command

**Right fit:**

- About to add a new file under `apps/backend/supabase/migrations/`
- Just finished drafting a migration and want to verify before committing
- Modifying an unmerged migration and want to re-run the coordination steps

**Wrong fit — refuse:**

- Already-merged migrations (don't try to coordinate history)
- Pure data-backfill SQL with no schema change (run as a one-off, not a timestamped migration)

## What this command does

It is **not** the per-change reviewer (`/safe-edit`). It is the per-migration workflow that catches drift the reviewer can't easily see — RLS and policies on every new table, explicit grants (Supabase's default "grant all to anon, authenticated" is revoked at the end of each migration), anything clients must never read living in `private`, `security definer` functions pinning `search_path = ''`, money as `bigint` cents with no interest column anywhere (the conventions header of `apps/backend/supabase/migrations/20261030120000_members.sql`), regenerated types (`pnpm gen:types` → `apps/backend/supabase/database.types.ts`, committed), the rule table in `docs/backend.md` § "Where each rule is enforced" (a new invariant gets a row and a pgTAP test), and which pgTAP tests under `apps/backend/supabase/tests/` need to grow.

The actual work is done by the `migration-coordinator` agent. This command is the orchestrator: figure out which migration we're talking about, invoke the agent, then prompt the user for the follow-up edits.

## Procedure

### 1. Resolve the migration

If `$ARGUMENTS` is:

- A **path** under `apps/backend/supabase/migrations/` → use that file directly.
- A **slug** without a timestamp → propose `apps/backend/supabase/migrations/<YYYYMMDDHHMMSS>_<slug>.sql` (UTC, later than the newest existing file — `supabase migration new <slug>` from `apps/backend` generates the name). If the file doesn't exist yet, ask the user to draft it first (or prompt them with a starter template) — do not invent SQL on their behalf.
- **Empty** → run `git status` + `ls apps/backend/supabase/migrations/` and identify the new or modified `.sql` file. If there's no candidate, abort with "no migration to coordinate."

### 2. Spawn the migration-coordinator agent

Once you have a concrete file path, invoke the agent with the prompt:

> "Coordinate the migration at `apps/backend/supabase/migrations/<file>`. Apply it locally (`pnpm dev:db:reset`), verify RLS, grants and the public/private split on every new object, check money columns are bigint cents, run `pnpm test:backend:db`, run `pnpm gen:types` and check the diff of `apps/backend/supabase/database.types.ts`, propose pgTAP additions, and flag doc updates (`docs/backend.md`). Output the format from your spec."

### 3. Relay the agent's report

The agent's output is the deliverable — relay it verbatim to the user. Do not summarise away the file paths or the proposed field signatures; those are the actionable bits.

### 4. Offer to apply the follow-up edits

After the agent returns, ask the user one focused question:

> "Want me to commit the regenerated `apps/backend/supabase/database.types.ts` with the migration, and apply the client edits the agent proposed? [...]"

If yes, apply only the proposed changes (no scope creep into adjacent interfaces). If no, end the turn — the user will handle it.

Same offer for the pgTAP test stubs and doc updates, in that order. Each is opt-in.

### 5. Hand off the commit

When all the follow-up edits the user accepted are applied, hand off:

> "Ready when you are. Suggested commit: `feat(db): <slug>` — want me to commit it path-scoped?"

Commit path-scoped (`git commit -m "…" -- <paths>`), never push. Match the recent log's style — `feat(db):` for new tables/columns, `fix(db):` for corrective migrations, `chore(db):` for index-only or trigger-only changes. **No `Co-Authored-By` / "Generated with Claude Code" / robot-emoji footers** — user-level rule overrides any project default.

## What this command does NOT replace

- `/audit/rls` and `/audit/migration-locks` — broad sweeps over **all** migrations. `/safe-migration` is per-migration.
- `/check` — pre-commit gate that runs once you're ready to commit. Use it after `/safe-migration` if you want the doc-hygiene + test-gap pass on the working diff.
- `/safe-edit` — coder ↔ reviewer loop for non-migration changes. The two are complementary; for a migration that also lands an edge function or web code backed by the new table, run `/safe-migration` first, then `/safe-edit` on the rest. A migration that touches money or scoring tables also gets `money-path-reviewer` / `scoring-fairness-reviewer` via `/check`.

## Tone

User-facing text:

- A one-line "Coordinating migration `<file>`…"
- The agent's verbatim report.
- The opt-in follow-up questions, one at a time.
- The commit handoff.

Don't narrate the agent fan-out or repeat the agent's findings in your own words.
