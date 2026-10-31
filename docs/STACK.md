# Stack

Kinfold is at the design stage. The product design lives in [design.md](design.md); read it before writing any code.

## What exists today

A pnpm workspace (`apps/*`), laid out like `project-stocks`:

| Workspace | What it is | Port |
| --- | --- | --- |
| `apps/web` | SvelteKit 5 marketing / preview site: landing page, request board demo and savings calculator. `adapter-static` with every route **prerendered** to HTML (a public site, unlike project-stocks' auth-gated SPA). No backend, no env vars. | 7790 |

Code layout in `apps/web/src/lib`: `finance/` (loan maths, pure and tested), `requests/` (community-pool allocation by legitimacy band, pure and tested), `core/` (formatting), `landing/` (page sections). Styling is plain CSS with design tokens in `src/app.css` (light and dark via `prefers-color-scheme`); no CSS framework.

## Commands

| Command | Does |
| --- | --- |
| `pnpm setup` | Install deps and the gitleaks pre-commit hook |
| `pnpm dev:run:web` | Dev server on http://localhost:7790 |
| `pnpm build:web` | Prerender to `apps/web/build/` (deployable to S3 + CloudFront as-is) |
| `pnpm preview:web` | Serve the production build on 7790 |
| `pnpm check` | svelte-check typecheck |
| `pnpm test` | Vitest unit tests + the root-scripts guard |

## Not chosen yet

The member app (accounts, requests, evidence storage, scoring, loans, the pool) needs relational data, auth and private object storage. When it starts, add it from the matching `templates` branch (likely `mobile-fullstack`, i.e. Supabase + Flutter, or `web-postgres`) as further `apps/*` workspaces.

## Domain rules that hold whatever the stack

These come from `design.md` and apply to every line of code:

- **No interest and no late fees in any code path.** A repayment schedule only ever sums to the principal. Where tax law needs a minimum rate on a family loan, it is calculated, shown, and set up to be forgiven as a gift.
- **The app never holds member money.** In Phase 1 money moves between people through a payment partner; Kinfold stores records, documents and schedules. Pooled money (community pool, Home Fund) only ever sits with a licensed partner, reached through their API.
- **Pay the payee, not the member.** Damage requests pay the named shop against its invoice; home requests pay the lender or seller. No code path sends request money to the requester's own account.
- **Scores are explained and never refuse.** Every legitimacy score stores the model version, inputs and reasons. Code may route a low score to review; only a person's recorded decision can refuse a request.
- **Public evidence is redacted; originals are private.** Nothing reaches the public board without automatic redaction plus the member's confirmation.
- **The money pools stay separate.** Lending data and protection-reserve data live in separate schemas or services with no code path that moves funds between them.
- **Financial and identity data is sensitive.** Treat loan amounts, income, hardship details and identity documents as PII: encrypted at rest, least-privilege access, audit-logged reads.
- **Fund decisions are explainable.** The Community Home Fund scoring formula is versioned in code and its inputs logged, so any decision can be explained to the applicant and audited for bias.

