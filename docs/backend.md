# Backend and data model

How Kinfold's backend works, and which part of it enforces each rule from [design.md](design.md). The schema itself is in `apps/backend/supabase/migrations/`, and its tests are in `apps/backend/supabase/tests/`. Commands are in [STACK.md](STACK.md).

## Principles

1. **Kinfold never holds money.** Licensed partners move and hold all money: a payment partner for people-to-people payments, the partner insurer for the protection pool, and a credit union for the Home Fund. Postgres is the system of record for *decisions* (who asked, what the evidence showed, who decided, what was allocated). The partners are the system of record for *money*. The ledger mirrors what the partners report, keyed by their reference, and is reconciled daily.
2. **The database enforces the rules.** "No interest", "the AI never refuses", "the pools never mix" and "pay the payee, never the member" are enforced by constraints, triggers and grants, so a bug in the app or an edge function cannot break them. Every rule is pinned by a pgTAP test.
3. **Least privilege by default.** Supabase's default "grant everything to every role" is revoked. Clients get column-level grants and row-level security (RLS) policies, and every status change goes through a `security definer` function. Anything clients must never read goes in the `private` schema.
4. **Every decision can be explained.** Scores, reviews, pool runs and fund-setting changes are append-only and record their inputs and versions.
5. **Local-first.** Every external partner has a local stand-in, so the whole system runs on a laptop with no accounts (see "Local development").

## Architecture

```
 Flutter member app ──┐                      ┌── KYC vendor (identity)
 (requests, camera,   │   Supabase            ├── Bank link (income, read-only)
  pledges, loans)     ├─► Auth                ├── Payment partner (pledges, repayments, payouts)
                      │   PostgREST + RLS     ├── Partner insurer (protection pool custody)
 Web (apps/web) ──────┤   Storage (evidence)  ├── Credit union (Home Fund custody)
 marketing site,      │   Edge Functions ─────┼── AI model provider (scoring, redaction)
 later reviewer and   │   pg_cron (schedules) ├── E-signature (loan agreements)
 panel console        ┘   Postgres 17         └── County lien recording (secured loans)
```

- **Clients** talk to PostgREST (tables and RPC functions) as the signed-in member, so RLS applies to every query.
- **Edge functions** run as `service_role`. They are the only callers of service-only functions (`record_score`, `run_pool_allocation`, `capture_contributions`, `mark_refunded`, `resume_ended_pauses`, `apply_default_plan`, `post_journal`) and the only readers of the `refunds_due` view, and the only code that talks to partners. `service_role` bypasses RLS but not grants, so it holds explicit table, sequence and function grants (the hardening migration); the append-only triggers and the status and payout guards still apply to it.
- **Partner webhooks** come in through edge functions, which check the signature, then update payment statuses and post ledger journals. They are idempotent, keyed by `partner_ref`, which is unique on every money table.

## Data model

Money is stored as `bigint` cents. Times are `timestamptz`. Ids are UUIDs. Enums cover every status.

`20261030120400_hardening.sql` revises functions, policies and grants across all three areas below (account closure, capture and refunds, appeals, loan terms and states, payee checks, service-role grants); the tables describe the result.

### Members (`20261030120000_members.sql`)

| Table | Purpose |
| --- | --- |
| `members` | One row per user (`auth.users`). Holds the member's state (`region`) and status: `pending_verification` until identity verification passes, then `active`; `suspended` or `closed` members keep no role powers. A member edits only `display_name`: `region` is set at sign-up and changed only by the service after address verification, because reviewers are matched by region. Members are closed (`close_account()`), never deleted |
| `private.member_identity` | The identity-check vendor's reference and the outcome. The documents themselves stay with the vendor |
| `member_roles` | `reviewer`, `panel`, `admin` |
| `fund_settings` | Rules for each pooled fund: minimum score, band size, reserve share, waiting days, request cap, kinds covered. Every change is logged to `private.fund_settings_history` |
| `income_verifications` | Verified monthly take-home pay, how it was verified, and when it expires |
| `subscription_formulas` | Published pricing versions: income floor, rate, cap, core share |
| `subscriptions` | A member's monthly amount and which formula version priced it. At most one active per member |
| `subscription_payments` | Each month's collection. Cover starts at the first captured payment (`coverage_started_on`, security invoker: a member can read only their own cover date) |
| `allocation_preferences` | How the member splits the directable 20% of their payment. Weights must total 100 |
| `covered_assets` | Vehicles and homes. `registered_on` drives the waiting period |
| `private.audit_log` | Append-only record of sensitive actions |

### Requests (`20261030120100_requests.sql`)

| Table | Purpose |
| --- | --- |
| `payees` | Shops, lenders, sellers and contractors. Members can propose one; only the service can verify it (business and bank checks) |
| `requests` | The request: kind, funding mode (`people` / `pool` / `both`), amount, incident date, asset, payee, status, `public_summary` (redacted), `current_score` |
| `request_transitions` | The allowed status moves, as data |
| `request_events` | Append-only history of every status change |
| `evidence` | Each file's private original path, redacted path, SHA-256 hash, perceptual hash, whether it was captured in-app, content credentials, and redaction status |
| `scores` | Append-only. The score, its reasons, the model and its version, the prompt version, and a hash of the inputs |
| `reviews` | Append-only. The person's decision and a written reason (at least 10 characters). The member never sees `reviewer_id` (retaliation risk): they read decisions through `my_request_reviews(request)`, which returns only decision, reason and time. The panel reads full rows on requests that aren't their own; a reviewer reads the reviews they wrote |
| `appeals` | One appeal per refusal (`file_appeal` counts appeals against transitions into `refused` in `request_events`), decided by a panel member who didn't review the request |
| `private.fraud_signals` | Flags from duplicate photos, cross-request patterns and similar checks. An open high-severity flag sends a request to a person |
| `board_requests` (view) | The members-only board: redacted summary, kind, amount, score, state, week. Never names, towns or exact dates |

Request lifecycle:

```
 draft ─submit─► scoring ─score ≥ min─► open ─fully pledged─► funded ─payout─► paid
   │               │  └─score < min─► needs_evidence ─resubmit─┘   │
   │               └─fraud flag─► in_review ◄──────────────────────┤
   └─► withdrawn                     │ └─person refuses─► refused ─appeal upheld─┐
                                     └─approve─► open             ▲              │
                                                                  └──────────────┘
 open / needs_evidence can also expire; withdrawn, expired and refused release all pledges.
```

A refused request is reopened only by an upheld appeal: `record_review` doesn't accept `refused` requests. Approving a request whose pledges already cover it (a funded request sent back to review) returns it to `funded`. If a request that already had money captured ends withdrawn, refused or expired, that money appears in `refunds_due` until the payment partner refunds it.

### Funding, loans and the ledger (`…120200_funding.sql`, `…120300_repayment.sql`)

| Table | Purpose |
| --- | --- |
| `request_invites`, `request_supporters` | Invite links (only the token's hash is stored) and the family and friends who accepted them |
| `contributions` | Pledges from people (`gift` / `loan`) and the pool (`pool`). Status: `pledged`; `captured` by `capture_contributions(request)` (service only) once the request is funded, every loan behind it is signed and the payment partner has confirmed; `released` if the request ends unpaid before capture; `refunded` (`mark_refunded`, with `refund_partner_ref`) if it ends unpaid after. Pledges and pool grants wait for the request's payee to be verified. Strangers can give only to requests on the board; loans need an invite |
| `family_loans` | Zero-interest loans. There is no rate column: `imputed_rate_bps` is the IRS minimum rate, kept only for tax paperwork. Also the payment day, pause allowance and agreed default plan, set with `set_loan_terms` while the loan is `proposed` (it clears both signatures) |
| `loan_installments` | The schedule: `set_loan_schedule` puts each installment on the loan's payment day, sums exactly to the principal, and clears signatures. Constraint triggers keep the total at or below the principal, and payments plus forgiveness can't exceed it. Paying the last cent marks the loan `repaid` |
| `loan_pauses`, `loan_forgiveness` | Pauses taken (each pushes unpaid installments back) and amounts forgiven as gifts |
| `loan_missed_installments` (view) | Installments more than 10 days overdue on loans still collecting (`active` or `paused`), shown to the borrower and the lender |
| `pool_runs`, `pool_allocations` | Each allocation run, with a snapshot of the settings used, the reserve held, and each request's band, need and grant. Open books |
| `payouts` | Payments to payees. Allowed only for funded requests, only to the request's verified payee, only against an invoice on that request, and only up to the captured contributions |
| `private.ledger_accounts`, `ledger_journals`, `ledger_lines` | Double-entry ledger. Every journal balances to zero and stays within one fund. Append-only: corrections are reversing journals |
| `refunds_due` (view) | Service only. Captured contributions on withdrawn, refused or expired requests, waiting for the partner to refund them |
| `public_stats` (view) | Public totals per fund for the marketing site |

Loan lifecycle:

```
 proposed ─both sign─► signed ─request paid (money disbursed)─► active ⇄ paused
    │                    │                                       │  pause_loan / resume_loan,
    └─request ends unpaid┴─► cancelled                            │  or the daily job once a pause runs out
                                                                 ├─last payment─► repaid
                                                                 ├─forgiven to zero─► forgiven
                                                                 └─apply_default_plan─► forgiven / defaulted
```

Only `active` or `paused` loans can be paused, forgiven or defaulted, and a loan that owes nothing is never defaulted. The borrower can resume early at any time (the pushed-back dates stay pushed back); the service resumes a loan only once its latest pause has run out.

`request_raised_cents(request)` returns the amount raised only to the owner, a supporter, a verified member when the request is on the board, or the service role; anyone else gets null. Internal callers use `private.raised_cents`. `loan_outstanding_cents` is security invoker (only the loan's parties get a balance), and `pool_requests_paid_3y` answers a member only about themselves.

Member-facing functions: `my_reliability()` (the record that replaces a credit score) and `my_giving_record()` (what the member has paid in, given and lent, and what they've received). Both return only the caller's own data.

## Where each rule is enforced

| Rule (design.md) | Enforced by | Test |
| --- | --- | --- |
| No interest | No rate column; installments ≤ principal (constraint trigger); `sign_loan` requires the schedule to equal the principal | `funding_test` |
| Pauses never change the total | `pause_loan` only moves due dates, within the allowance; `resume_loan` and `resume_ended_pauses` change only the status | `repayment_test`, `hardening_test` |
| Default plan agreed up front | `family_loans.default_plan`, set only before signing (`set_loan_terms`); `repay_on_sale` requires a secured loan (check); `apply_default_plan` is service-only, audited, and refuses a loan that owes nothing | `repayment_test`, `hardening_test` |
| The AI never refuses | The status guard rejects `refused` unless a `refuse` review was written in the same transaction; `record_score` can only route to open, needs evidence or in review | `requests_test`, `reviews_test` |
| No self-review or same-region review | `record_review` checks; roles count only for `active` members (`has_role`) | `reviews_test`, `hardening_test` |
| Every refusal can be appealed, once, to someone independent | `record_review` can't re-decide a `refused` request; `file_appeal` allows one appeal per refusal; `decide_appeal` refuses the appellant and anyone who reviewed the request | `reviews_test`, `hardening_test` |
| Reviewers are safe from retaliation | Members can't read `reviews` rows on their own requests; `my_request_reviews` omits `reviewer_id` | `hardening_test` |
| No joining after the incident | `submit_request` checks `coverage_started_on` and the asset's `registered_on` against `waiting_days` | `requests_test` |
| Evidence is redacted before anyone sees it | `submit_request` requires every redaction to be `confirmed`; the board shows only `public_summary`; the originals bucket is owner-only | `requests_test`, `rls_test` |
| Pay the payee, never the member | `payouts` guard trigger; payees are businesses, never members; `pledge` and `run_pool_allocation` wait for a verified payee (`submit_request` doesn't, so verification runs alongside scoring) | `ledger_test`, `hardening_test` |
| Pledges are all-or-nothing | Funded when pledges reach the amount; released on withdraw, expire or refuse; money already captured is listed in `refunds_due` and marked by `mark_refunded` | `funding_test`, `hardening_test` |
| No money moves on an unsigned loan | `capture_contributions` refuses unless the request is funded and every loan behind it is signed; a loan becomes `active` only when its request is paid, and only active or paused loans can be paused, forgiven or defaulted | `hardening_test`, `funding_test` |
| Only people you know can lend | `pledge` requires an accepted invite and an active member for `loan`; a stranger can give only to a request on the board | `funding_test` |
| Pool pays by band, highest first, all at once | `run_pool_allocation` (same algorithm as `apps/web/src/lib/requests/allocation.ts`) | `pool_test` |
| The pools never mix | Every ledger journal stays within one fund and has at least two lines (deferred constraint trigger, `post_journal`) | `ledger_test`, `hardening_test` |
| Open books | `pool_runs` and `public_stats` readable by anyone; `fund_settings` changes logged | `rls_test` |
| The giving record is private and never ranks | `my_giving_record` returns only the caller's data; nothing in allocation reads it | `repayment_test` |
| Other members' money and cover stay private | `request_raised_cents` only for those who can see the request; `coverage_started_on` and `loan_outstanding_cents` are security invoker; `pool_requests_paid_3y` is self-only | `rls_test`, `repayment_test`, `hardening_test` |
| Financial records outlive accounts | Members are never deleted (requests are `on delete restrict`; history is append-only); `close_account` refuses while anything is open, then scrubs and closes | `hardening_test` |

## Access model

| Role | Can |
| --- | --- |
| `anon` | Read the fund rules, subscription formulas, pool runs and public stats |
| Member (`authenticated`) | Read their own data (but not who reviewed their requests); edit their display name (not their region); create and edit drafts; add evidence; submit, withdraw and appeal through RPCs; pledge to requests they're invited to or that are on the board; set terms and schedules for, sign, pause and resume their own loans; close their account |
| Supporter | Read the requests they were invited to and how much they've raised |
| Reviewer (active members only) | Read requests waiting for a person (never their own); record reviews (not on refused requests); see scores and the reviews they wrote |
| Panel (active members only) | Decide appeals (never their own, nor on a request they reviewed); read full review rows on requests that aren't their own |
| `service_role` (edge functions only) | Record scores, run the pool, verify payees, capture pledges, record refunds, payments and payouts, post journals, resume loans whose pause has ended, apply default plans |

Storage has two private buckets. `evidence-original` holds files under the member's own folder, readable only by the member; reviewers get short-lived signed URLs from an edge function that writes to the audit log. `evidence-redacted` is readable by the owner, and by verified members once the request is on the board.

## Edge functions (to build)

| Function | Triggered by | Does | Local stand-in |
| --- | --- | --- | --- |
| `verify-identity` | Signup | Starts an identity check, then a webhook sets the member `active` | Fake vendor that approves `*@test.com` |
| `verify-income` | Member links a bank | Reads income only (never a password), writes `income_verifications`, prices the subscription | Fixture statements |
| `redact-evidence` | Evidence upload | Blurs faces, plates, names and account numbers, writes the redacted copy and `auto_done`, computes hashes | Open-source face and plate detection running locally |
| `score-request` | Status becomes `scoring` | Builds inputs from redacted and original evidence plus fraud signals, calls the model, then `record_score` | Ollama model behind the same provider interface |
| `fraud-checks` | Evidence and request events | Duplicate-photo and pattern checks, writes `private.fraud_signals` | Same code, local data |
| `evidence-url` | Reviewer opens evidence | Issues a short-lived signed URL for the original and logs it | Same |
| `payments-webhook` | Payment partner | Calls `capture_contributions` once the partner confirms a funded request's charges; refunds what `refunds_due` lists and calls `mark_refunded`; records repayments and payouts; posts journals with `post_journal` (the `public` wrapper, service only, at least two lines) | Partner's test mode, or a local webhook sink |
| `run-pool` | pg_cron, weekly | Reads the custody balance, then calls `run_pool_allocation` | Balance from a fixture |
| `reconcile` | pg_cron, daily | Compares ledger balances with the partners' statements and raises an alert on any difference | Fixture statements |
| `loan-servicing` | pg_cron, daily | Calls `resume_ended_pauses`, collects due installments (paying the last one marks the loan repaid), sends reminders, offers pauses on missed payments | Fake collector |
| `expire-requests` | pg_cron, daily | Expires stale open and needs-evidence requests, which releases their pledges | Same |
| `close-account` | Member asks to delete their account | Calls `close_account()` as the member, then disables (never deletes) the auth user. Deleting from `auth.users` is blocked by design for anyone with a request, pledge, review or loan | Same, against local Auth |

## Privacy and retention

- Original evidence is kept only as long as a request can be appealed or reopened (design target: 2 years after it's paid or closed), then deleted. Redacted copies and scores are kept for the open books.
- Financial records (contributions, payouts, ledger) are kept as long as the partners' regulators require, typically at least 5 years, even after an account is closed. Personal fields are separated out so they can be deleted while the financial record stays.
- Closing an account (`close_account`) is refused while the member has open requests, an open appeal, loans they owe or are owed, or uncollected pledges. Then it sets the member `closed`, replaces the display name with "Closed account", deletes their covered assets (one named on a request is kept with its description scrubbed), allocation preferences and supporter rows, ends the subscription, and writes an audit row.
- Income, identity and hardship details are PII: kept in the database only as outcomes and vendor references, read only by their owner, and audit-logged when staff access them.

## Local development

`pnpm dev:db:up` starts the local Supabase stack (ports 54721 to 54729). `pnpm dev:db:reset` re-applies the migrations and the seed. The seed creates test members, verified payees, requests in every state and a family loan; logins are listed in `apps/backend/supabase/seed.sql`. `pnpm test:backend:db` runs the pgTAP suite. Partner integrations run against the stand-ins listed above, and each one stays off until it's configured.

## Not built yet

Edge functions, the Flutter member app, the reviewer and panel console, `fund_loans` (Home Fund loans, Stage 3: the same shape as `family_loans`, with the fund as lender plus income-based schedules), restructuring flows, and the subrogation workflow. See [roadmap.md](roadmap.md).
