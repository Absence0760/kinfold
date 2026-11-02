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
- **Edge functions** run as `service_role`. They are the only callers of service-only functions (`record_score`, `run_pool_allocation`, `capture_contributions`, `mark_refunded`, `resume_ended_pauses`, `apply_default_plan`, `post_journal`, `record_fraud_signal`, `resolve_fraud_signal`, `record_identity_check`) and the only readers of the `refunds_due` view, and the only code that talks to partners. `service_role` bypasses RLS but not grants, so it holds explicit table, sequence and function grants (the hardening migration); the append-only triggers and the status and payout guards still apply to it.
- **Partner webhooks** come in through edge functions, which check the signature, then update payment statuses and post ledger journals. They are idempotent, keyed by `partner_ref`, which is unique on every money table.

## Data model

Money is stored as `bigint` cents. Times are `timestamptz`. Ids are UUIDs. Enums cover every status.

`20261030120400_hardening.sql` revises functions, policies and grants across all three areas below (account closure, capture and refunds, appeals, loan terms and states, payee checks, service-role grants), and `20261030120500_service_paths.sql` adds the payout rules, refunds net of payouts and the service-only wrappers for private writes; the tables describe the result. `apps/backend/supabase/database.types.ts` is generated from the schema (`pnpm gen:types`).

### Members (`20261030120000_members.sql`)

| Table | Purpose |
| --- | --- |
| `members` | One row per user (`auth.users`). Holds the member's state (`region`) and status: `pending_verification` until identity verification passes, then `active`; `suspended` or `closed` members keep no role powers. A member edits only `display_name`: `region` is set at sign-up and changed only by the service after address verification, because reviewers are matched by region. Members are closed (`close_account()`), never deleted |
| `private.member_identity` | The identity-check vendor's reference and the outcome. The documents themselves stay with the vendor. Written only through `record_identity_check` (service only), which also moves a `pending_verification` member to `active` and audit-logs it; it never lifts a suspension or reopens a closed account |
| `member_roles` | `reviewer`, `panel`, `admin` |
| `fund_settings` | Rules for each pooled fund: minimum score, band size, reserve share, waiting days, request cap, kinds covered. Every change is logged to `private.fund_settings_history` |
| `income_verifications` | Verified monthly take-home pay, how it was verified (a bank-linked figure carries the vendor's reference), and when it expires. Written only through `record_income_verification` (service only, audit-logged) |
| `subscription_formulas` | Published pricing versions: income floor, rate, cap, core share, and whether the rate is marginal (v2: 1% of the amount above the floor, effective 2027-01-01 — the switch is the actuarial review's, not ours) |
| `subscriptions` | A member's monthly amount and which formula version priced it. At most one active per member |
| `subscription_payments` | Each month's collection. Cover starts at the first captured payment (`coverage_started_on`, security invoker: a member can read only their own cover date) |
| `allocation_preferences` | How the member splits the directable 20% of their payment. Weights must total 100 |
| `covered_assets` | Vehicles and homes. `registered_on` drives the waiting period |
| `private.audit_log` | Append-only record of sensitive actions |

### Requests (`20261030120100_requests.sql`)

| Table | Purpose |
| --- | --- |
| `payees` | Shops, lenders, sellers and contractors. Members can propose one; only the service can verify it (business and bank checks) |
| `requests` | The request: kind, funding mode (`people` / `pool` / `both`), amount, incident date, asset, payee, status, `public_summary` (redacted by the service), `public_summary_confirmed_at` (set by the member through `confirm_public_summary`; any change to the summary clears it), `current_score` |
| `request_transitions` | The allowed status moves, as data |
| `request_events` | Append-only history of every status change |
| `evidence` | Each file's private original path, redacted path, SHA-256 hash, perceptual hash, whether it was captured in-app, content credentials, and redaction status |
| `scores` | Append-only. The score, its reasons, the model and its version, the prompt version, and a hash of the inputs |
| `reviews` | Append-only. The person's decision and a written reason (at least 10 characters). The member never sees `reviewer_id` (retaliation risk): they read decisions through `my_request_reviews(request)`, which returns only decision, reason and time. The panel reads full rows on requests that aren't their own; a reviewer reads the reviews they wrote |
| `appeals` | One appeal per refusal (`file_appeal` counts appeals against transitions into `refused` in `request_events`), decided by a panel member who didn't review the request |
| `claims` | Insured-cover claims from the partner's feed: gross, the member's share, what the shop got (exactly gross minus share, by check), and a person's denial with its reason. Written only through `record_claim` (service, unique partner_ref) and `deny_claim` (needs a recorded refuse review) |
| `private.fraud_signals` | Flags from duplicate photos, cross-request patterns and similar checks. An open high-severity flag sends a request to a person. Written only through `record_fraud_signal` and `resolve_fraud_signal` (service only, audit-logged) |
| `board_requests` (view) | The members-only board, for active members. One rule decides what's on it, `on_board(request)`: a pool request that is open, funded or paid, with a summary the member confirmed, open or submitted in the last 12 months. Shows the summary, kind, status, amount band, 10-point score band, month, and the state or, for states with fewer than 1,000 active members, the Census division (`board_area`). The exact amount only while the request is open. Never names, towns or exact dates |

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

A payout that is `pending` or `sent` is live: the money is with (or on its way to) the payee. While a request has a live payout the status guard refuses `refused`, `withdrawn` and `expired`, and `record_review` turns a refusal into `in_review` (the review and an audit row are still written), so a person deals with recovering the money; once the partner reports the payout `returned`, the request can be refused or withdrawn as usual. A request becomes `paid` only once at least one payout has been sent and its captured contributions cover the payouts sent.

### Money for the same damage and the evidence lifecycle (`…120600_board_privacy.sql`, `…150000_evidence_lifecycle.sql`)

| Relation | Purpose |
| --- | --- |
| `request_recoveries` | Money that covered the same damage through other sources: the member's own cover, insurer recoveries, FEMA/SBA/state/charity money. Append-only, positive amounts, `partner_ref`/`verified_at` set once the service verifies it. Owner-written (`record_recovery`) or service-written; read by the requester and the service. The pledge cap and the pool run's need subtract it (`private.recovered_cents`); it is never counted as money Kinfold raised, so funding, payout caps and refunds still look only at pledges and payouts |
| `private.evidence_deletions` / `pending_evidence_deletions` (view) | When an evidence row is deleted, its original and redacted files queue here for the service to remove (`mark_evidence_deleted` closes an entry). A storage delete policy can't cover files whose row is already gone, and the queue can't race with the row |
| `set_redaction_done`, `set_public_summary` (service) | The redaction pipeline's database affordance: `pending` or `rejected` evidence gets a `redacted_path` and `auto_done` while the request is still `draft` or `needs_evidence`; the service writes a request's `public_summary` (the existing trigger then clears the member's confirmation) |
| `reject_redaction`, `request_summary_change` (member) | The member says a redaction is wrong, or asks for a different summary with a note the service acts on; a member can never write the summary or the redaction themselves |

### Funding, loans and the ledger (`…120200_funding.sql`, `…120300_repayment.sql`)

| Table | Purpose |
| --- | --- |
| `request_invites`, `request_supporters` | Invite links (only the token's hash is stored; `revoked_at` cancels one before it's used) and the family and friends who accepted them |
| `contributions` | Pledges from people (`gift` / `loan`) and the pool (`pool`). Status: `pledged`; `captured` by `capture_contributions(request)` (service only) once the request is funded, every loan behind it is signed and the payment partner has confirmed; `released` if the request ends unpaid before capture; `refunded` (`mark_refunded`, with `refund_partner_ref` and `refunded_cents`, which can be less than the amount when part of it reached the payee) if it ends unpaid after. Pledges and pool grants wait for the request's payee to be verified. Strangers can give only to requests on the board; loans need an invite |
| `family_loans` | Zero-interest loans. There is no rate column: `imputed_rate_bps` is the IRS minimum rate, kept only for tax paperwork. Also the payment day, pause allowance and agreed default plan, set with `set_loan_terms` while the loan is `proposed` (it clears both signatures) |
| `loan_installments` | The schedule: `set_loan_schedule` puts each installment on the loan's payment day, sums exactly to the principal, and clears signatures. Constraint triggers keep the total at or below the principal, and payments plus forgiveness can't exceed it. Paying the last cent marks the loan `repaid` |
| `loan_pauses`, `loan_forgiveness` | Pauses taken (each pushes unpaid installments back) and amounts forgiven as gifts |
| `loan_missed_installments` (view) | Installments more than 10 days overdue on loans still collecting (`active` or `paused`), shown to the borrower and the lender |
| `pool_runs`, `pool_allocations` | Each allocation run, with a snapshot of the settings used, the reserve held, and each request's band, need and grant. Service only, except that a member reads the allocations for their own requests. The public sees them only as monthly totals in `open_books` |
| `payouts` | Payments to payees. Created only for funded requests, only to the request's verified payee, only against an invoice on that request, and live payouts never exceed the captured contributions. Later status reports from the partner (`sent`, `failed`, `returned`) are always recorded, whatever the request's state or the payee's status by then. `sent_at` records when the partner confirmed it sent |
| `private.ledger_accounts`, `ledger_journals`, `ledger_lines` | Double-entry ledger. Every journal balances to zero and stays within one fund. Append-only: corrections are reversing journals |
| `refunds_due` (view) | Service only. Captured contributions on withdrawn, refused or expired requests, waiting for the partner to refund them. Live payouts use up a request's captured money oldest first, and `refund_cents` is what's left of each contribution, so only money that didn't reach the payee goes back |
| `open_books` | The public open books: one row per pooled fund per month, written once by `publish_open_books(month)` (service only, a week after the month ends, UTC). Counts of 1 to 10 requests are null ("10 or fewer"); dollar totals show only for 11 or more requests with none making up half, rounded to $1,000; the short-run count shows only when 11 or more requests were granted money. No live totals, no all-funds or all-time rows, so nothing hidden can be recovered by subtraction |

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

`request_raised_cents(request)` returns the amount raised only to the owner, a supporter, a verified member while the request is open on the board, or the service role; anyone else gets null. Internal callers use `private.raised_cents`. `loan_outstanding_cents` is security invoker (only the loan's parties get a balance), and `pool_requests_paid_3y` answers a member only about themselves.

Member-facing functions: `my_reliability()` (the record that replaces a credit score) and `my_giving_record()` (what the member has paid in, given and lent, and what they've received). Both return only the caller's own data.

## Where each rule is enforced

| Rule (design.md) | Enforced by | Test |
| --- | --- | --- |
| No interest | No rate column; installments ≤ principal (constraint trigger); `sign_loan` requires the schedule to equal the principal | `funding_test` |
| Pauses never change the total | `pause_loan` only moves due dates, within the allowance; `resume_loan` and `resume_ended_pauses` change only the status | `repayment_test`, `hardening_test` |
| Default plan agreed up front | `family_loans.default_plan`, set only before signing (`set_loan_terms`); `repay_on_sale` requires a secured loan (check); `apply_default_plan` is service-only, audited, and refuses a loan that owes nothing | `repayment_test`, `hardening_test` |
| The default trigger is agreed, not improvised | `loan_default_due` (service only) lists a loan only when it is still collecting, has three or more unpaid installments more than 10 days past due, and has used up the pause allowance agreed in 12 months — so the borrower's reminder and pause-offer conversations come first and nothing changes a loan on its own | `loan_servicing_test` |
| Forgiving part of a loan keeps the totals true | `forgive_loan` writes the forgiveness and takes the same amount off the last unpaid installments (dropping a row when nothing would be left), so the schedule left sums to exactly the outstanding amount and collecting it trips no totals check; forgiving more than is owed is still refused | `loan_servicing_test` |
| The reliability record says "on time" | `loan_installments.paid_on` is written by a trigger only with the payment that finishes an installment, and `my_reliability` counts payments made on or before the due date. Installments paid before that column shipped carry no date, so they don't count as on time — the record understates rather than invents | `loan_servicing_test` |
| A proposed schedule can't start in the past | `set_loan_schedule` refuses a first due date before today, so a loan can't be made with payments already overdue | `loan_servicing_test` |
| The AI never refuses | The status guard rejects `refused` unless a `refuse` review was written in the same transaction; `record_score` can only route to open, needs evidence or in review | `requests_test`, `reviews_test` |
| No self-review or same-region review | `record_review` checks; roles count only for `active` members (`has_role`) | `reviews_test`, `hardening_test` |
| Every refusal can be appealed, once, to someone independent | `record_review` can't re-decide a `refused` request; `file_appeal` allows one appeal per refusal; `decide_appeal` refuses the appellant and anyone who reviewed the request | `reviews_test`, `hardening_test` |
| Reviewers are safe from retaliation | Members can't read `reviews` rows on their own requests; `my_request_reviews` omits `reviewer_id` | `hardening_test` |
| Dues follow earnings, never a cliff | `subscription_amount` version 2 charges 1% of the amount ABOVE the floor (income at the floor costs $0, a cent more income costs at most a cent more), still capped like v1; the live formula stays v1 until its own `effective_from` — dues never change silently | `dues_marginal_test` |
| No joining after the incident | `submit_request` checks `coverage_started_on` and the asset's `registered_on` against `waiting_days` | `requests_test` |
| Evidence is redacted before anyone sees it | `submit_request` requires every redaction to be `confirmed`; the board shows only `public_summary`, and only once the member confirmed it (`on_board`); the originals bucket is owner-only | `requests_test`, `rls_test`, `board_privacy_test` |
| The board answers a card's money questions on the card | `board_requests` carries `raised_cents` (only while `open`) and `taking_pledges` (open and the payee verified), so the page reads one view rather than asking per card | `board_progress_test` |
| A payout's outcome is the service's to report | `report_payout` moves only honest steps (pending→sent/failed, sent→returned; failed/returned terminal), the same report twice is a no-op, and a payout can't be reported back once money was refunded (that needs a person) | `payout_reporting_test` |
| Small numbers don't identify people | The board shows bands, month and division (`board_requests`); `request_raised_cents` answers strangers only while a request is open; `open_books` hides small counts and dominated totals; pool runs and other members' allocations aren't readable | `board_privacy_test`, `hardening_test` |
| Money only ever aims at the right kind of payee | `submit_request` needs `payee_fits(request kind, payee kind)`: cars go to a repair shop, a repair to a contractor, home money to a lender, seller or title company (the same mapping the web form offers) | `payee_fits_test` |
| Stale requests expire, and expiry is the cron's alone | `expire_request` moves only open/needs-evidence; the payout guard refuses expiry while money is out; pledges release via the close trigger | `expire_requests_test` |
| Loan money only moves through the service, up to what is owed | `record_loan_payment` collects only on still-collecting loans (active/paused), never on a paused installment, and refuses more than owed; a full installment dates itself and finishes the loan through the existing triggers | `loan_collection_test` |
| A supporter sees only what their page needs | `support_requests` (security barrier) carries the ask, story, status, incident date and a payee id that hides itself until the payee is verified; the whole request row — `current_score` included — stays the owner's and the console's | `support_view_test` |
| The ledger mirrors the schema's refund split | `mark_refunded` returns the `refunded_cents` figure it stored (computed by `refunds_due`); the payments webhook journals exactly that and refuses a partner figure that disagrees; the refund journal uses the fund's seeded account codes (`partner_cash` → `available`) | `refund_figure_test`, `deno test` |
| Income is checked honestly, then read only | `record_income_verification` takes only active members, requires the vendor's reference on a bank-linked figure (so it can be traced), refuses negatives; the member keeps reading their own checks (existing policy) | `income_verification_test` |
| The ledger balances the partners report | `ledger_balance` reads fund-level account totals (service only); `reconcile` never republishes a month and never moves money from here | `ledger_balance_test`, `deno test` |
| Evidence files are what evidence can be | both buckets declare `allowed_mime_types` (photos, clips, documents) and a 20 MB size limit, so the server refuses anything else, not just the web app | `evidence_limits_test` |
| A covered claim is paid in full, minus the member's share | `claims.paid_cents = gross - share` by check; the partner's feed records idempotently by `partner_ref`; a denial needs a reviewer's recorded refuse decision in the same transaction and is audit-logged | `insured_claims_test` |
| Opening an original for a review leaves a trail | `record_evidence_url` audits every issuing (request + path); same-region and self pairings sign nothing at all | `evidence_url_audit_test`, `deno test` |
| A payout opens against funded money only | `create_payout` (service, idempotent by payout ref) starts rows `pending`; guard_payout holds funded request, named verified payee, final invoice, captured ceiling | `payout_creation_test`, `deno test` |
| Money that reached the payee isn't refunded or abandoned | The status guard blocks refusing, withdrawing or expiring a request with a pending or sent payout (`record_review` routes to `in_review`); `paid` needs a sent payout covered by captured money; `refunds_due` nets out live payouts | `service_paths_test` |
| Pay the payee, never the member | `payouts` guard trigger; payees are businesses, never members; `pledge` and `run_pool_allocation` wait for a verified payee (`submit_request` doesn't, so verification runs alongside scoring) | `ledger_test`, `hardening_test` |
| Pledges are all-or-nothing | Funded when pledges reach the amount; released on withdraw, expire or refuse; money already captured is listed in `refunds_due` and marked by `mark_refunded` | `funding_test`, `hardening_test` |
| No money moves on an unsigned loan | `capture_contributions` refuses unless the request is funded and every loan behind it is signed; a loan becomes `active` only when its request is paid, and only active or paused loans can be paused, forgiven or defaulted | `hardening_test`, `funding_test` |
| Only people you know can lend | `pledge` requires an accepted invite and an active member for `loan`; a stranger can give only to a request on the board | `funding_test` |
| An invite says what you're joining | `invite_preview(token)` looks the token up by hash and names the owner, title, kind, funding, amount and status before the click; the read is written in `audit_log`; a used, cancelled or expired link answers nothing at all | `invite_preview_test` |
| A link can be handed back | `revoke_invite(invite)` for the owner only, refused once someone joined; a cancelled link never accepts and never previews | `invite_preview_test` |
| Names stay inside an invite pair | `request_names(request)` answers an owner with their supporters' names (plus the relationship each said) and a supporter with the owner's name plus their own; no other reader reaches a `members` row | `invite_preview_test` |
| Pool pays by band, highest first, all at once | `run_pool_allocation` (same algorithm as `apps/web/src/lib/requests/allocation.ts`) | `pool_test` |
| The pools never mix | Every ledger journal stays within one fund and has at least two lines (deferred constraint trigger, `post_journal`) | `ledger_test`, `hardening_test` |
| Open books | `open_books` (published monthly snapshots) and `fund_settings` readable by anyone; `fund_settings` changes logged | `rls_test`, `board_privacy_test` |
| The giving record is private and never ranks | `my_giving_record` returns only the caller's data; nothing in allocation reads it | `repayment_test` |
| Other members' money and cover stay private | `request_raised_cents` only for those who can see the request; `coverage_started_on` and `loan_outstanding_cents` are security invoker; `pool_requests_paid_3y` is self-only | `rls_test`, `repayment_test`, `hardening_test` |
| Financial records outlive accounts | Members are never deleted (requests are `on delete restrict`; history is append-only); `close_account` refuses while anything is open, then scrubs and closes | `hardening_test` |

## Access model

| Role | Can |
| --- | --- |
| `anon` | Read the fund rules, subscription formulas and the published open books |
| Member (`authenticated`) | Read their own data (but not who reviewed their requests); edit their display name (not their region); create and edit drafts; add evidence; submit, withdraw and appeal through RPCs; confirm their request's public summary; pledge to requests they're invited to or that are on the board; set terms and schedules for, sign, pause and resume their own loans; cancel their own waiting invite links and read the names of the people they're paired with; close their account |
| Supporter | Read the requests they were invited to and how much they've raised |
| Reviewer (active members only) | Read requests waiting for a person (never their own); record reviews (not on refused requests); see scores and the reviews they wrote |
| Panel (active members only) | Decide appeals (never their own, nor on a request they reviewed); read full review rows on requests that aren't their own |
| `service_role` (edge functions only) | Record scores, fraud signals and identity checks, run the pool, publish the monthly open books, verify payees, capture pledges, record refunds, payments and payouts, post journals, resume loans whose pause has ended, apply default plans |

Storage has two private buckets. `evidence-original` holds files under the member's own folder, readable only by the member; reviewers get short-lived signed URLs from an edge function that writes to the audit log. `evidence-redacted` is readable by the owner, and by verified members once the request is on the board.

## Edge functions

Two are built (`apps/backend/functions/<name>/index.ts`, Deno, tested by `pnpm test:edge`); the rest are
the plan for what to build, in `functions/` when each is built.

| Function | Triggered by | Does | Local stand-in |
| --- | --- | --- | --- |
| `verify-identity` ✅ | Signup | Starts an identity check; the vendor's webhook calls `record_identity_check`, which stores the reference and sets the member `active` | Fake vendor that approves `*@test.com` (`functions/verify-identity`, tested by `pnpm test:edge`) |
| `verify-income` ✅ | Member links a bank | Reads income only (never a password), writes `income_verifications` through `record_income_verification`, prices the subscription | Fixture statements (function built in `functions/verify-income`, annual→monthly conversion and credential-touch refusal pinned by `deno test`) |
| `redact-evidence` ✅ | Evidence upload | Blurs faces, plates, names and account numbers, writes the redacted copy and `auto_done`, computes hashes | Open-source face and plate detection running locally; the stand-in copies the file and masks region counts, but the file-exists-and-hash check is real (`functions/redact-evidence`, tested by `pnpm test:edge`) |
| `score-request` ✅ | Status becomes `scoring` | Builds inputs from redacted and original evidence plus fraud signals, calls the model, then `record_score`. The evaluation gate (300+ labelled cases approved, stamped) keeps scoring OFF until then — a blank stamp refuses before any call | Ollama model behind the same provider interface (function built in `functions/score-request` with the provider seam and gate pinned by `deno test`; the bundled scorer is a LOCAL HEURISTIC STAND-IN until the model arrives) |
| `fraud-checks` ✅ | Evidence and request events | Duplicate-photo and pattern checks; records flags with `record_fraud_signal` and clears them with `resolve_fraud_signal` | Same code, local data (duplicate-photo leg built in `functions/fraud-checks`, pinned by `deno test`; pattern v2 joins later) |
| `evidence-url` ✅ | Reviewer opens evidence | Issues a short-lived signed URL (15 min) for the original and logs it. Same-region and self pairings sign NOTHING — no URL, no audit | A real sign endpoint for the URL itself (function built in `functions/evidence-url`, pairing/window decisions pinned by `deno test`; audit via `record_evidence_url`, pgTAP `evidence_url_audit_test`) |
| `payments-webhook` ✅ | Payment partner | Calls `capture_contributions` once the partner confirms a funded request's charges; refunds each contribution's `refund_cents` from `refunds_due` and calls `mark_refunded`; reports payouts `sent`, `failed` or `returned` through `report_payout`; records repayments and payouts; posts journals with `post_journal` (the `public` wrapper, service only, at least two lines) | Partner's test mode, or a local webhook sink (function built in `functions/payments-webhook`, its calls pinned by `deno test`; the loan-repayment leg still to wire) |
| `run-pool` ✅ | pg_cron, weekly | Reads the custody balance, then calls `run_pool_allocation` once per fund with money in custody (only funds holding money get a weekly run; the schema's guard refuses the rest) | Balance from a fixture (function built in `functions/run-pool`, schedule decisions pinned by `deno test`) |
| `reconcile` ✅ | pg_cron, daily | Publishes the open books for the month that ended over a week ago, then compares ledger balances (`ledger_balance`, service-only) with the partners' statements and reports any difference | Fixture statements (function built in `functions/reconcile`, month/lag decisions pinned by `deno test`; statements still a fixture) |
| `loan-servicing` ✅ | pg_cron, daily | Calls `resume_ended_pauses`, collects due installments through `record_loan_payment` (a guarded owner for the money write: only collecting loans, never more than owed), sends reminders, offers pauses on missed payments; reads `loan_default_due` and hands each listed loan to `apply_default_plan` | Fake collector (due-date decisions pinned by `deno test`) |
| `expire-requests` ✅ | pg_cron, daily | Expires stale open and needs-evidence requests, which releases their pledges (stale = nothing touched for the fund's `waiting_days`; the guarded skip keeps money with the payee a person's) | Same (function built in `functions/expire-requests`, staleness pinned by `deno test`; `expire_request` pinned by pgTAP) |
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
