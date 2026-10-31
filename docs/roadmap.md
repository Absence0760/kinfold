# Build roadmap

What to build, in what order. Each stage ships something members can use, and the next stage starts only when the last one's gate is met. The product reasons behind the order are in [design.md](design.md#roadmap); the data model is in [backend.md](backend.md). Durations are planning estimates for a small team.

Open items outside the stages (CI gaps, backend edge cases, pending decisions) are tracked in [followups.md](followups.md).

**Order rule:** build what moves no pooled money first. Every stage before Stage 2 can run with Kinfold holding nothing, so a mistake costs trust, not someone's savings.

## Stage 0: Foundations (now, weeks 0 to 4)

| Build | Done when |
| --- | --- |
| Preview site (`apps/web`) | ✅ Live locally; deployable as static files |
| Schema v1: members, requests, evidence, scores, reviews, funding, loans, repayment, ledger, pool (`apps/backend`) | ✅ Migrations apply; pgTAP suite green |
| CI: `pnpm check`, `pnpm test` (web, scripts, pgTAP) on every push to `main` (no PRs pre-launch; see `CLAUDE.md`) | Green on `main`; PR review and branch protection switched back on before Stage 1 has real members |
| Infra skeleton (Terraform, estate pattern): AWS account via `new-project-account.sh`, S3 + CloudFront for the site, hosted Supabase project, `production` environment with a required reviewer | The site deploys through the gated workflow |
| Counsel engaged (insurance, consumer lending, money transmission, co-op formation) and a first-state shortlist | Written legal plan for Stage 1 |

## Stage 1: Requests between people (months 1 to 9)

Goal: the whole request flow, funded only by family and friends. Car damage and home help. No pooled money.

| Step | Build | Notes |
| --- | --- | --- |
| 1a | **Member app shell** (Flutter, `apps/mobile`, estate `mobile-fullstack` pattern): sign-up, Supabase Auth, profile | A phone app, because evidence is captured at the scene with the camera |
| 1b | **Identity checks**: `verify-identity` edge function, vendor sandbox, local fake | Members become `active` only after passing |
| 1c | **Requests and evidence**: create a draft, in-app capture (content credentials, device attestation), upload to the private bucket, `redact-evidence`, member confirms each redaction | Gallery uploads allowed but marked |
| 1d | **Scoring v1**: `score-request` behind a provider interface (local Ollama, hosted model in prod), explained reasons, `fraud-checks` (duplicate photos) | Build a labelled evaluation set (at least 300 real-shaped cases) **before** turning scoring on |
| 1e | **Reviewer console** (authenticated web routes): review queue, signed-URL evidence viewer, decisions with reasons, audit trail | Same-region and self-review blocked in the database |
| 1f | **Supporters and payments**: invite links, gifts, all-or-nothing pledges through the payment partner, payee verification, payouts to shops against the final invoice, `payments-webhook`, ledger journals | Partner test mode locally |
| 1g | **Family loans**: agreement and e-signature, schedule on payday, autopay (`loan-servicing`), pauses, the default-plan choice, forgiveness and gift letters, IRS minimum-rate paperwork | Templates reviewed by a tax attorney |
| 1h | **Records**: reliability record and private giving record screens | |
| 1i | **Appeals**: member appeal and the panel console | |

**Gate to Stage 2:** legal review passed. 500 requests scored, and reviewers agree with the score at least 9 times in 10. No significant score gap by neighbourhood, age or language. Every payout reconciles with the payment partner. Kinfold never held funds.

## Stage 2: Community car pool (months 9 to 18)

Goal: earnings-based subscriptions fund a protection pool for own-damage car requests in one state, with the cover issued by a licensed partner insurer.

| Step | Build |
| --- | --- |
| 2a | **Partner integration**: fronting insurer and reinsurance contracts, custody account, statements feed |
| 2b | **Subscriptions**: `verify-income` (bank link), formula pricing, collection, the 80/20 split into fund journals, allocation preferences |
| 2c | **Pool runs**: weekly `run-pool`, reserve held, allocation published, pool contributions captured on funding |
| 2d | **Members-only board** and the public stats page |
| 2e | **Cover terms**: per-request caps by vehicle value, the member's share rising with `pool_requests_paid_3y`, waiting periods (already enforced) |
| 2f | **Fraud v2**: cross-request, cross-vehicle and cross-shop pattern checks; in-person inspection workflow for large requests |
| 2g | **Subrogation**: when another driver is at fault, the member assigns recovery; the partner claims from their insurer and refunds the pool |
| 2h | **Daily reconciliation** (`reconcile`) with alerts; quarterly open-books report |

**Gate to Stage 3:** requests paid within 7 days on average, fraud losses below the agreed target, books reconcile every day, regulator relationship in good standing, and a credit union partner signed.

## Stage 3: Home Fund (months 18 to 30)

Goal: zero-interest home help for people with no family to lend, through a partner credit union.

| Step | Build |
| --- | --- |
| 3a | `fund_loans`: the same shape as `family_loans`, with the fund as lender, a subordinate lien, and monthly or income-based schedules |
| 3b | Needs formula (versioned, inputs logged), panel review for edge cases |
| 3c | Mortgage-gap bridging, plus referral to HUD-approved housing counselors |
| 3d | Matching funds from foundations, employers and local government, tracked per source |
| 3e | Mortgage partner referrals (disclosed, never steering to a worse offer) |
| 3f | Home cover in the protection pool (repairs), if loss data supports it |

**Gate to Stage 4:** 25 fund loans repaying on time, and zero foreclosures.

## Stage 4: Grow (year 3 onward)

More cover types and states. A reciprocal exchange so members insure each other directly. Shared-equity homes. Paying members' mandatory liability premiums from the pool. Portable reliability records that landlords can accept.

## In every stage

- **Tests and docs ship with the code** (repo rule): pgTAP for every new rule in the database, Vitest and Deno tests for logic, Flutter tests for the app.
- **Security sweeps** before each stage's launch (`/audit/all`, plus `auth`, `gdpr` and `third-party-data-flows`), and a scoring bias audit every year.
- **Accessibility**: the member app is usable with a screen reader and large text from day one, because people post requests on their worst days.
- **Local-first**: every new partner arrives with a local stand-in in the same change.
