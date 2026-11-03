# Stack

Kinfold is at the design stage. The product design lives in [design.md](design.md); read it before writing any code. The data model, invariants and edge functions live in [backend.md](backend.md). Whether each product can work, and what it would take, is in [feasibility.md](feasibility.md).

## What exists today

A pnpm workspace (`apps/*`), laid out like `project-stocks`:

| Workspace | What it is | Port |
| --- | --- | --- |
| `apps/web` | SvelteKit 3 (Svelte 5). Two halves: the public marketing / preview site (landing page, request board demo, savings calculator), **prerendered** to HTML under the `(site)` route group; and the member area (`/signin`, `/app/*`), a browser-only SPA (`ssr = false`) that talks to Supabase under RLS and is served from the adapter's `200.html` fallback. `adapter-static`. Env vars live in `src/env.ts` (Kit 3's `defineEnvVars`, read via `$app/env/public`): `PUBLIC_SUPABASE_URL` (committed `.env.development`) and `PUBLIC_SUPABASE_ANON_KEY` (never written to a file; `bin/dev-run-web.sh` reads it from `supabase status`). Kit config lives in `vite.config.ts` (there is no `svelte.config.js` in Kit 3). | 7790 |
| `apps/backend` | Supabase (Postgres 17, Auth, Storage, Edge Functions) for the member app. Local stack via the Supabase CLI in Docker. Migrations in `supabase/migrations`, pgTAP tests in `supabase/tests`. | API 54721, DB 54722, Studio 54723, Mailpit 54724 |

Code layout in `apps/web/src/lib`: `auth/` (session helpers, the dev demo accounts, the `?next=` return path, limited to `/app` paths, and `errors.ts`: sign-in failures worded by Supabase Auth error code (wrong password, rate limit, unconfirmed email, offline; `pnpm` commands only in a dev build), and `LoadError` plus `classifyLoadError`, which tell an ended session from a dropped connection from a server refusal. `loadViewer` throws on a failed read instead of reporting "no profile"; `app/+layout.ts` sends an ended session back to `/signin` and shows anything else on `routes/+error.svelte` with a retry, and member-page failures use `app/+error.svelte`, inside the member nav), `supabase/` (the one client, typed from `apps/backend/supabase/database.types.ts`; functions the migrations add after the last `gen:types` run go through `rpcNew`, one typed escape so new RPCs keep the same client rather than hand-editing the generated file), `dashboard/` (member home at `/app`: the greeting, a plain note for a signed-in account with no member row (creating one in the app is a pending product decision), status labels, loan summaries, the private giving record, and `loadHome`, which reads only RLS-scoped selects and self-only RPCs), `board/` (members-only board at `/app/board`: kind, fund and payee labels, bands, progress text, filter and sort that never use who gave or who asked, pledge-amount parsing; `errors.ts` words a failed board load in plain language and never shows the raw database message; `terms.ts` holds the plain-language definitions of "the pool", the two funds, a pool run, "payee" and "redacted" that the board, loans, invites and review pages show where each word first appears, restated from `design.md`; `list-semantics.test.ts` fails when a list in those pages resets its markers without `role="list"`), `invites/` (invite links, supporters, gift and 0% loan pledges; `InvitePanel` for the owner on the request page, `SupportPanel` for the invitee at `/app/invite/<token>`), `loans/` (`/app/loans`: a schedule preview mirroring `set_loan_schedule`'s last-installment-takes-the-remainder split, property-tested; who may take which loan action; plain-word loan refusals), `review/` (review console at `/app/review`: decision labels, reason validation, plain-language wording for every database refusal, reads and decisions under RLS), `finance/` (loan maths, pure and tested), `requests/` (community repair fund allocation by evidence band, pure, with example tests plus `fast-check` property tests of its money invariants; plus the member request flow's draft validation, pool eligibility, evidence and appeal helpers behind `/app/requests/new` and `/app/requests/[id]` (`amount.ts` refuses a comma decimal such as "12,50" rather than reading it as $1,250 and echoes the amount it understood; `upload-queue.ts` uploads several chosen evidence files one at a time with a status per file, and the evidence panel keeps focus in place instead of jumping to the page top; evidence rows whose file never reached storage are found by listing the member's own folder and marked "Upload didn't finish" for the member to remove; evidence still awaiting automatic redaction is worded as Kinfold's pending step, not the member's; the request page shows payouts to the payee with their status and sent date, read under the existing "owners read payouts" policy; the request copy says invited supporters can read the title, description and drafts, which the "supporters read requests they back" policy allows); and `score-band.ts`, which words a member's score by the request's status ("Needs more evidence", "With a reviewer", "Evidence accepted", "A person decided"), comparing it with the fund's `fund_settings.min_score` only while no review has been written since the current score (`reviewSinceScore`) and only when the comparison agrees with the status, and words board bands (never "needs evidence" and never "approved by a reviewer": a board request under the fund's current minimum is "Open for gifts") with no band-payment or formula claim for the Home Fund, whose needs formula isn't live yet; never a refusal word, property-tested. The review console shows only the score, band range and reasons, so reviewers aren't anchored on a label), `core/` (formatting), `landing/` (page sections; `sections.ts` lists the nav anchors and its test fails if one points at a missing section; `SavingsCalculator.contrast.test.ts` recomputes the calculator's results-panel text contrast from the `app.css` tokens, light and dark, and fails under 4.5:1 or on any text opacity), imported as `#lib/...` (a `package.json` subpath import; Kit 3 dropped the `$lib` alias). Styling is plain CSS with design tokens and the shared utilities (`.visually-hidden`, `.skeleton`, `.skip-link`; `src/lib/shared-styles.test.ts` stops components re-copying them, and fails if a form field outline uses the low-contrast `--border` instead of `--field-border`) in `src/app.css` (light and dark via `prefers-color-scheme`); no CSS framework.

## Commands

| Command | Does |
| --- | --- |
| `pnpm setup` | Install deps and the gitleaks pre-commit hook. The backend also needs Docker running and the Supabase CLI |
| `pnpm setup:e2e` | Download the Chromium build Playwright drives (once per machine, and after a `@playwright/test` bump) |
| `pnpm dev:db:up` / `dev:db:down` | Start / stop the local Supabase stack |
| `pnpm dev:db:reset` | Re-apply every migration and `seed.sql` to the local DB |
| `pnpm dev:db:status` | Local URLs, ports and keys of the running stack |
| `pnpm dev:db:psql` | `psql` into the local DB on 127.0.0.1:54722 |
| `pnpm dev:db:studio` | Open Supabase Studio on http://127.0.0.1:54723 |
| `pnpm dev:run:web` | Dev server on http://localhost:7790. With `dev:db:up` running, `/signin` lists the seeded demo accounts (maria, sam, james, priya; password `testtest`): click one to sign in. The list only appears in a dev build pointed at a loopback Supabase URL. There is no sign-up or password reset in the UI: membership is invitation-only for now, and the page says so |
| `pnpm build:web` | Prerender to `apps/web/build/`. S3 + CloudFront must serve `200.html` for unknown paths so `/app/*` loads |
| `pnpm preview:web` | Serve the production build on 7790 |
| `pnpm check` | svelte-check typecheck for the web workspace, then `deno fmt --check` + `deno check` for the edge functions |
| `pnpm test` | Vitest unit tests + the root-scripts guard + the markdown-hygiene guard (`test:docs`) + pgTAP (needs `dev:db:up` first). Does not run the e2e tests |
| `pnpm test:web:e2e` | Playwright end-to-end tests of the public site: builds it and serves it with `vite preview` on 7790 (reuses a server already on 7790 outside CI), then runs desktop Chrome and a Pixel 7 phone. Needs `setup:e2e` once |
| `pnpm test:edge` | Deno unit tests of the edge functions in `apps/backend/functions` (fake `Db`, no stack, no Docker) |
| `pnpm test:backend:db` | pgTAP only: schema, invariants, RLS |
| `pnpm gen:types` | Regenerate `apps/backend/supabase/database.types.ts` from the local schema; commit the result |

## End-to-end tests

Playwright tests live in `apps/web/e2e/`, outside the Vitest glob (`src/**/*.{test,spec}.ts`); config in `apps/web/playwright.config.ts`. They run against the production build, so they see the prerendered HTML that ships. Two projects: `desktop` and `phone` (Pixel 7, under the 860px breakpoint where the nav becomes the "Menu" `<details>`). A `*.desktop.spec.ts` file runs only on desktop, `*.phone.spec.ts` only on the phone, and any other spec runs on both. `retries: 0`: a flaky test is a bug to fix (root `CLAUDE.md`).

- **Wait on real signals.** The root layout sets `<html data-hydrated="true">` once the app hydrates; `gotoHydrated()` in `e2e/helpers.ts` waits for it before touching controls that need JavaScript (sliders, the phone menu closing after a pick). Content checks don't need it, since the HTML is prerendered.
- **Expected figures come from the app's own pure modules** (`#lib/finance`, `#lib/core/format`, `#lib/landing/sections`), imported by relative path, so a test can't drift from the maths it checks.
- **No-JS coverage** uses `test.use({ javaScriptEnabled: false })` and asserts that `data-hydrated` is absent.
- **Accessibility audit of the public surfaces** (`e2e/a11y.spec.ts`, both projects): the hydrated landing, transparency and sign-in pages are walked like a screen reader walks them - `lang` and the viewport meta (large text needs a reflow), one `h1` anchor and no heading-level skips, every `img` carries `alt`, every button and link announces a name, every visible form field carries a label. Rules collect named problems, so a failure points at the element. The member consoles are the audit's next surface once a stack-configured project exists.
- **Not covered yet: the member area's stack-dependent behaviour** (`/signin`'s sign-in form and session flow, `/app/*`), because it needs the local Supabase stack. `/signin`'s no-stack ENTRY is covered (`e2e/signin.spec.ts`): with no key configured the page must show its notice, not a dead form or a crash. So is the member area's ENTRY (`e2e/member-entry.spec.ts`): with no key configured `/app` redirects to `/signin` client-side, so a preview build can never serve a half-empty member area. To add it: a separate Playwright project (or config) whose tests start with `pnpm dev:db:up && pnpm dev:db:reset`, run against a build pointed at the local stack (`PUBLIC_SUPABASE_URL` from `.env.development`, the anon key read from `supabase status` the way `bin/dev-run-web.sh` does it), sign in as a seeded demo account, and keep it out of the default `test:web:e2e` run so it still needs no Docker.
- **e2e now runs in CI, and the Chromium download is paid once per version bump.** `ci.yml` gained an `e2e` job: `pnpm setup:e2e` under `PLAYWRIGHT_BROWSERS_PATH=apps/web/.e2e-chromium-cache`, with that directory held in `actions/cache` keyed on `hashFiles('apps/web/package.json')` (the `@playwright/test` version lives there), then `pnpm test:web:e2e`. The public prerendered site needs no stack and no Docker, so the job is gated like the others on the `changes` filter (a docs-only push skips it, and skipped counts as passing). Verified locally: with `CI` set the config refuses a reused server, forbids `test.only` and runs one worker — 44 passed, 0 failed (see [ledger.md](ledger.md) for why the earlier "leave e2e out" decision was reversed).

## Edge functions

`apps/backend/functions/<name>/index.ts` (Deno 2, which `supabase/config.toml` already pins with `deno_version = 2`).
A function reaches the database through `functions/shared/rest.ts`: PostgREST with the service key from
the runtime environment, calling the **same guarded functions** the members' app calls — a function never
writes to a table itself, so its word is never more trusted than the function's own guard (`private.is_service()`).
`pnpm test:edge` runs the `*_test.ts` files beside each function, where the `Db` is a fake: the rules a function
applies before it touches a file are pinned there, without a stack. `pnpm check:edge` runs `deno fmt --check` and
`deno check`. Not in CI: the runners don't ship Deno (see [ledger.md](ledger.md)); `pnpm test` runs these locally.

## Backend

`apps/backend` is a Supabase project. Migrations live in `apps/backend/supabase/migrations` and pgTAP tests in `apps/backend/supabase/tests`; change the schema through a new migration plus a test, then `pnpm gen:types`. The schema overview, the invariants the database enforces and the edge functions are in [backend.md](backend.md).

A pgTAP file's `select plan(N)` must equal the number of top-level assertions it makes — `is`, `is_ok`, `is_not_null`, `isnull`/`isnot`, `isnt`, `like`, `results_eq`, `ok`, `lives_ok`, `throws_ok`, `throws_like` — each call is one test, and a suite that runs short of its plan FAILS in `pnpm test:backend:db` (pgTAP reports the gap as a failure, not a pass). So a suite that can't be run here is audited by counting, not by eyeballing: `grep -cE "^select (is|is_ok|is_not_null|isnull|isnot|isnt|like|results_eq|ok|lives_ok|throws_ok|throws_like)\(" <file>` must print the same number the file's `plan()` claims. All 62 suites agree on 2026-11-03.

Every module under `apps/web/src/lib` has a matching `*.test.ts` — the one exception is `supabase/client.ts`, the seam module itself: its value import can't resolve the `$app/env/public` virtual module outside a built app, so a vitest file would fail on import; its behaviour is pinned instead by every loader that fakes the seam and by the no-stack e2e entries (`sign-in.spec.ts`, `member-entry.spec.ts`). Checked the same way the pgTAP plans are: for each `*.ts` under `src/lib` a sibling `*.test.ts` must exist. Agrees on 2026-11-03.

## Clients

- **Member app: Flutter, planned** as `apps/mobile` (the estate `mobile-fullstack` pattern, as in project-stocks). Evidence capture needs the phone camera with device attestation, which a web page can't give.
- **Reviewer console: planned** as authenticated routes in a later web app, not in the public marketing site.

## Domain rules

These come from `design.md` and apply to every line of code:

- **No interest and no late fees in any code path.** A repayment schedule only ever sums to the principal. Where tax law needs a minimum rate on a family loan, it is calculated, shown, and set up to be forgiven as a gift.
- **The app never holds member money.** In Phase 1 money moves between people through a payment partner; Kinfold stores records, documents and schedules. Pooled money (community pool, Home Fund) only ever sits with a licensed partner, reached through their API.
- **Pay the payee, not the member.** Damage requests pay the named shop against its invoice; home requests pay the lender or seller. No code path sends request money to the requester's own account.
- **Scores are explained and never refuse.** Every legitimacy score stores the model version, inputs and reasons. Code may route a low score to review; only a person's recorded decision can refuse a request.
- **Shared evidence is redacted; originals are private.** Nothing reaches the members-only board (state or Census division and month, never names or towns) without automatic redaction plus the member's confirmation.
- **The money pools stay separate.** Lending data and protection-reserve data live in separate schemas or services with no code path that moves funds between them.
- **Financial and identity data is sensitive.** Treat loan amounts, income, hardship details and identity documents as PII: encrypted at rest, least-privilege access, audit-logged reads.
- **Loans repay monthly by default, never with interest or late fees.** Hardship pauses push the schedule back without changing the total. What happens on default is agreed at signing (forgive / repay on sale (secured only) / mediate).
- **The giving record is private.** What a member has put in vs received is private to the member and never ranks or refuses requests.
- **Fund decisions are explainable.** The Community Home Fund scoring formula is versioned in code and its inputs logged, so any decision can be explained to the applicant and audited for bias.
