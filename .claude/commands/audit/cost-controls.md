---
description: Verify spend safeguards across the AI legitimacy scorer, Supabase, edge functions, hosting and partner APIs — no single failure should produce a runaway bill
---

Audit every layer that bounds runaway spend. Kinfold's realistic cost-vector accidents: a leaked AI scorer key, a scoring loop that re-scores the same request on every evidence edit, a member (or bot) uploading thousands of evidence files to trigger thousands of scoring and redaction calls, a Supabase plan overrun from storage or egress, an edge function stuck in a retry loop against a partner API, a CloudFront egress flood. Each one should be capped by **at least one** independent ceiling — none should run unbounded for hours before someone notices.

## Goal

Kinfold is pre-launch: today only `apps/web` exists (a prerendered static site, no backend calls, no env vars) and `apps/backend/supabase` holds an early schema. So most checks below will report "not present yet" — that is a valid result. The value of running this now is to name the ceilings that must land **in the same change** as the thing that spends money (root `CLAUDE.md` § Local-first: each external dependency ships with a local equivalent and a default that points at it, so dev never spends real money either).

A finding is anything that lets the bill exceed expected spend by an order of magnitude before any alarm fires.

## What to check

### 1. AI legitimacy scorer (biggest variable cost)

The scorer (`score-request` edge function in `docs/backend.md`; production model not chosen yet, `docs/design.md` § Open questions; local stand-in is Ollama) reads evidence — photos, PDFs, reports — and returns a 0–100 score with reasons. Token cost scales with evidence size and with how often a request is scored.

- **When does scoring run?** When a request's status becomes `scoring` (on submit and resubmit), not on every upload, keystroke or page view. A trigger or realtime subscription that calls the scorer per row change is High.
- **Idempotent by input.** A score is keyed on (request, evidence set hash, model version); re-submitting the same evidence returns the stored score instead of calling the model again.
- **Per-member and global caps.** A per-member daily scoring cap and a global daily cap, enforced server-side (in the edge function or the DB), not in the web UI.
- **Input size bounded.** Max files per request, max file size, max pages per PDF, images downscaled before they're sent. Uploading a 500-page PDF must not produce a 500-page prompt.
- **Provider-side cap.** The provider console has a monthly spend limit set. Surface as a manual check — the audit cannot see it.
- **Local default.** Dev and CI score against a local model or a deterministic stub, never the paid API (root `CLAUDE.md` § Local-first). A dev path that needs a real key is a finding.
- See `/audit/llm-endpoint` for prompt-injection and data-minimisation checks on the same endpoint.

### 2. Redaction pipeline

Automatic redaction (`redact-evidence` edge function, `docs/backend.md`; faces, plates, names, account numbers) may be a paid vision API or a self-hosted model; locally it is open-source face and plate detection. Same questions as the scorer: runs once per file, cached by content hash, bounded input size, capped per member and globally.

### 3. Supabase

- **Plan and spend cap.** Hosted Supabase projects have a spend cap toggle; confirm it is on (manual check) or that a deliberate decision to turn it off is recorded.
- **Storage growth.** Evidence buckets (`apps/backend/supabase/config.toml` `[storage]`, bucket definitions in migrations) set `file_size_limit` and `allowed_mime_types`. Unlimited size on a bucket members write to is High.
- **Egress.** Evidence images served through signed URLs with sensible expiry and image transformations (thumbnails) rather than full originals on list views.
- **Database.** No unbounded `select *` exposed to `anon` via PostgREST that a scraper can page through cheaply (`[api] max_rows` in `config.toml` is set).
- **Auth.** `[auth.rate_limit]` in `config.toml` caps sign-ups, sign-ins, OTPs and email sends; SMS sign-in (paid per message) stays off unless deliberately enabled.

### 4. Edge functions (planned under `apps/backend/supabase/functions/`; list in `docs/backend.md` § "Edge functions (to build)")

- The pg_cron-scheduled ones (`run-pool` weekly; `reconcile`, `loan-servicing`, `expire-requests` daily) run on a fixed schedule and process a bounded batch per run; none re-schedules itself in a loop.

- Each function that calls a paid API has a timeout and **no unbounded retry**; retries are capped with backoff and a failure is recorded, not looped.
- Webhook handlers (payment partner, KYC vendor) are idempotent by event id, so a partner's retry burst doesn't re-trigger paid work.
- Functions reachable without a JWT are only webhooks with signature verification.

### 5. Partner APIs

Payment partner, KYC vendor and bank-link (earnings verification) provider are not chosen yet. When they land:

- KYC checks are charged per check: one verification per member, re-run only on a defined trigger, never on each sign-in.
- Bank-link calls (earnings verification for the subscription) on a schedule bounded per member, not per page view.
- Payment partner fees are per transaction and legitimately scale with use; the denial-of-wallet path is creating many payment intents that are never completed — cap intent creation per member.

### 6. Hosting (once `infra/` exists)

`apps/web` builds to static files for S3 + CloudFront (`docs/STACK.md`). When the Terraform lands:

- An `aws_budgets_budget` with `ACTUAL > 50%`, `ACTUAL > 100%` and `FORECASTED > 100%` notifications to a real address. Missing forecasted → High.
- CloudFront `price_class` is `PriceClass_100` (US audience) unless justified.
- S3 lifecycle expiring non-current versions.
- Log groups have `retention_in_days` set.

Until `infra/` exists, report this section as "not applicable yet".

### 7. Documentation matches reality

Once a cost model exists in `docs/`, it matches the configured caps. Today there is none; recommend one alongside the first paid dependency.

## Report

- **Critical** — a paid API (scorer, redaction, KYC) reachable without auth or without any cap; a scoring trigger that fires per row change; a paid key in a path that retries unboundedly.
- **High** — no per-member scoring cap; evidence bucket with no size limit; no AWS budget forecast alert (once infra exists); dev path that requires a paid key.
- **Medium** — scores not cached by input hash; no `max_rows`; auth rate limits left at defaults without review.
- **Low** — provider console caps unconfirmed; cost doc missing.

For each finding: file:line + the concrete change. Don't apply fixes without explicit confirmation.

## Useful starting points

- `docs/design.md` § "3. Legitimacy score", § "2. Upload evidence", § Open questions
- `apps/backend/supabase/config.toml` — `[api]`, `[storage]`, `[auth.rate_limit]`, `[edge_runtime]`
- `apps/backend/supabase/migrations/` — bucket and trigger definitions
- `apps/backend/supabase/functions/` — once it exists

## Delegate to

`general-purpose` agent with this file as the prompt body. Cross-cuts code, config, docs and provider-console gaps, so it doesn't fit one of the specialised auditors.

Read-only. Findings only. The audit must NOT call a paid API, run `terraform plan`, or load-test anything — a load test against the scorer is itself a spend event.
