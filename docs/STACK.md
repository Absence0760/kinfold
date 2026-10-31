# Stack

Kinfold is at the design stage. The product design lives in [design.md](design.md); read it before writing any code. The data model, invariants and edge functions live in [backend.md](backend.md).

## What exists today

A pnpm workspace (`apps/*`), laid out like `project-stocks`:

| Workspace | What it is | Port |
| --- | --- | --- |
| `apps/web` | SvelteKit 5 marketing / preview site: landing page, request board demo and savings calculator. `adapter-static` with every route **prerendered** to HTML (a public site, unlike project-stocks' auth-gated SPA). Does not call the backend; no env vars. | 7790 |
| `apps/backend` | Supabase (Postgres 17, Auth, Storage, Edge Functions) for the member app. Local stack via the Supabase CLI in Docker. Migrations in `supabase/migrations`, pgTAP tests in `supabase/tests`. | API 54721, DB 54722, Studio 54723, Mailpit 54724 |

Code layout in `apps/web/src/lib`: `finance/` (loan maths, pure and tested), `requests/` (community-pool allocation by legitimacy band, pure and tested), `core/` (formatting), `landing/` (page sections). Styling is plain CSS with design tokens in `src/app.css` (light and dark via `prefers-color-scheme`); no CSS framework.

## Commands

| Command | Does |
| --- | --- |
| `pnpm setup` | Install deps and the gitleaks pre-commit hook. The backend also needs Docker running and the Supabase CLI |
| `pnpm dev:db:up` / `dev:db:down` | Start / stop the local Supabase stack |
| `pnpm dev:db:reset` | Re-apply every migration and `seed.sql` to the local DB |
| `pnpm dev:db:status` | Local URLs, ports and keys of the running stack |
| `pnpm dev:db:psql` | `psql` into the local DB on 127.0.0.1:54722 |
| `pnpm dev:db:studio` | Open Supabase Studio on http://127.0.0.1:54723 |
| `pnpm dev:run:web` | Dev server on http://localhost:7790 |
| `pnpm build:web` | Prerender to `apps/web/build/` (deployable to S3 + CloudFront as-is) |
| `pnpm preview:web` | Serve the production build on 7790 |
| `pnpm check` | svelte-check typecheck |
| `pnpm test` | Vitest unit tests + the root-scripts guard + pgTAP (needs `dev:db:up` first) |
| `pnpm test:backend:db` | pgTAP only: schema, invariants, RLS |
| `pnpm gen:types` | Regenerate `apps/backend/supabase/database.types.ts` from the local schema; commit the result |

## Backend

`apps/backend` is a Supabase project. Migrations live in `apps/backend/supabase/migrations` and pgTAP tests in `apps/backend/supabase/tests`; change the schema through a new migration plus a test, then `pnpm gen:types`. The schema overview, the invariants the database enforces and the edge functions are in [backend.md](backend.md).

## Clients

- **Member app: Flutter, planned** as `apps/mobile` (the estate `mobile-fullstack` pattern, as in project-stocks). Evidence capture needs the phone camera with device attestation, which a web page can't give.
- **Reviewer console: planned** as authenticated routes in a later web app, not in the public marketing site.

## Domain rules

These come from `design.md` and apply to every line of code:

- **No interest and no late fees in any code path.** A repayment schedule only ever sums to the principal. Where tax law needs a minimum rate on a family loan, it is calculated, shown, and set up to be forgiven as a gift.
- **The app never holds member money.** In Phase 1 money moves between people through a payment partner; Kinfold stores records, documents and schedules. Pooled money (community pool, Home Fund) only ever sits with a licensed partner, reached through their API.
- **Pay the payee, not the member.** Damage requests pay the named shop against its invoice; home requests pay the lender or seller. No code path sends request money to the requester's own account.
- **Scores are explained and never refuse.** Every legitimacy score stores the model version, inputs and reasons. Code may route a low score to review; only a person's recorded decision can refuse a request.
- **Shared evidence is redacted; originals are private.** Nothing reaches the members-only board (state and week, never names or towns) without automatic redaction plus the member's confirmation.
- **The money pools stay separate.** Lending data and protection-reserve data live in separate schemas or services with no code path that moves funds between them.
- **Financial and identity data is sensitive.** Treat loan amounts, income, hardship details and identity documents as PII: encrypted at rest, least-privilege access, audit-logged reads.
- **Loans repay monthly by default, never with interest or late fees.** Hardship pauses push the schedule back without changing the total. What happens on default is agreed at signing (forgive / repay on sale (secured only) / mediate).
- **The giving record is private.** What a member has put in vs received is private to the member and never ranks or refuses requests.
- **Fund decisions are explainable.** The Community Home Fund scoring formula is versioned in code and its inputs logged, so any decision can be explained to the applicant and audited for bias.

