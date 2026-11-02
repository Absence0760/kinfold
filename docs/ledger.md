# Decision ledger

The record of judgment calls taken on the operator's behalf while building the roadmap: what was decided, why, and where it lives. Newest first. Each entry names the change that carries the call. Reverse any call you disagree with and the change with it — the ledger stays the place to read the calls without re-reading the code.

## 2026-11-02 — The dues screen names its earnings check (`income_verifications` on the home)

- **The membership block now shows which earnings check priced dues** (bank link / tax return / self-attestation, verified on, and whether it is still live until its expiry), so a member can see that an expired check needs redoing rather than silently pricing off old income. No check yet is honest ("No earnings check yet"), never a $0 income. **Reversal:** hiding the method would make dues look like a flat fee when the whole design says they track verified earnings.

## 2026-11-02 — Cover comes in filed plans, priced by risk not earnings (`cover_plans`, pgTAP `cover_plans_test`)

- **The partner insurer's filed group rate lives in the data**: one premium and cap per vehicle CLASS and PLAN (Basic, Standard), with the schema refusing any write that would price Standard at or below Basic inside a class (more premium must buy at least as much cap). A member chooses their plan (`cover_choices`, `set_my_plan`) but can never write a filed rate — only the service files, and each change leaves a history row and an audit trail. **Reversal:** a single global cap (the old `fund_settings.max_request_cents` alone) can't express class-based rates without turning earnings into a cap, which rating law forbids.

## 2026-11-02 — Subrogation money is recorded verified in one step (`record_partner_recovery`)

- **When another driver is at fault, the at-fault party’s insurer should pay** (design.md: Kinfold’s cover must not subsidise other insurers). The partner insurer reports the money that moved; the schema records it **already verified, in one write** — a separate `verify_recovery` step could leave a half-verified row a retry would double-count. Retry-safe by the partner’s reference. Money moved between insurers, so it never joins Kinfold’s ledger; the pledge caps and pool needs subtract it. **Reversal:** letting members write subrogation money themselves would let a member claim money no insurer moved.

## 2026-11-02 — Quarters sum the published months, never re-derive them (`quarterlySummaries`, `/transparency`)

- **The quarterly open-books report is a sum of the published monthly figures** (per fund and calendar quarter), so the report can never disagree with the month pages beneath it; a quarter with fewer than three published months carries its months count so readers see it is partial rather than guessing. **Reversal:** recomputing quarters from raw journals could publish figures the month-level small-numbers rules never approved.

## 2026-11-02 — A reconcile difference is recorded, not just logged (`ledger_differences`)

- **When a statement and the ledger disagree, the difference is stored** (append-only, audit-logged, service-only: fund-level books are money members never see) so an operator can find the alert later; the log line still accompanies it. A statement that MATCHES stores nothing. **Reversal:** leaving alerts as a returned string buries the only record of a discrepancy in whichever cron log survives.

## 2026-11-02 — The request page records other money for the same damage (`RecoveriesPanel`)

- **Other money that covered the same damage now has a place on the request page** — the member's own cover declared at request time, another insurer's claim, FEMA/SBA/state/charity money — with a record form the requester can write through (`record_recovery`; the schema re-checks and subtracts it from pledge caps and pool needs). It is money that moved outside Kinfold, so funding, payout caps and refunds still count only pledges and payouts; the page says so rather than implying Kinfold raised it. **Reversal:** hiding the record from the page would leave the pledge caps subtracting money the member can't see, making the ask look smaller for an unexplained reason.

## 2026-11-02 — The home shows dues, cover and plan (`lib/dashboard/membership.ts`, `/app`)

- **The member's home now reads their dues** (own figure, this month's charge status from the partner: collected / asked-not-collected / failed / refunded / not asked yet), **their cover** (vehicles covered, claims paid so far) **and their directable-share plan** (weights must add to 100, or none yet is said honestly). No dues is not faked as $0: it says so. **Reversal:** showing only dues amounts would leave the member unable to tell an un-collected charge from a refunded one, which the agreement says they must see.

## 2026-11-02 — "Legitimacy score" becomes "evidence score" (web copy)

- **The app and site now say "evidence score"**, per design.md's business-model review ("legitimacy score sounds like an accusation"). It measures how well the evidence supports the request; low scores ask for more evidence and never refuse. Copy-only: the schema always said `score` neutrally, so nothing moved in the database. **Reversal:** keeping "legitimacy" would imply an accusation to honest members and invite regulators to read it as a claims model.

## 2026-11-02 — The insurer's feed closes claims (`…360000_claim_paid.sql`, `functions/claims-feed`)

- **`mark_claim_paid` is idempotent and refuses denials** (a denied claim pays nothing, code 23514) and audit-trails the confirmation with the event's partner reference; `claims-feed` journals a confirmed payment exactly gross minus the member's share — out of the insurer's side, into `paid_out`. **Reversal:** journaling on RECORD would claim money moved the insurer never confirmed.

## 2026-11-02 — The console decides standing claims (`/app/review`, `ClaimCard`)

- **The review console now lists standing insured claims** (RLS answers with exactly the claims on requests a reviewer may review) and **offers a denial form whose reason carries the decision**, calling `decide_claim` so the refusal and the denial land together. A member's own request page keeps only the appeal affordance — denial is a reviewer's act. **Reversal:** putting the denial affordance on the request page would let the requester deny their own claim.

## 2026-11-02 — Denying a claim is one atomic decision (`decide_claim`, pgTAP `claim_decision_test`)

- **`decide_claim(claim, reason)` records the reviewer's refusal and denies the claim in one transaction.** `deny_claim` only accepts a refusal recorded at the SAME instant (`reviews.created_at = now()`, and `now()` is fixed per transaction) — two PostgREST calls are two transactions with different instants, so the two-step console flow could never satisfy it. A claim denial therefore also refuses its request (the repo's rule: only a person's recorded decision can deny a claim). Reviewers can now read standing claims of what they may review, so the console can show the claim before closing it. **Reversal:** loosening the same-instant rule would let anyone deny a claim with no reviewer decision behind it.

## 2026-11-02 — Fraud v2 joins the checks (`functions/fraud-checks` cross patterns)

- **Cross-shop, cross-vehicle and cross-request patterns now flag low-severity signals**: a shop already carrying other members' requests, an asset that reads exactly like another member's (same description and value), and another member's copied public summary. A member's own requests never cross-flag. **Reversal:** flagging these high would accuse innocent patterns (popular shops, the same car damaged twice); only duplicate-photo reuse stays high because money on someone else's damage is near-certain.

## 2026-11-02 — Claim denial is atomic, not two web calls (decision, followups)

- **`deny_claim` refuses unless a reviewer's refusal was recorded in the SAME transaction** (the schema pins `reviews.created_at = now()`). Two PostgREST calls from the console land in different transactions with different clocks, so the two-step web flow can never satisfy it; the console affordance needs a single `decide_claim` service path instead. **Reversal:** dropping the same-instant check would let anyone deny a claim without a reviewer's decision behind it.

## 2026-11-02 — Claims appear on the request page (`lib/requests/claims.ts`, ClaimsPanel)

- **The member's request page now lists insured claims** (figures exactly as the schema stored them — the gap to the shop is never recomputed), and **a denied claim offers the requester an appeal** with a reason of at least 10 characters; the schema decides and its error text is shown verbatim. Claims read via `fromNew` (generated types lag), and a failed claims read is empty rather than a crash: RLS decides who sees them. **Reversal:** showing claims only in the review console would leave the requester unable to see why their deductible paid or didn't.

## 2026-11-02 — Open books get a public page (`/transparency`, `lib/transparency/`)

- **The transparency dashboard reads `open_books` anon-only** — the table only exists with the schema's small-numbers rules baked in at publish time (counts 0 or ≥ 11, money rounded to $1,000), so the page never re-derives or unmasks: it formats what the schema published. A failed read explains its kind (session/network/server); a not-yet-configured stack says so rather than showing blank money as zero. **Reversal:** computing totals client-side from raw rows would bypass the publish-time privacy rules entirely.

## 2026-11-02 — Denied claims get an appeal (`…350000_claim_appeal.sql`)

- **`appeal_claim` (requester only) re-opens a denied claim** — back to `recorded`, decision cleared, audit-logged with the written reason — completing design.md's "denials only by a person, with appeal". A re-opened claim counts toward insured cover again, so the pool stops paying what the insurer will. **Reversal:** letting other members appeal would put money decisions on people the damage was never offered to.

## 2026-11-02 — Dues get a collection flow (`…340000_dues_collection.sql`, `functions/charge-dues`)

- **Dues collection rides the payment partner**: the monthly cron creates a pending dues ask at the member's OWN figure from their active subscription (`enqueue_dues`; a $0 subscription has nothing to collect), the webhook's `dues_captured` leg closes it (`capture_dues`, answers with the stored figure) and journals that number into the fund. **Reversal:** a member self-marking dues captured would fund the cooperative without the money moving; journaling the partner's word would fight the schema's figure.

## 2026-11-02 — The pool stacks after insured cover (`…330000_pool_insured_cover.sql`)

- **A request's pool need now subtracts insured deductible cover before pledges** (`insured_cover_cents` sums standing claims' gross; a denied claim covers nothing), matching design.md's split into insured cover (partner insurer pays in full, minus the member's share) and the gift-funded repair fund. Band math, reserve and ordering stay the schema's bands-v1 run, so the parity tests keep their figures; `allocation.ts` and its vitest mirror the new line (two new cover cases). **Reversal:** leaving cover out of need would pool money the insurer already paid, and pooling before cover would fight the deductible's priority.
- **The `subscriptions`→dues table rename stays deferred**: it touches every fixture and the web dashboard at once, and without the stack up we can't run the rename's tests; it goes in with a stack window. **Reversal:** a blind repo-wide rename we can't test is exactly what the schema's "every rule pinned" ethos forbids.

## 2026-11-02 — Loan repayments ride the webhook (`loan_repaid` leg)

- **The webhook's repayment leg only calls `record_loan_payment`** — the guard already owns collecting-loans and the owed ceiling — and **journals NOTHING**: loan money sits with the family, not on the payment partner's side, so the fund ledger says nothing about it. **Reversal:** journaling repayments as partner money would claim money moved that never touched the partner.

## 2026-11-02 — Payouts get an opening door (`…320000_payout_creation.sql`, webhook leg)

- **`create_payout` (service only, keyed by the partner payout reference) opens payout rows** — before, `public.payouts` had no insert path at all, so the console and the webhook had nothing to call. Rows start `pending`: money moves when `report_payout` says `sent`, and the guard (funded, named verified payee, final invoice, captured ceiling) that was already on the table does the rest. A replayed payout event is a no-op answering with the payout it made. **Reversal:** journaling at opening would count money as moved before it is.

## 2026-11-02 — Evidence URLs leave a trail (`…310000_evidence_url_audit.sql`, `functions/evidence-url`)

- **`record_evidence_url` audits every issuing of a reviewer's signed URL** (request + file path in jsonb) — PII reads trail their name, same as every other affordance. Only the service issues.
- **`evidence-url` mirrors the review pairings before signing anything**: same-region and self pairings sign NOTHING — no URL exists, so nothing is audited for a refusal either. URLs are 15 minutes, a review's length, not a day. **Reversal:** a day-long URL would let a link be shared long past the review. Regions are compared as a boolean inside the function; the value never leaves the read.

## 2026-11-02 — Scoring gets a gate and a provider seam (`functions/score-request`)

- **Scoring stays OFF behind an evaluation-set gate**: until a labelled evaluation set (300+ real-shaped cases) is reviewed and its stamp deployed, the function refuses before any provider call — requests wait in the queue. **Reversal:** turning scoring on without the set would route money on unreviewed judgements.
- **`score-request` goes through a `Provider` interface** and writes provenance (`model`, versions, inputs hash) with every score, so the console can retrace each one. **Reversal:** baking a model into the function would make the prod swap (Ollama locally, hosted model in prod) a schema change. The bundled scorer is an honest LOCAL HEURISTIC STAND-IN — evidence completeness, not picture understanding.

## 2026-11-02 — Insured claims record (`…300000_insured_claims.sql`)

- **`claims` records the partner insurer's paid claims: gross, the member's share, and `paid_cents = gross - share` enforced by a check** — the score decides speed and scrutiny, never the amount, so nothing here recomputes money. `record_claim` is service-only and keyed by `partner_ref` (unique), so a replayed feed entry is a no-op that answers with the existing row.
- **`deny_claim` only works right after a recorded refuse review** — the same all-or-nothing pattern the status guard uses (`created_at = now()` in the same transaction) — and the denial is audit-logged with its reason. **Reversal:** letting a denial stand on its own would let the feed veto payments without a person's decision. The ledger journal for insured claims still goes through the payments webhook when that leg is wired.

## 2026-11-02 — Repair-fund weekly run (`functions/run-pool`)

- **`run-pool` runs the allocation once per fund that has money in custody**, and a schema-guard refusal is a logged skip, not a crash. The allocation math itself stays in `run_pool_allocation` — this file only owns the schedule and the balance read. **Reversal:** computing bands or reserves here would fork the schema's allocation rules.

## 2026-11-02 — Evidence buckets get their limits (`…290000_evidence_limits.sql`)

- **Both evidence buckets now declare `allowed_mime_types` (photos, clips, documents) and a 20 MB `file_size_limit` on `storage.buckets`** — the server, not just the web app, refuses anything else. **Reversal:** web-only checks leave the direct API path unbounded. The column names come from Supabase's storage schema and can't be exercised without Docker — CI is the gate for this one.
- **The loan-terms operator's call answered: intended as-is.** While `proposed`, either side may change terms, and the database's own line `borrower_signed_at = null, lender_signed_at = null` means a change signs nobody — both parties must re-sign. No new rule needed; the invariant already lives in `set_loan_terms`. **Reversal:** restricting who may edit terms would fight design.md's "borrower and lenders set the amount, schedule and purpose".

## 2026-11-02 — Books reconcile (`…280000_ledger_balance.sql`, `functions/reconcile`)

- **`ledger_balance(fund, code)` gave the daily reconcile job a service-only read of fund-level ledger accounts** — the ledger lives in `private`, which PostgREST never exposes, so there was no honest way to ask what's in an account. Member/payee money stays theirs; members never see the books.
- **The reconcile job publishes the newest month that ended over a week ago** and never republishes (`publish_open_books` refuses a second row per fund per month, and the job treats that as a skip). A payout returned after its month was published stays counted there — corrections land in the NEXT month's numbers, so the books are written once, honestly. Ledger differences against the partners' statements are REPORTED to the cron's log, never moved from here (statements are a fixture until the partners' feed swaps in). **Reversal:** republishing a month to absorb late returns would rewrite published public totals.

## 2026-11-02 — Income checks get an owner (`…270000_income_verification.sql`)

- **`record_income_verification(member, method, cents, ref)` became the guarded way to write an income check** — active members only, no negative figures, and a bank-linked figure must carry the vendor's reference so the check can be traced back to the read that produced it (self-attested figures carry none by design). **Reversal:** deleting it hands `income_verifications` bare writes and dues priced from untraceable figures.
- **`functions/verify-income` converts the vendor's ANNUAL income to the monthly figure the dues formulas price (floored whole cents)** and refuses any report that touched a credential field before anything is written — income only, never a password, never a transfer. **Reversal:** trusting the vendor's own monthly figure or trimming credential-touch instead of refusing would price dues off untrustworthy reads.

## 2026-11-02 — Refunds answer with their figure (`…260000_refund_figure.sql`)

- **`mark_refunded` now returns the figure it stored** (`refunded_cents` computed by the `refunds_due` split), and the payments webhook journals exactly that number — a partner event claiming a different amount is refused so no journal can contradict the row it owns. **Reversal:** keeping `void` means the ledger mirrors the partner's word, and a wrong event figure silently mis-records money.
- **Journal account codes are the fund's seeded ledger accounts** (`partner_cash`, `available`, `reserve`, `committed`, `paid_out`) — the webhook used invented codes that `post_journal` would refuse. Refunds journal `partner_cash → available`; payouts `available → paid_out`, reversed for `returned`; `failed` journals nothing. **Reversal:** inventing codes needs new ledger accounts with no role in the design.
- **CREATE OR REPLACE resets a function's grants** (they live on the function object, not the signature). `mark_refunded` had been create-or-replaced by `…120500_service_paths.sql` with no grant re-claim after — the replacement re-claims service-only here. **Reversal:** leaving grants at their default would hand money-moving to every authenticated member. Worth an audit pass over other replaced functions.

## 2026-11-02 — Marginal dues formula (`…250000_dues_marginal.sql`)

- **`subscription_amount` grew a `marginal` flag on the formula rows and version 2 (1% of the amount above the $1,500 floor) entered effective 2027-01-01** — closing the $15 cliff followup without touching today's dues. **Reversal:** switching the live version now would change what every member is charged with the actuarial review unmade; design.md keeps the figures pending review, so the switch stays dated.
- **v1 keeps its row and meaning** (published pricing history, and a member's subscription records which version priced it), so old receipts still read against the formula that made them. **Reversal:** replacing v1 in place would make past dues unreproducible.

## 2026-11-02 — The supporter's view replaces the whole-row read (`…240000_support_view.sql`)

- **The "supporters read requests they back" policy was dropped and a `support_requests` barrier view took its place** — the supporter's read is now exactly the ask, the story, the status, the incident date and a payee id that hides itself until the payee is verified. The request row (score, timestamps, the payee link while unverified) stays the owner's. **Reversal:** keeping the row policy means every supporter carries the score and every private field of the row.
- **The web's `fromNew` seam reads tables/views newer than the committed generated types** — same reason and same honesty note as `rpcNew`: types are regenerated only from a live stack, so new relations arrive untyped and the call site pins the shape. **Reversal:** hand-editing `database.types.ts` would put generated and handwritten truth in one file.

## 2026-11-02 — Loan money gets an owner (`…230000_loan_collection.sql`)

- **`record_loan_payment(loan, seq, cents)` became the service's guarded way to move loan money** — nothing owned the installment write before, so a loan could quietly become "paid" with no record. Still-collecting loans only (active/paused; signed money hasn't moved, forgiven/repaid/cancelled are over), never a paused installment (the pause was agreed by both sides), and never more than what the installment owes. The full installment's paid date and the loan's `repaid` turn stay the existing triggers' jobs. **Reversal:** deleting the function puts bare writes on `loan_installments` back with no owner and no audit trail.
- **The webhook's "records repayments" leg now has a real call**, and the daily loan-servicing job decides WHAT is due (pure, pinned by `deno test`) and calls this guarded function — the database owns overdue (the `loan_default_due` view) and pause end (`pause_ends_on`), the job never re-decides. **Reversal:** letting the job compute defaults itself would fork the overdue rules.

## 2026-11-02 — Duplicate-photo fraud signal (`functions/fraud-checks`)

- **A reused photo flags high-severity `duplicate_photo` on the NEW request, one signal per other request matched** — perceptual-hash equality across requests. The member's own second photo on their own request never matches (same request_id is excluded); evidence still awaiting redaction has no perceptual hash and flags nothing — no accusation without evidence. **Reversal:** one signal with many details would collapse each decision trail; chosen shape is per-match.
- **The Deno layer only decides WHEN to flag; the flag itself lives behind `record_fraud_signal`** (service-only, audit-logged). `queryRows` in `rest.ts` is the service's read path for cron-time jobs — reads only, writes still go through guarded functions. **Reversal:** letting a job write `private.fraud_signals` directly would dodge the audit trail and the owner rule.

## 2026-11-02 — Expiry owned by the cron (`…220000_expire_requests.sql`)

- **`expire_request(uuid)` became the service's guarded way to expire a request** — only open or needs-evidence move; a draft is a member's to withdraw; the payout guard in …120500 keeps money-out requests a person's, so the cron's skip is a caught refusal, not a crash. Pledges release and unsigned loans cancel through the existing close trigger — expiry goes the same path as withdrawal. **Reversal:** deleting the function lets expiry happen as a bare table write with none of these owners.
- **Staleness = nothing touched the request for its fund's `waiting_days`** (newest pledge for open, newest evidence for needs-evidence; submission itself counts if nothing followed). The figure is `fund_settings.waiting_days`, so it moves with actuarial review, not in code. **Reversal:** a per-kind staleness rule would need a schema field; not chosen, the fund's waiting period is the shared patience.

## 2026-11-02 — Payout reporting owns the outcome (`…210000_payout_reporting.sql`)

- **`report_payout(uuid, outcome)` became the service's guarded way to move a payout**, replacing the webhook's bare table write: honest steps only (pending→sent/failed, sent→returned; failed/returned terminal), pending is never an outcome to report, and the same outcome twice is a no-op for replayed webhooks. **Reversal:** deleting the function puts webhook writes back on the table, with none of these rules enforced.
- **A payout can't be reported `returned`/`failed` once its request has refunded contributions** — this closes the open followup. `refunds_due` splits captured money over live payouts oldest first, and a late return wouldn't re-run that split, so the honest answer is a refusal that sends it to a person's decision (audit-logged). **Reversal:** re-running the split on returns would let the refusal back off — not chosen, because the ledger's shape stays frozen.
- **The webhook journals each refund with the REFUND amount, one journal per contribution** (journals are keyed by partner_ref, so refunds can't share a journal), and journals two money lines — out of one account, into the next — with amounts checked before any write so a bad event leaves no half a refund. A failed payout moves no money and journals nothing. **Reversal:** one journal per event (not per contribution) would collide on the unique partner_ref; a single-sided line would break the schema's two-line rule.

## 2026-11-02 — Board progress on the view (`…200000_board_progress.sql`)

- **`raised_cents` and `taking_pledges` became columns on `board_requests`** rather than a per-card RPC, so one read answers the whole board (the page used to call `request_raised_cents` once per open card). `raised_cents` is filled only while a request is `open`; a finished request shares none. `taking_pledges` is the same pair of rules `pledge` applies, so the page can say gifts aren't open yet instead of refusing the first gift. **Reversal:** the view is dropped and rebuilt; returning to per-card reads is deleting the two columns and restoring the map in `loadBoard`.
- **The web reads those columns as optional** (`BoardRow & { raised_cents?…, taking_pledges?… }`): the local schema has them, the committed generated `database.types.ts` doesn't until the live stack regenerates it. A row without them shows "progress not shown", never $0. **Reversal:** once `gen:types` runs, the optionals can become required.

## 2026-11-02 — Edge functions get their own layer (`apps/backend/functions`, `pnpm test:edge`)

- **Edge functions live in `apps/backend/functions/<name>/index.ts` in Deno 2**, which `supabase/config.toml` already pins (`deno_version = 2`, `[edge_runtime] enabled = true`). Deno is on this machine, so their pure logic gets real `deno test` coverage without Docker — this is what makes the payment and lifecycle functions testable at all here. **Reversal:** a different runtime for the functions means dropping `deno.json` and the `check:edge`/`test:edge` scripts, not moving the functions' code.
- **A function reaches the database through `functions/shared/rest.ts` only: PostgREST with the service key from the runtime environment, calling the same guarded functions the app calls** — never a direct table write, so a function's word is never more trusted than the function's own guard (`private.is_service()`) allows. **Reversal:** a different transport is one file (`rest.ts`); the rule itself is pinned by each function's guard test.
- **The local stand-ins are honest: only the vendor decisions stand in.** `verify-identity`'s fake approves `*@test.com` emails straight away; `redact-evidence` copies the file and masks region counts in place of face/plate detection — but the checks that precede it (the file reached storage at all, its SHA-256 matches the row) are real and pinned by tests, because marking `auto_done` over a file Kinfold never saw would let a member confirm a redaction of nothing. **Reversal:** swapping the stand-in is one function (`blurRegions`/`fakeVendorApproves`); the checks around it don't move.
- **`test:edge` runs the function tests; `check:edge` stays out of the `check` chain.** CI's runners don't ship Deno, and `ci.yml` runs `pnpm check` — adding Deno there means another unpinned Action, against the pinned-SHA rule. **Reversal:** when a Deno Action is pinned deliberately, `check:edge` joins `check` and `test:edge` joins the CI web job.

## 2026-11-02 — Payee kind fits the request (`…190000_payee_fits.sql`)

- **`payee_fits(request_kind, payee_kind)` is the single mapping the web form and the database read.** `submit_request` refuses a mismatch, so money can't aim at the wrong place: cars at a shop, a repair at a contractor, home money at a lender, seller or title company. Call: one small function rather than a table check, because the rule is about a *pair* of kinds, not one row. **Reversal:** if counsel ever wants shops on home money, only that function's body changes.
- **The refusal is at submission, not at the draft.** A member may save a draft naming any payee (the form offers only fitting kinds anyway, but drafts can be edited around it); the gate sits where money starts aiming somewhere, next to the other submission rules. **Reversal:** an insert-time check would push the rule onto drafts and fight the form's payee picker while editing.

## 2026-11-01 — CI gate, repo hygiene

- **CI runs the tests on every push to `main`** (`.github/workflows/ci.yml`): `pnpm check`, `test:web`, `test:scripts`, then pgTAP with the Supabase stack started by `supabase/setup-cli`. Follows the single-emitter pattern in [README-ci-gate.md](../.github/workflows/README-ci-gate.md): one `changes` filter job, heavy jobs gated on it, `ci-gate` as the aggregator with `if: always()`. Action SHAs pinned like the other workflows. **e2e stays out of CI**: `test:web:e2e` still runs only on demand (`setup:e2e` per machine), so CI can't pay for the Chromium download yet.
- **`docs/STACK.md` said "no CI job yet"** and now says what is and isn't in CI, because the stale sentence would have talked the next person into adding a duplicate job. **Reversal:** none — the copy follows the workflow file.
- **Backend rules are verified only in CI on this machine.** No Docker daemon (user not in the docker group, sudo needs a password) and no Supabase CLI installed, so `dev:db:up` and `test:backend:db` can't run locally here. Backend changes therefore land with their pgTAP tests, and CI turns them green or red the same day; a red run is fixed in the same session, not shelved.
- **Work lands on `main`, path-scoped** (CLAUDE.md, pre-launch no-PR decision): the checkout sat on a scratch branch `full_roadmap` sitting on the same commit as `main`; switched back to `main` and left the scratch branch alone (deleting it is the operator's call).
- **Push is blocked from this machine**: the account has pull-only permission on `Absence0760/kinfold` (SSH and token both refused). Commits stay local; the push needs the operator's own credential. Flagged in the session report.

## 2026-11-01 — Step 1f: invite links (`…180000_invite_preview.sql`)

- **`invite_preview(token)` is a security-definer lookup by hash, not a read policy.** The token is the whole secret: nobody can list invites, and only someone holding the link learns the owner's name, the title, kind, amount and status before accepting. It's a function rather than a view so the read can be audit-logged (`invite.preview`) like the evidence view. **Reversal:** a member who later wants the preview hidden from search-ish traffic would need the link gated by sign-in — deliberately not done: an invitee who can't open the link can't decide whether to accept it.
- **A cancelled link answers exactly like a used or expired one** (`invite not found`, same for preview and accept), so an owner cancelling a link tells nobody else anything about it. Cancelling is refused once the link was accepted: what the supporter did with it is theirs, and their way out is their own choice.
- **`accept_invite` was rewritten to refuse a caller with no member row** with "finish setting up your account" instead of a foreign-key crash; `errors.ts` maps both the old FK code path and the new message to the same words.
- **`request_names(request)` returns an owner's supporters (with the relationship each said) and a supporter's own plus the owner's name** — names never cross a pair, and a supporter's own entry stays out of the list. Kept as a function rather than the view the followup suggested because the answer differs by which side of the pair you are on; a view would have to expose every name in the request to everyone who can read the request at all.
- **The preview is a page load, and a dead link says so before the click.** The invite page reads `invite_preview` once on load and shows what you're joining; a null preview (used, cancelled or expired) shows the same words as accepting would, so the Accept button never sits under a link that can't work. **Reversal:** if the preview ever needs to be lazy, dropping the load-time call is one line; the audit trail says how often the read happens.
- **The preview carries `funding` as well as kind and status**, because the label for `open` differs between a people-funded and a pool-funded request; without it the page would have to guess what the fund is doing.
- **`revoked_at` is granted as a readable column to authenticated members**, not kept owner-only, because read policies on `request_invites` already scope which rows anyone sees and a column-level rule can't name the owner; the row scope is what keeps a cancelled link invisible to strangers.
- **Rows read with a column the generated `database.types.ts` doesn't have yet are cast once at the call site.** `gen:types` needs the live stack, so the local schema can outrun the committed types; the cast is documented where it happens rather than regenerating by hand. **Reversal:** once the stack regenerates the file, the cast is a no-op and can be dropped.
## 2026-11-01 — Step 1g: loan servicing (`…170000_loan_servicing.sql`)

- **Installments grew a `paid_on` date, written by a trigger rather than by callers.** `loan_installments` is written by several places (the schedule, the collector, the pause); a trigger keeps the date honest everywhere and the table check `(paid_on is null or paid_cents = amount_cents)` means a date can never exist on an installment that is still owed. `my_reliability` then counts payments made on or before the due date, which is what the name always promised. **Reversal:** rows paid before this column shipped carry no date and don't count as on time — the record understates rather than invents; if a backfill is ever wanted, it needs the partner's payment dates.
- **`forgive_loan` now cuts the tail of the schedule**, not just the forgiveness row: the last unpaid installments lose the forgiven amount (a row is dropped when nothing would be left, since a zero installment is refused elsewhere), so the remaining installments sum to exactly the outstanding amount. Before this, a partially forgiven loan still scheduled the whole principal, so collecting the last ones tripped the loan-totals check. Payments already made are never cut, so a borrower's repayment can't be erased by the lender's forgiveness. **Reversal:** the alternative — leaving the schedule alone and stopping the collector at what is outstanding — pushes the rule into an edge function and lets the ledger disagree with itself.
- **The default-plan trigger is a service-only view (`loan_default_due`), not an automatic status change.** Three or more unpaid installments more than 10 days past due, plus the borrower having used the whole pause allowance they agreed to in 12 months, and only while the loan is still collecting. The job reads it and calls `apply_default_plan`; nothing here changes a loan by itself, so reminders and pause offers keep their place in the conversation. **Reversal:** if the numbers ever need rethinking, only the view body changes; loans in a pause are deliberately excluded, since the borrower asked for that pause.
- **`set_loan_schedule` refuses a first due date before today.** The web form already blocked it; the database now agrees, so a loan can't be proposed with payments already overdue on the day it's made. **Reversal:** none — the web guard is now redundant but harmless.
- **The dashboard line changed from "paid of due" to "on time of due so far"** because the number's meaning changed. It is one copy string: honesty about what the reliability record counts.

## 2026-11-01 — Steps 1e and 1i: reviewer and panel access (`…160000_review_access.sql`)

- **One security-definer `private.may_review(request, reviewer)` decides reviewability.** Read policies, `record_review`'s rules and the console's `review_flags` all read the same boolean, so the queue, the RPC and the database can't drift apart. **Reversal:** a new anti-collusion rule (e.g. same town) is one line in that function.
- **The requester's region never reaches the client.** The console asks `review_flags(uuid[])` once for the page and gets booleans keyed by request id, so a reviewer can grey what they can't take without learning the requester's state. **Reversal:** if a reviewer ever needs the region itself, swap the RPC for a richer view.
- **Panel read policies use `private.has_open_appeal(request)`, not an inline subquery.** `appeals` has an `id` column too, so an inline `a.request_id = id` inside a policy on `requests` resolves to the wrong row and silently turns the policy off. **Reversal:** none — the pgTAP suite pins the panel reading the request and the score.
- **`decide_appeal` was dropped and re-created with a reason argument** (`appeals.decision_note`, 10–2,000 characters, audit-logged with it) rather than storing free text elsewhere; "every decision records reasons" now holds for appeals the same way it does for reviews. The web guard test that scans migrations for every `raise exception` forced a plain-words mapping in `errors.ts` before the suite would pass.
- **Redacted copies get a reviewer read policy; originals deliberately do not.** The audited path to an original is `evidence_view` (writes to `audit_log`) followed by the `evidence-url` edge function's short-lived signed URL, so nothing opens every original in a folder. **Reversal:** a direct original policy would trade the audit trail for a one-shot link — only if the edge function can't ship.

## 2026-11-01 — Step 1c: evidence lifecycle, money for the same damage (`…120600_board_privacy.sql`, `…150000_evidence_lifecycle.sql`)

- **`request_recoveries` is one table, not three.** The roadmap's "declare other cover" and "report insurer/FEMA/SBA recoveries later" are the same record in the database, so one append-only table covers both; `source` names the kind. Call: a member's own cover declared at request time stays in this table (it behaves identically everywhere else). **Reversal:** split `declared`/`reported` if a product reason needs them apart.
- **Recovered money never counts as funding but always shrinks need.** `private.recovered_cents` subtracts from the pledge cap (`pledge`) and the pool run's per-request need (`run_pool_allocation`); funding, payout caps and refunds still look only at pledges and payouts, so the two money kinds can't mix. **Reversal:** none needed; the pgTAP pins the property.
- **Redaction gains four affordances instead of changing `submit_request`.** Service-only `set_redaction_done` (pending/rejected → auto_done, only while `draft`/`needs_evidence`) and `set_public_summary`; member `reject_redaction` and `request_summary_change(request, note)`. Call: a member can't write their own summary (that would let them dodge redaction) — they file a note the service acts on. **Reversal:** if counsel wants member-editable summaries, the change is one new function.
- **Evidence file removal queues `private.evidence_deletions` rather than using a storage delete policy.** A policy can't run once the row is gone (the web app deletes rows); a queue can't race with it, and `mark_evidence_deleted` lets the service close entries. **Reversal:** a delete policy could replace this if row deletion were made service-only.
- **Bucket MIME/size limits deliberately not set in this migration.** The `storage.buckets` shape couldn't be verified without a running stack, so guessing at column names is off-limits; the item stays in followups.md until checked against the schema.
- **Two service functions were re-issued in full** (`pledge`, `run_pool_allocation`) to add the recovered-money subtraction: same bodies plus one subtraction each, verified against the current definitions in `funding`/`hardening`/`board_privacy` migrations so existing suites' error-wording assertions keep passing.
- **Root `package.json` had an accidental `"pnpm": "^12.16.1"` dependency** with a stray `package-lock.json` and a rewritten `pnpm-lock.yaml` — written by some global pnpm call. It grants access to nothing but confuses corepack version pinning; reverted all three paths.