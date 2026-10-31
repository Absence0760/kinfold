---
description: Sweep every logging and error-response path for identity, earnings, hardship, loan and evidence data leaking into logs, error bodies or an external sink
---

Audit every log call and error-response path for personal and financial data that must never be written to stdout/stderr, returned to a client, or shipped to an external log or error sink.

## Goal

Logs are the easiest place for regulated data to escape: verbose by default, fanned out to places the data model never intended (Supabase function logs, Postgres logs, an error tracker), and outliving the row they describe. `docs/STACK.md` § Domain rules makes loan amounts, income, hardship details and identity documents PII with audit-logged reads; a log line that echoes them is an unaudited read by everyone with log access.

Distinct from:
- `/audit/secrets`: credentials committed to git or inlined into the static bundle.
- `/audit/third-party-data-flows`: the *intended* sub-processor map.
- `/audit/storage`: who can fetch evidence objects.

Cross-reference those instead of re-reporting.

## What Kinfold must never log

- **Identity**: email, legal name, the KYC vendor's `provider_ref`, `auth.uid()` paired with any of those, IP address tied to a member.
- **Money and need**: verified earnings, subscription amount derived from earnings, loan principal and schedule, lender savings figures, hardship details, Home Fund needs-formula inputs.
- **Evidence**: unredacted photos or documents, their storage paths, OCR text, licence plates, addresses, account numbers, the other driver's insurer details.
- **Scoring inputs**: the full evidence bundle or prompt sent to the scoring model (the model, version, inputs and reasons are stored deliberately in the database; they are not log material).
- **Secrets / tokens**: JWTs, the service-role key, a bank-link or payment-partner token, any `Deno.env` value.
- **Bulk dumps**: `console.log(req.body)`, `console.error(err)` where `err` carries a row, `JSON.stringify(member)`, a whole Supabase response.

## What to check

1. **Edge functions (Deno), `apps/backend/supabase/functions/`** (to build, per `docs/backend.md` § Edge functions; if absent, say so and check nothing else here). `console.*` lands in Supabase's function logs. Highest risk: scoring, redaction, KYC callback, bank-link, payment-partner webhooks.
2. **Postgres.** `raise notice/log/exception` in SQL functions and triggers that interpolate PII columns; `log_statement` settings in `apps/backend/supabase/config.toml` that would log parameter values; audit-history tables that copy whole rows (`private.fund_settings_history` stores `to_jsonb(old)`: fine for fund settings, a finding if the pattern is reused on a PII table without a reason).
3. **External error sink.** If an error tracker is added, everything attached to an event (message, breadcrumbs, `extra`, request context) leaves for a third party. A leak there is **Critical**.
4. **Error responses.** A 4xx/5xx body that returns `err.message`, a SQL fragment, a row or a stack. Clients get a short code; detail stays server-side and is itself scrubbed.
5. **The web app, `apps/web/src/`.** Prerendered and static today, so the surface is `console.*` in shipped client code; flag any that would print member data once the member app exists, and any analytics call carrying PII.
6. **Scripts and seeds.** `scripts/`, `apps/backend/supabase/seed.sql` (if present): fixtures use obviously fake people; nothing logs real data.

## Report

- **Critical**: regulated data reaches an external sink or a client-facing error body.
- **High**: regulated data in a server log (function logs, Postgres logs); a bulk body/row dump on a path that carries PII.
- **Medium**: logging that *could* carry PII depending on input; scoring prompt or evidence path logged "for debugging".
- **Low**: pseudonymous ids logged (`request_id`, `member_id` alone) with no written redaction policy.

Each finding: `file:line`, the statement, which field it exposes (by name; **never paste a real value**), the sink, and the fix (log an id, not the value; scrub before capture; return a generic code).

## Delegate to

The `compliance-auditor` agent (`.claude/agents/audit/`): `"Audit every server-side logging and error-response path for identity, earnings, hardship, loan, evidence or secret data leaking into logs, error bodies or an external sink. Write the report to reviews/audit-pii-in-logs.md."` For an edge-function-heavy tree, also run the `repo-security-auditor` with area `pii`.

## Output → `reviews/`

Persist findings to `reviews/audit-pii-in-logs.md` (git-ignored; see `reviews/README.md`), one finding per entry with a `[ ]` status box, grouped by severity, updated in place on re-runs (`[x]` resolved with commit, `[~]` deferred with reason). Writing this one file is the only change the audit makes.
