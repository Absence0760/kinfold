# Build roadmap

What to build, in what order. Each stage ships something members can use, and the next stage starts only when the last one's gate is met. The product reasons behind the order are in [design.md](design.md#roadmap); the data model is in [backend.md](backend.md). Durations are planning estimates for a small team.

Open items outside the stages (CI gaps, backend edge cases, pending decisions) are tracked in [followups.md](followups.md). Whether each stage's product can work at all is in [feasibility.md](feasibility.md).

**Order rule:** build what moves no pooled money first. Every stage before Stage 2 can run with Kinfold holding nothing, so a mistake costs trust, not someone's savings.

## Stage 0: Foundations (now, weeks 0 to 4)

| Build | Done when |
| --- | --- |
| Preview site (`apps/web`) | ✅ Live locally; deployable as static files |
| Schema v1: members, requests, evidence, scores, reviews, funding, loans, repayment, ledger, pool (`apps/backend`) | ✅ Migrations apply; pgTAP suite green |
| CI: `pnpm check`, `pnpm test` (web, scripts, pgTAP) on every push to `main` (no PRs pre-launch; see `CLAUDE.md`) | Green on `main`; PR review and branch protection switched back on before Stage 1 has real members |
| Infra skeleton (Terraform, estate pattern): AWS account via `new-project-account.sh`, S3 + CloudFront for the site, hosted Supabase project, `production` environment with a required reviewer | The site deploys through the gated workflow |
| Counsel engaged (insurance, consumer lending, money transmission, co-op formation) and a first-state shortlist | Written legal plan for Stage 1 |
| Start-up funding: member capital and cooperative or CDFI loans for the cooperative; foundation grants only for specific charitable projects (or through a fiscal sponsor); formation help from a cooperative development centre ([design.md](design.md#public-and-grant-funding)) | Start-up costs covered without outside equity |

## Stage 1: Requests between people (months 1 to 9)

Goal: the whole request flow, funded only by family and friends. Car damage and home help. No pooled money.

| Step | Build | Notes |
| --- | --- | --- |
| 1a | **Member app shell** (Flutter, `apps/mobile`, estate `mobile-fullstack` pattern): sign-up, Supabase Auth, profile | A phone app, because evidence is captured at the scene with the camera |
| 1b | **Identity checks**: `verify-identity` edge function, vendor sandbox, local fake | Members become `active` only after passing |
| 1c | **Requests and evidence**: create a draft, in-app capture (content credentials, device attestation), upload to the private bucket, `redact-evidence`, member confirms each redaction and the public summary (`confirm_public_summary`, schema done); the member declares other cover and any FEMA, SBA, state or charity money for the same damage, and is told how gifts affect disaster aid | Gallery uploads allowed but marked |
| 1d | **Scoring v1**: `score-request` behind a provider interface (local Ollama, hosted model in prod), explained reasons, `fraud-checks` (duplicate photos) | Build a labelled evaluation set (at least 300 real-shaped cases) **before** turning scoring on |
| 1e | **Operations console** (authenticated web routes): review queue, signed-URL evidence viewer, decisions with reasons, fraud signals, audit trail | Same-region and self-review blocked in the database; every PII read audit-logged. Reconciliation and reserve panels join in 2h |
| 1f | **Supporters and payments**: invite links, gifts, all-or-nothing pledges through the payment partner, payee verification, payouts to shops against the final invoice, `payments-webhook`, ledger journals | Partner test mode locally |
| 1g | **Family loans**: agreement and e-signature, schedule on payday, autopay (`loan-servicing`), pauses, the default-plan choice, forgiveness and gift letters, IRS minimum-rate paperwork | Templates reviewed by a tax attorney |
| 1h | **Member home dashboard**: open requests with score reasons, loans and next installment, pauses, missed installments, reliability record, private giving record | The giving record shows nowhere else ([design.md](design.md#dashboards)) |
| 1i | **Appeals**: member appeal and the panel console | |

**Gate to Stage 2:** legal review passed. 500 requests scored, and reviewers agree with the score at least 9 times in 10. No significant score gap by neighbourhood, age or language. Every payout reconciles with the payment partner. Kinfold never held funds.

## Stage 2: Community car cover (months 9 to 18)

Goal: in one state (Vermont first), earnings-based dues pay a group deductible policy issued to the cooperative by a licensed partner insurer, alongside a gift-funded repair fund and 0% repair loans. Why this shape and not one earnings-priced pool: [feasibility.md](feasibility.md#community-car-pool).

| Step | Build |
| --- | --- |
| 2a | **Partner integration**: fronting insurer with a filed group rate per vehicle class and plan (Basic, Standard), reinsurance and aggregate stop-loss, the insurer's claims and statements feed; insurance-regulatory counsel's written view (ideally the regulator's) on rebating and the group definition |
| 2b | **Dues**: `verify-income` (bank link; earnings leave out disaster aid, gifts, pool payouts and loan proceeds), the marginal dues formula, collection, the cooperative paying each member's premium (never called premium on the member's side), Basic paid in full below the floor, proof of liability cover, one premium per covered vehicle |
| 2c | **Claims under the group policy**: deductible claims paid in full, less the member's share, on the state's deadline; the evidence score sets speed and scrutiny, never the amount; denials only by a person, with appeal; in declared disasters a decision with a payment statement or decline letter within 30 days |
| 2d | **Repair fund and board**: the gift-funded repair fund's weekly run (`run_pool_allocation`, bands and reserve, money stacking after insured cover); the members-only board (schema done: confirmed summaries, bands, month, Census division); the **public transparency dashboard** on `open_books`. Schedule `publish_open_books` monthly. Any new breakdown follows design.md's small-numbers rules |
| 2e | **0% repair loans** through a partner credit union or CDFI, paid to the shop, with a gift-funded loss reserve; pointers to state and federal repair help |
| 2f | **Fraud v2**: cross-request, cross-vehicle and cross-shop pattern checks; in-person inspection workflow for large requests |
| 2g | **Subrogation**: when another driver is at fault, the member assigns recovery; the partner claims from their insurer |
| 2h | **Daily reconciliation** (`reconcile`) with alerts; quarterly open-books report |
| 2i | **Gap cover** (own damage up to $1,000 a year for members without collision cover), only once a year of loss data supports it |

**Gate to Stage 3:** covered claims paid within the state's deadline and repair-fund requests within 7 days on average, a loss ratio inside the partner's filed range, fraud losses below the agreed target, books reconcile every day, regulator relationship in good standing, a credit union partner signed that is a Home Loan Bank member willing to run the AHP set-aside, and the Home Fund formed as a 501(c)(3) the cooperative controls (it owns the loans, needs a services agreement at fair market value, and must exist before the CDFI application).

## Stage 3: Home Fund (months 18 to 30)

Goal: zero-interest home help for people with no family to lend, through a partner credit union.

| Step | Build |
| --- | --- |
| 3a | `fund_loans`: the same shape as `family_loans`, with the fund as lender, a subordinate lien, and monthly or income-based schedules |
| 3b | Needs formula (versioned, inputs logged), panel review for edge cases |
| 3c | Mortgage-gap bridging, plus referral to HUD-approved housing counselors |
| 3d | Matching funds and program-related investments from foundations, employers and local government, tracked per source, with federally funded loans as their own pot (2 CFR 200); CDFI Technical Assistance application, then certification after the Fund has lent on its own books for one full fiscal year (loan-level reporting with "Do Not Know" where no data was collected) |
| 3e | Mortgage matching with fair lenders, with **no referral fees** (RESPA section 8) |
| 3f | Home repair deductible cover under the group policy, and home grants from the repair fund, if loss data supports it |
| 3g | FHLB down-payment grants through the partner credit union; state housing finance agency and city programmes in the pilot city. Every public lien stays in the funder's own name (Kinfold never administers HOME or CDBG paper); offer the city HOME match credit for the Fund's 0% loans (24 CFR 92.220); one counseling agency certified under 24 CFR part 214 for every applicant and for 3c |
| 3h | Fair-lending data: the government monitoring form on home-purchase and refinance loans (Reg B 1002.13, on the credit union's behalf), and a voluntary self-test with its disclosures for other Fund loans (1002.5(b)(1)), stored where scoring and review can't read it |

**Gate to Stage 4:** 25 fund loans repaying on time, and zero foreclosures.

## Stage 4: Grow (year 3 onward)

More cover types and states. A reciprocal exchange so members insure each other directly. Shared-equity homes. Paying members' mandatory liability premiums from dues. Portable reliability records that landlords can accept.

## In every stage

- **Tests and docs ship with the code** (repo rule): pgTAP for every new rule in the database, Vitest and Deno tests for logic, Flutter tests for the app.
- **Security sweeps** before each stage's launch (`/audit/all`, plus `auth`, `gdpr` and `third-party-data-flows`), and a scoring bias audit every year.
- **Accessibility**: the member app is usable with a screen reader and large text from day one, because people post requests on their worst days.
- **Local-first**: every new partner arrives with a local stand-in in the same change.
