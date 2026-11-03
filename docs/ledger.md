# Decision ledger

The record of judgment calls taken on the operator's behalf while building the roadmap: what was decided, why, and where it lives. Newest first. Each entry names the change that carries the call. Reverse any call you disagree with and the change with it — the ledger stays the place to read the calls without re-reading the code.

## 2026-11-03 — The board's web loader took the same db seam, so its fallbacks are pinned

- **The gap**: `loadBoard` read the `supabase()` singleton, so vitest couldn't hand it a fake client and its two fallbacks were eyeball-only - a `fund_settings` read that fails must leave the board standing with NO minimum (the page then drops the band's status line) rather than inventing a bar, and the fund that words a band comes from `fundForKind(kind)`, which is the same mapping the eligibility card and the request form rely on.
- **The decision**: same convention as the invite loaders the day before - `loadBoard(db, ...)`, `pledgeGift(db, ...)`, `loadRaised(db, ...)` with the board page, its retry and the pledge form passing `supabase()`. Then `board/data.test.ts` pins the own-row marking, the fund's own minimum words the band (repair fund's bar vs Home Fund's, deliberately different in the fixture so a swapped mapping fails), the settings-failure fallback, and that a refused board read throws `BoardLoadError` keeping the code for `explainBoardError`.
- **Why the mapping matters on the board**: a band's words are the only fairness claim a member sees before a person reviews; read against the wrong fund's minimum a Home Fund request would look like the repair fund pays it by band.
- **Reversal:** keep the singleton if the board grows and the loader moves to a shared, page-level read (the view column would already carry the fund's minimum); then this test moves to the view's shape rather than the loader's calls.

## 2026-11-03 — The invite loaders take the db seam so their display gates can be tested

- **The gap**: `invites/data.ts` called the `supabase()` singleton inside every loader, so nothing could hand it a fake client and vitest had no way to reach its display gates - the payee-name/verified check, progress-as-nothing-rather-than-$0, a stranger's request reading as nothing, a `request_names` P0002 being silence while any other code is a real failure. Every one of those was load-bearing on a supporter's page and eyeball-only.
- **The decision**: follow the convention the newer loaders already use (`loadCover(db, ...)`, `loadFundLoans(db, ...)`, `loadLoans(db, ...)`) - add `db: Db` as the first parameter to the nine invite loaders and have the four pages and one `+page.ts` pass `supabase()`. Then add `invites/data.test.ts` (fakeDb chain like the other loader tests) and pin the gates, plus `canInvite` against the six statuses `create_invite` accepts (the four closed ones read false).
- **Why this shape instead of mocking the singleton**: the db-as-parameter is already the repo's pattern for anything that wants a test, and it makes the seam explicit at the call site - a page now says which client it read with.
- **Reversal:** if the loaders kept `supabase()` internally, the same gates would need a global seam per test (fragile across concurrent pages) - only worth keeping if the client itself must stay global for a page-lifecycle reason; the client is already created lazily and shared.

## 2026-11-03 — The ops console can SEE reconcile differences; the reserve panel waits

- **The gap this closes**: `record_ledger_difference` wrote alerts into an append-only, service-granted table that nothing could read - the reconcile cron found differences and the operators had no place to look. Roadmap 1e says "reconciliation and reserve panels join in 2h", and the reconciliation half of that is a door problem, not a 2h problem: a reviewer needs to SEE an alert, and the ledger books behind it stay behind the service.
- **The decision**: a reviewer/admin-only door, `review_ledger_differences(limit)`, answers fund, account and BOTH figures (the partner's statement and the ledger's own number) newest first, audit-logging its own read like every privileged read. The console page lists them under "Differences on the books" beside the trail. No client-side re-derivation anywhere: the mirror keeps the row's shape and the figures as recorded, so a difference can't be hidden in the browser.
- **Why fund-level is allowed to cross**: these are the same class of aggregates `open_books` already publishes to everyone - fund accounts, never member, payee or vendor keys - and the test asserts a `member_id` key never appears in what the door answers.
- **What stays deferred**: the reserve panel. The reserve accounts exist in the schema, but a panel over them is money-management display with its own product decisions (how much of the reserve to show, and to whom) - left for 2h proper, per the roadmap line.
- **Reversal:** if the alert table were ever made readable by reviewers directly (a read policy over `ledger_differences`), this door collapses into the table grant and the TS mirror reads the table - the mirror's shape stays, and the audit-log hook for "the alerts were read" would need to move onto the table's read path to stay visible on the trail.

## 2026-11-03 — Every test name the docs claim was checked against the repo, and three were ambiguous

- **The audit**: each backticked test name in the 81 tracked `.md` files was resolved to a real artifact - a pgTAP `*.sql` in `supabase/tests`, a deno `*_test.ts` beside its function, or a vitest `*.test.ts` under `src/`. Every 14-digit migration prefix was checked the same way. Result after the fixes: 0 unknown claims.
- **The three ambiguous ones**: `charge_dues_test`, `pay_premiums_test` and `payments_webhook_test` are deno test FILES (`apps/backend/functions/<fn>/<name>.ts`), but written without an extension in a column that otherwise lists pgTAP suites, so a reader would go looking for a `supabase/tests/<name>.sql` that never existed. They now carry `.ts`, and the one row that said both the file and "deno test" lost the redundant word.
- **The stale count caught on the way**: `docs/STACK.md` claimed "All 58 suites agree"; the new `fund_for_kind_test` made it 59. A suite count in the docs is a claim about a date, so it now says "on 2026-11-03" to stay readable as a snapshot.
- **The false positive class worth knowing**: `offer_fair_lending_self_test` is a schema FUNCTION whose name ends in `_test`, and `is_active_member`-style helpers can look similar. The audit therefore accepts a `*_test` token that names a `create function`, and the ledger records it so a future sweep doesn't "fix" a real function name by deleting it.
- **Reversal:** if docs only ever cited the runner ("deno test", "pgTAP") rather than the artifact, these three rows would need no `.ts`; the file names were kept because a named artifact can be opened and a runner cannot, and the ledger's own rows already name files this way.

## 2026-11-03 — The transparency page's e2e pins the share rule's WORDING, not its figures

- **The decision**: the new browser test asserts the share section's heading, its problem line, and that the intro names the share rule - it asserts no percentages, because the published share rule needs the stack and the e2e build never has one.
- **Why**: without the stack every section shows its unconfigured line, so the only share-rule truth a preview build can carry is that the section exists and reads like a share rule. The figures themselves stay pinned by vitest (`data.test.ts`, two versions with their percentages) and by pgTAP (`paid_share_test`); the e2e closes the gap between them - that a real browser renders the section in its spot between the weights and the grants.
- **Reversal:** if the e2e project ever runs against the local stack, this test can assert the seeded v1 percentages (10%/30%) directly; keep it wording-only while the stack stays out.

## 2026-11-03 — The kind→fund mapping now has a test on BOTH sides

- **The gap**: `fundForKind` in `requests/form.ts` is documented as "mirrors `public.fund_for_kind`" and is used in real logic - the board words a score band against the fund's own `min_score`, and the eligibility card picks the fund's waiting period and claims cap by the same mapping. Neither side had a test: no pgTAP suite ever called `fund_for_kind`, and no vitest file referenced `fundForKind`. A silent divergence would have shown a member a bar and a waiting period from the wrong fund.
- **The decision**: pin the mapping itself, not just its effects. `fund_for_kind_test` calls the schema function for all six kinds; `form.test.ts` calls the TS mirror for the same six and asserts the mirror's `isCarKind` never disagrees with its own fund answer. The tests read the enum list, so adding a kind later fails here rather than quietly defaulting.
- **Why the mapping is worth its own test**: it is a lookup, not a rule, but nearly every fund rule (minimum score, band, inspection floor, waiting days) is reached through it, so one wrong line moves four rules onto the wrong fund at once.
- **Reversal:** keep only the schema side pinned if the TS mirror is dropped and the fund is read from the row (the view could carry it) - then delete `fundForKind` from `form.ts` in the same change, since the consumers would otherwise keep a second source of truth.

## 2026-11-03 — The pool's TS mirror now reads recovered money as its own field

- **What was wrong**: `allocation.ts` - the web's reference implementation of the pool's need line - read `amount - covered - funded`, while the schema reads `amount - insured_cover - raised - recovered`. Money recorded for the same damage (2g's `request_recoveries`, via `private.recovered_cents`) was simply absent from the mirror, so the two disagreed on any request with recovered money: the mirror asked the pool for money the schema already had covered. Nothing in the app passes `recovered` today (the landing board never has recoveries), so it caused no wrong figure on screen - a latent divergence, not a visible bug.
- **The shape of the fix**: `FundingRequest` gains `recovered?`, and the need line reads all four terms the schema reads. `covered` and `recovered` stay SEPARATE fields: insured deductible cover counts toward filling the ask (a claim can fund a request), recovered money never does - it is neither Kinfold's raised money nor insured cover. So a fully recovered request still waits for the pool, exactly as the schema's status rules decide.
- **Why pin it now**: the split is the subtle half of the need line, and the property test now generates `recovered` and asserts both bounds - a grant never exceeds the gap, and a request whose only money is recovered is never `funded`. A future consumer that shows member recoveries next to pool grants cannot drift from the schema without a red test.
- **Reversal:** fold recovered into `covered` if the mirror is only ever used for insured cover (the landing board case) - but then the mirror stops matching the schema and the property test goes red, so the split is the honest reading.

## 2026-11-03 — Every pgTAP plan count was audited against its assertions; one suite was over-planned

- **What was wrong**: `evidence_lifecycle_test.sql` declared `plan(46)` but makes 43 assertions. pgTAP counts each top-level assertion call as one test, and a suite that finishes short of its plan is a FAILURE - so `pnpm test:backend:db` (which `ci.yml` runs on every push to `main`) would have been red from the day the evidence-lifecycle migration landed.
- **The fix is the number, not the tests**: `plan(46)` -> `plan(43)`. Nothing was dropped - the file's own header lists five property groups and all of them still have their assertions (recoveries 1-10, funding and pool 11-18, redaction 19-31, the deletion queue 32-36, summaries 37-43). The three extra tests were never written.
- **Why audit all 58 instead of patching one**: the pgTAP runner needs Docker plus the Supabase CLI, which this machine lacks, so the plan count is the only checkable proxy for "the suite is complete". Audited every `supabase/tests/*_test.sql`: the other 57 already agreed with their plans, and they do now too.
- **Reversal:** if a pgTAP version ever tolerates over-planning, restore 46 - but the assertions never change, so 43 is the honest number either way.

## 2026-11-03 — The markdown sweep now runs over ALL 81 tracked `.md` files, scaffold included

- **What the sweep checks** (filed as the standing hygiene rule, not a one-off pass): final newline, no doubled blank line, no trailing whitespace or tabs, table rows with one escaped-pipe-aware cell count per block, no heading-level skips (fence-aware: a `# Web` line inside a report template doesn't count), and every relative link resolving to a tracked path.
- **What got fixed here**: `.claude/commands/persona.md` had a doubled blank line; `.claude/agents/audit/compliance-auditor.md` put a pipe inside a code span in a table row (`grep -rn "fetch(\|https://"`) so naive checkers read a fifth cell — the starting point is now two separate greps, which keeps the same intent and leaves the cell unambiguous. (`2262b83`)
- **What was NOT "fixed" and why**: 63 of the 81 files open with `##` rather than `#`. That is the scaffold's own convention — agent definitions and slash-command bodies are included documents, not standalone ones — so promoting every heading would rewrite 63 files for no reader benefit. Only `docs/` and top-level files carry an h1 title.
- **Reversal:** if the scaffold is ever restyled to h1-rooted files, bump every heading in those 63; the rest of the checks stay as they are.

## 2026-11-03 — The share rule's effect is logged where the money lands, not left to be re-derived

- **The decision**: every `pool_allocations` row now carries the `share_bps` the need line actually applied (default 0 for rows the old algorithm wrote), and `run_pool_allocation` writes it alongside `need_cents` and `grant_cents`. The run still logs the rule version on `pool_runs.settings`; this is the missing per-request half.
- **Why**: the share depends on how often a member's pool requests were PAID, and that window moves every day - an auditor replaying a past run cannot recompute a member's share at that day from today's data. design.md's fairness audit asks for figures that can be re-derived; the version stamp alone does not pin the count.
- **The shape of the fix**: the migration is an `alter table ... add column` plus a `create or replace` of the function whose body differs from the current one in exactly two spots (the candidate table gains the share field; the insert logs it) - verified by diffing against the live body, so the band math, reserve and ordering stay untouched.
- **Reversal:** drop the column and the logging to go back to deriving the share from the count at audit time; nothing else depends on the column, and the grants do not change with or without it.

## 2026-11-03 — The "how often paid" record dates a payout by when it was SENT, not by when it was opened

- **What was wrong**: `pool_requests_paid_3y` filtered on `payouts.created_at`, but the board already counts payouts by `sent_at` ("Payouts are counted by when they were sent"), and a payout row is opened at capture time, which can be months before the fund actually pays the request. Counting by the open date put a waited-for payout outside the three-year window the function's own comment promises - quietly shrinking the member's share under the rule built the same day.
- **The fix is the read, not a new column**: `coalesce(p.sent_at, p.created_at)` - `sent_at` is stamped by the existing trigger when a payout becomes `sent`, and the fallback keeps rows without a stamp (fixtures, older data) dated honestly rather than silently dropped.
- **Why this matters now**: the share rule reads this count, so the same payout decides both "how many runs fell short" on the open books and "how much of the next repair the member carries" - the two must agree on what "paid" means.
- **Reversal:** if the record should date by when money was pledged rather than sent, restore `p.created_at` in the window and drop the coalesce; the share rule keeps working under either date, it just counts a different "paid".

## 2026-11-03 — The share rule is listed on the public transparency page, next to the needs weights

- **A published rule should be readable without reading a table**: the fairness audit asks "which rule priced whom when", the member's card names the version that priced their share, and the only public place that answered was `share_rules` itself - so `/transparency` now lists every version with its step and cap (newest first, percentages spelled by the existing `shareWord`), mirroring how the needs weights are already published.
- **The read is soft like the weights':** if the table refuses, the published months still show and the section explains itself (`shareProblem`), so a refused rule never blanks the books.
- **Only the rule crosses**: the page publishes step and cap, never who was paid how often - the counts stay on the member's own card (`my_share`) and behind the self-only read the schema enforces.
- **Reversal:** if the rule should stay table-only for the auditor, delete `loadShareRules`, the `share` section in `transparency/+page.svelte` and the read in `transparency/+page.ts`; the member's card (`my_share`) and the pool's need line stay either way.

## 2026-11-03 — The member's own share answers on their reliability card: same numbers, no new facts

- **Why the console read exists**: the share rule shrinks the fund's grant to a frequent claimant, and the member had no way to see WHY - the home's reliability record showed counts, not the share. `my_share()` (no arguments, `auth.uid()` inside, authenticated-only) answers the same three numbers the pool reads (`pool_requests_paid_3y`, `member_share_bps`, `share_rule_version`), so the card and the door can never disagree.
- **A no-argument self read, not a parameterised one**: the parameterised read (`member_share_bps`) already refuses other members, but the home's affordance should not offer a place to point at someone else at all - `my_share()` has nothing to point at, the same shape as `my_reliability()`.
- **The home read is soft**: a missing share row means the card says nothing about the rule; it never makes the home fail, because the reliability record itself is the read that must answer. The share line sits inside the reliability card (with the counts that price it) rather than a new section, since design.md keeps the reliability record one replacement-for-a-credit-score card.
- **Reversal:** if the share should stay invisible to members (the grant size then the only clue), delete `my_share`, the loader read and the card lines in `app/+page.svelte`; the rule and the pool's need line stay either way.

## 2026-11-03 — How often a member's pool requests were paid raises their own share, by a published versioned rule

- **design.md's promise built**: "how often a member's pool requests are paid (in the last three years) raises their own share of the next request, the same way a deductible works" - so `share_rules` is a versioned, effective-dated published table (like `needs_formulas` and dues formulas), `member_share_bps` reads the member's own `pool_requests_paid_3y` count times the step capped at the cap, and `run_pool_allocation`'s need line subtracts that share - a frequent claimant gets a smaller grant and pays the rest themselves, never a refusal and never a wait.
- **v1 weights are local stand-ins** (a tenth per paid request, capped at three tenths) pending actuarial review, like every other number on that table; the run records the `share_version` it read in `pool_runs.settings` so the fairness audit can re-derive grants.
- **The count stays self-only**: `member_share_bps` runs `pool_requests_paid_3y`, so an authenticated member may ask only about their own share while the service may ask about anyone - the same rule as the count itself, pinned by a refusal in `paid_share_test`.
- **The TS mirror took an optional shape** (`paid3y` on `FundingRequest`, `share` in `AllocationOptions`) so existing callers and every existing pinned figure stay exactly as they were; a member with no paid history gets the identical grant, so no older `pool_cover_test` or `allocation.test.ts` figure moves.
- **Reversal:** if the share should raise the member's share of the REPAIR (their pledge side) instead of shrinking the grant, move the term out of the allocation into the member-facing figures; deleting the rule entirely is just removing `share_rules`, `member_share_bps` and the need-line term - the pool then grants the same amount to everyone.

## 2026-11-02 — The member area's no-stack ENTRY is e2e-covered: /app must redirect to /signin

- **The redirect was already the rule** (`app/+layout.ts` sends an unconfigured visitor to `signinUrl(url)`); what `e2e/member-entry.spec.ts` pins is the browser-visible consequence, for all seven unparameterised member routes (`/app`, `/app/board`, `/app/cover`, `/app/invite`, `/app/loans`, `/app/requests/new`, `/app/review`), each keeping its own return path in `?next=`: the preview build's member area is never a half-empty shell or a crash through the SPA fallback.
- **Waiting on the notice, not on goto's response**: the redirect is client-side (Kit's router runs the layout's load after hydration), so `page.goto` resolves while the URL is still `/app`; asserting the /signin notice (which only exists after the navigation) makes the test deterministic, and `retries: 0` means it can't be flaked away.
- **Same no-stack rule as the /signin entry**, so both stay in the default suite: neither path touches the stack, only the sign-in flow behind it does.
- **Reversal:** if `/app` should instead render an empty member area with a notice when unconfigured, delete `e2e/member-entry.spec.ts` and change `app/+layout.ts` to stop redirecting; the sign-in entry (`e2e/signin.spec.ts`) stays either way.

## 2026-11-02 — Proof of liability stays the partner's filing step, not a new local column

- **What the roadmap still asks for**: `roadmap.md` 2b and [followups.md](followups.md) name "proof of liability cover" as the last cover term. Rating filings ask an applicant for proof of liability (the report naming the party at fault) before collision cover applies - it is a demand made *before* a claim exists, and a claim that reaches Kinfold has already passed it.
- **Why not a `claims.proved_by` column**: the feed is the partner's, so any local proof field would be a copy of a check we can neither perform nor verify here - a column the partner says they ran, and nothing more. design.md keeps liability with the member's own insurer ("the pool never replaces the cover the law requires"), which is a term on the member's side, not a per-claim claim.
- **What stands in locally**: the request-side analogue is already built - evidence, reviews with written reasons, fraud signals and appeals decide whether a request is credible before money moves. That is where Kinfold's own liability judgement lives.
- **Reversal:** if the state's filing rules turn out to demand the liable party's identity on the claim itself, add a `liability` text column on `public.claims`, require it in `record_claim`, and show it on the member's claims card; the feed contract then has to carry it.

## 2026-11-02 — The cover console shows the filed annual deductible and what this year has used

- **The rule was already enforced in the schema; the member just couldn't see it**: `loadCover` now also reads `annual_deductible_cents` on the filed rates and the member's own `claims` rows (RLS answers with claims on their requests only), and the console names the smallest filed annual next to each rate ("a year at most") plus one sentence on what this insurance year has already used. A member who can't see the annual can't understand why their share rose — the refusal wording would otherwise be the only clue.
- **The year window is restated in TS to match the schema's**: the same calendar year `record_claim` uses for the floor, and a denied claim's paid nothing so it consumes none — both pinned in `data.test.ts` (a 2025 paid claim is out, a denial counts for zero).
- **Used dollars are read, not recomputed from the partner's gross**: the sums go over `paid_cents`, exactly the column the annual floor is computed from, so the console and the door can never disagree about what the deductible has left.
- **Reversal:** if the annual should stay a partner-side term the member never sees, drop the claims read and `deductibleUsedCents` in `loadCover` plus the two notes in `app/cover/+page.svelte`; the schema floor (`annual_deductible_cents`, `set_annual_deductible`, the `record_claim` block) stays either way.

## 2026-11-02 — The shared nav bar's section links are page-root-qualified, not bare fragments

- **What was broken**: the site chrome renders on every prerendered page, but the nav's section ids (`requests`, `board`, ...) exist only on the landing page, so a bare `#requests` on `/transparency` pointed at that page's own missing anchor — a silent dead link. Kit's prerender link check (`prerender_missing_id`) only surfaced it once `/transparency` stopped crashing outright.
- **`/#id` over suppressing the check**: the link's real target is the landing page's section, so it says so; a `handleMissingId` that only warns would hide a broken nav on every page (root `CLAUDE.md`: fix at the source, never silence).
- **Skip link stays a bare fragment**: `#main` exists on every page (the `(site)` layout's `<main id="main">`), so it belongs to the page it is on.
- **Reversal:** if the nav should only be offered on the landing page, delete the absolute `/#id` links in `SiteNav.svelte` and gate the bar in `(site)/+layout.svelte`; either way the fragments keep pointing at the landing page's sections, never at a per-page anchor.

## 2026-11-02 — The annual deductible caps a member's paid-back dollars; the member's share rises once it runs out

- **A filed term, not a rule invented here**: rating law lets a member recover at most the annual deductible in an insurance year, so `annual_deductible_cents` sits on `cover_plans` beside its premium and cap and the partner files it (`set_annual_deductible`, service only) — the seeded value (three claims' worth of that class's cap) is a local stand-in like every other number on that table.
- **The floor is computed, never trusted**: `record_claim` sums the `paid_cents` of that member's claims whose status is `paid` this insurance year (calendar year; a denial pays nothing, and a claim the feed has not confirmed as paid yet has recovered nothing so it consumes none) and refuses a share below `gross - remaining`; the feed's numbers stay the partner's words, and the books can never credit deductible dollars the filed terms would not pay.
- **Rising share, never a refusal**: design.md promises frequent claimants pay more of their own repair but "never wait longer or get refused", so the exhausted claim records with the share raised to the whole loss and pays nothing — the member carries it. Refusing instead would turn insurance into a queue that punishes unlucky people, which is the exact behaviour design.md forbids.
- **`paid_cents` now written by the door**: the previous `record_claim` left that NOT-NOT-NULL column unset, so a feed claim would have failed at insert time (the pgTAP suites run only in CI, so this was latent). The new door writes `paid = gross - share` itself, which is what the row's own check already promised.
- **Reversal:** if the annual deductible should instead be enforced on the partner's side (they simply stop paying claims once it is spent), delete `annual_deductible_cents`, `set_annual_deductible` and the annual-floor block in `20261102580000_annual_deductible.sql` plus `annual_deductible_test.sql`; keep the `paid_cents` write either way, the row's check needs it.

## 2026-11-02 — The signin page's no-stack entry is e2e-covered; the stack-dependent flow is not

- **What the test can honestly pin**: /signin is never prerendered, so `e2e/signin.spec.ts` pins the adapter's `200.html` fallback actually puts the page on the wire (title, heading, hydrate marker) — and that with no key configured the page shows its notice and NO form, instead of a dead form or a crash. That path needs no stack, so it belongs in the default suite.
- **Either wording accepted**: the preview runtime sets `dev` true, so the e2e build shows the dev-worded notice while a production runtime shows the public one; the regex accepts both rather than hard-coding the runtime's devness.
- **Reversal:** if even the no-stack entry should wait for a stack window, delete `apps/web/e2e/signin.spec.ts` and revert the coverage notes in `apps/web/playwright.config.ts` and docs/STACK.md; the stack-dependent flow stays out either way.

## 2026-11-02 — The transparency page reads its load result under `data`, like every other route page

- **Why it was broken**: in Kit v3 a page component's `$props()` is the page context (`{ data, form, params, error }`) — the load result sits under `data`, which is how every other route page already read it. `/transparency` alone destructured the seven load keys straight off the context, so the build-time prerender died (`Cannot read properties of undefined`) and the page would have shipped blank in the SPA fallback too.
- **`data.x` in the template over local aliases**: destructuring into locals trips Svelte's `state_referenced_locally` warning (they'd capture only the initial value if the page ever re-rendered); `data.x` reads the context directly and stays honest. The loader's shape in `+page.ts` and the vitest pins under it didn't move.
- **Reversal:** if the loader should stop being page-context-shaped, re-destructure in `+page.svelte` and drop the `data.` prefixes, or split each section into its own `.svelte` component with its own loader; either way `#lib/transparency/data.ts` and its test pins stay as they are.
- **e2e now covers the public transparency page** (`apps/web/e2e/transparency.spec.ts`): it pins the page renders its three sections and the unconfigured notice instead of crashing, which the e2e build can exercise without a stack because the page is public — the member area stays out of the default suite by the earlier e2e entry.

## 2026-11-02 — The Fund loan console offers the fair-lending self-test and treats the schema's "already recorded" refusal as its marker

- **Only unsecured loans carry the form**: loans secured by the home answer on the credit union's government monitoring form (1002.13), which is service-only, so offering a self-test there would be a form the borrower can never complete. The schema refuses the same thing; the console just doesn't offer it.
- **The console can't know whether the offer already happened**: nothing client-side can read `private.fair_lending` — that is the decision the previous entry locked in — so the form stays available and the schema's "this loan's self-test data is already recorded" refusal, explained in the Fund's words, is the marker that an offer landed.
- **All four disclosures are one acknowledgement in the wrapper**: the schema takes four booleans (the law's four required disclosures); the console asks the borrower to check all four and passes one flag, so the UI can't drift out of sync with what the door needs.
- **Reversal:** if the self-test should not be offered in-app, delete `apps/web/src/routes/app/loans/fund/[id]/FairLendingPanel.svelte`, its import and render in that page, and `offerFundLoanSelfTest`/`fundSelfTestProblem` in `#lib/loans/fund.ts`; the monitoring form is unaffected since it never crosses to clients.

## 2026-11-02 — A partner's charge confirmation captures the pledges AND journals their money in one door

- **Gifts now have a journalled path** (followups item 19 named the gap): money the payment partner confirms for a funded request is money the cooperative put in motion, so it arrives `partner_cash` → `available` — the account the pool allocates from and payouts pay out of. The repair fund is gift-funded, so this is how its money actually arrives; before this, `available` only ever moved out.
- **One door owns both halves**, not the webhook: capture and journal in one transaction, so money is never captured without its ledger entry, and no replay can post the journal alone. The figure journaled is the schema's own pledged sum, never the partner's word; a replay with nothing pledged is refused with that wording rather than journalling zero.
- **Reversal:** if the charge journal should live in the webhook instead (the `dues_captured` shape), delete `20261102570000_charge_journal.sql` and `charge_journal_test.sql`, move the journal into `payments-webhook`'s `charges_confirmed` case with a `capture_contributions(p_request, p_partner_ref)` returning the captured cents, and update `payments_webhook_test.ts`; the `available` account and the seeded codes stay either way.

## 2026-11-02 — The grant report is a public aggregate door, and the transparency page renders it without re-adding

- **Public by design**: design.md says the transparency dashboard IS the grant report — funders and agencies get the same aggregates the public sees — so `grant_report()` is granted to anon, authenticated and service alike. There is no member data in it; grant money is fund-level, so the small-numbers masking the open books need doesn't apply.
- **The page renders, never re-adds**: `loadGrantReport` maps the door's jsonb rows to labels only; the aggregation lives in the schema so a front-end bug can't quietly change what funders see.
- **Reversal:** if the grant report should go back to funders-only PDFs rather than the public dashboard, delete `20261102560000_grant_report.sql`, `grants_report_test.sql`, `loadGrantReport`/`GrantRow` in `#lib/transparency/data.ts`, and the "The grant report" section plus its `grants`/`grantProblem` plumbing in `/transparency`; the `grants` table and pots stay either way.

## 2026-11-02 — Grant money gets labelled pots of its own and never joins `available`

- **Why not `available`**: design.md says grants fund the Fund, mitigation and dues — never the pool's eligibility or its payouts. Pool allocation draws only from `available`, so grant money landing there would let a grant buy a pool grant, which is neither lawful nor designed. Two new fund-level accounts (`grants`, and `federal_grants` for federally funded money per 2 CFR 200's "own pot") keep it out, and the protection fund's non-federal grants land in the `dues` pot, which the premiums door — not the pool — spends.
- **Federal money never enters insured cover**: design.md's payment-order rule says federal money inside the cover turns payouts into federal aid and pushes them behind insurance; the door refuses that combination and the table's check enforces it too.
- **Replays answer instead of adding**: grant money is reported by the partner, so a replayed report with the same `partner_ref` returns the grant row it already made, mirroring the premium and dues doors the ledger already treats this way.
- **Reversal:** if grants should flow into `available` like partner transfers, delete the `grants`/`federal_grants` accounts and the fund check in `20261102550000_grant_funding.sql` (make the door journal into `available`) and drop `grants_test`'s pot assertions; the append-only rows and the "federal money never enters insured cover" rule stay either way.

## 2026-11-02 — Fair-lending demographics live in a private table no client can read, reached by two doors

- **Two routes, one law**: 12 CFR 1002.5 bars asking race, ethnicity or sex, so the only ways in are the law's own exceptions — the government monitoring form (1002.13) for loans secured by the home, collected by the credit union (service only), and the voluntary self-test with its four disclosures (1002.5(b)(1)), offered by the borrower themselves. Nothing else asks, so the schema has no third door.
- **Self-test data is never federally reported**: the loan-level report a federal award pays for (2 CFR 200.337) reads "Do Not Know" for any loan that only has self-test rows. Voluntary answers feed the fairness audit; only monitoring-form answers count as collected.
- **No client can read the rows at all, not even the borrower**: `revoke all … from public, anon, authenticated` with only the service role granted. The borrower's consent is recorded in the audit log (`fair_lending.self_test`) like every PII touch; the answers themselves never enter the trail. Age is deliberately absent — the law may ask it but never weight it against an applicant, so nothing here can feed the needs formula.
- **Reversal:** if the demographics should go back to the credit union's own records rather than Kinfold's, delete `private.fair_lending` and its four doors in `20261102540000_fair_lending.sql` and `fair_lending_test.sql`; the Fund loan report then carries "Do Not Know" everywhere, which is what the CDFI form accepts.

## 2026-11-02 — The Fund loan console gives the borrower sign, pause, resume and restructure forms

- **Why no terms or schedule forms**: the Fund signs at once and its schedule is either set at creation or computed from income — `create_fund_loan` owns it, so the borrower has nothing to negotiate the way family loans do. The console offers exactly the doors whose rules the borrower can act on.
- **The pause preview matches what the schema writes**: the moved dates come from the same `pushBack` the family console uses; the restructure preview uses `fundSplit`, the same even split with the last payment taking the remainder that `apply_fund_loan_restructure` will write — so what you see is what the partner's event will land, and the outstanding figure never changes.
- **Refusals still come from the schema**: each form refuses client-side only to explain before sending; the save path relies on the doors, and the Fund-specific refusal words live in `explainLoanError`.
- **Reversal:** if the Fund loan actions should go back to read-only cards, delete `apps/web/src/routes/app/loans/fund/` (the whole route), the `loadFundLoan` and door wrappers in `#lib/loans/fund.ts`, and the card link in `/app/loans`; the schema doors and `loadFundLoans` stay either way.

## 2026-11-02 — The member's dues card names the published formula that priced their figure

- **Why show the formula at all**: `subscription_formulas` keeps old versions "so every subscription can say which formula priced it", but until now the member saw only their own figure. A dues number with no rule beside it is one of the things a member can most easily misread ("is my dues too high?"), and the fairness audit needs the same rule visible.
- **Published figures only**: the floor, rate and cap come straight off the published version the subscription references — the card never re-prices dues and never shows earnings, only the earnings check it was priced from (already on the card).
- **A missing version reads honestly**: if a subscription references a version that isn't published, the card says so rather than showing the figure as if unpriced.
- **Reversal:** if dues should keep showing bare figures, delete `formulaOf` and the `formula` state in `#lib/dashboard/membership.ts`, the `subscription_formulas` read in `loadHome`, and the card row in `/app`; the dues doors and the schema are untouched either way.

## 2026-11-02 — The transparency page publishes every version of the needs formula, not just the current one

- **Why publish weights at all**: `design.md` says applicants for Fund help are chosen by a *published* needs formula, and the fairness audit has to re-derive any place in the queue. A score nobody can re-derive cannot be defended at the panel, so the weights cross to the public page.
- **Every version stays listed**: `needs_formulas` keeps old rows so a member can ask which formula priced their place; showing only the newest would make past decisions unreadable and unreproducible.
- **Weights only, never inputs**: the inputs that feed a score stay with the member, and the page says so beside the list. The read is public (`using (true)`), so it needs no session, and a refused weights read leaves the published books standing rather than blanking the page.
- **Reversal:** if the weights should go back to being current-version-only (or off the page entirely), delete `loadNeedsFormulas` in `#lib/transparency/data.ts` and the "How members are chosen" section; the formula table, `record_needs` and the fairness audit are untouched either way.

## 2026-11-02 — The loans console shows the Fund's loans in their own section, and reads their money from the schema

- **Their own section, not mixed into "Money you borrowed"**: a family loan has a lender member on the other side, an invitation pair and a written agreement; a Fund loan has none of those — the Fund signed at once and the money reached the payee through the partner's disbursement. Listing both under one heading would read as if a person had lent the money, so the Fund's loans get their own heading and their own cards, with no agreement page.
- **Money figures come through the schema's own doors**: outstanding is read from `fund_loan_outstanding_cents` and each income month's cap from `fund_loan_income_due_cents`, so the console never re-derives money that the schema capped from live income; the only client arithmetic is one unpaid installment's owed amount. If either door is refused the page fails loudly rather than showing loans with no figures.
- **History is shown, not written**: a paused loan states the day its latest pause runs out (the same started_on + months window `private.fund_pause_ends_on` computes, from the append-only pause rows), and an open restructure ask says the lending partner still has to apply it. Both readings keep the card honest that pausing and re-scheduling never change the money owed. The borrower-callable doors stay unwired until the forms exist, and there is no Fund loan detail page — recorded in `docs/followups.md` so the gap stays visible rather than being half-built.
- **Reversal:** if Fund loans should ride in the family loans list instead, delete `apps/web/src/lib/loans/fund.ts` and the `fundList` snippet in the loans page; the money, the doors and the tests are untouched either way.

## 2026-11-02 — Dues money gets its own account so it can never buy a pool grant

- **Dues buy premiums, not grants**: design.md has dues paying premiums (paid in full to the insurer), gifts and grants funding capped repair grants, and dues leftovers going to reserves or back to members. But dues money journalled straight into `available`, the pool's own-money account, so a dues dollar could fund a pool grant — neither lawful nor designed. New fund-level `dues` account: dues money arrives there, premiums move `dues` → `premiums`, and `available` only ever holds money the fund itself holds.
- **Reversal:** if dues money should pool with the fund's own money again, delete the `dues` account and the rewritten `pay_cover_premium` in 20261102530000_dues_account.sql; the ledger checks (balanced journals, no fund mixing) hold either way.

## 2026-11-02 — The original vision is kept on `main` as history, verbatim (`docs/vision.md`)

- **Why keep it at all**: `origin/dev` held only the first write-up — "Low to zero monthly payments and have insurance" — and it is the raw origin of the rules `design.md` now states in researched form. Losing the wording makes the reversals recorded in this ledger unreadable, so it is kept on `main` rather than deleted with the branch.
- **Kept verbatim, marked as history**: spelling and grammar are the original's, fenced as source so nothing in it can be mistaken for current advice, and the header says `design.md` wins where they disagree (the earnings-priced pool, the unqualified "everything is public", the unpriced premiums are all reversed there).
- **Reversal:** if the early wording should stay off `main` (embarrassing, or a confidentiality concern about the founder's notes), delete `docs/vision.md` and the README pointer; the branch itself, and its deletion, are untouched either way.

## 2026-11-02 — A feed claim over the filed caps is refused, never silently truncated

- **A bad feed entry must not bend the books**: the partner's claims feed can carry an amount the filed terms would not pay (wrong plan, wrong class, or a claim above the vehicle's own value). `record_claim` now checks the limit — the filed deductible cap for the member's plan and the vehicle's rating-law class, and the vehicle's value — and raises rather than clamping, so a silent truncation can never invent a paid-in-full claim that isn't lawful.
- **No car cap for requests without a classed covered vehicle**: home repairs and down payments carry no car cap; the cap follows the asset the request names, not a global figure.
- **The cap applied is written onto the audit trail** with each recorded claim, so the trail can be reconciled against the filed rates at review time.
- **Reversal:** if the partner's feed should be trusted absolutely, delete the limit check and its pgTAP `claims_capped_test`; the claims table's own checks (share ≤ gross, paid = gross − share) keep the arithmetic either way.

## 2026-11-02 — The docs state what is built, not what was planned (`docs/backend.md`)

- **Stale claims are bugs in a docs-driven repo**: the edge-function table said "Two are built... the rest are the plan" while 16 of 17 `functions/` were built and deno-tested, and the "Not built yet" section still named pause, restructure and needs-edge-case work that landed. Rewrote the count, added the five missing built rows (each naming its pgTAP and `deno test` pins), and restated the unbuilt list to what is actually open: `close-account`, the phone app, and the partner-gated stages.
- **Reversal:** if the table should track only the partner stand-ins, drop the per-row pins and keep the counts in [roadmap.md](roadmap.md); the functions themselves are unchanged.

## 2026-11-02 — The ops console reads the tail of the trail, not its detail (`review_audit_tail`)

- **Decisions must be reviewable**: the roadmap promises the operations console shows the audit trail, and `private.audit_log` had no door at all. New door answers recent actions (action, target, target id, time), newest first, capped at 100 — reviewers and admins only, and the read itself is logged, so trail-reading is itself auditable.
- **The raw `detail` jsonb never crosses** (it carries amounts, vendor references and PII-adjacent figures), and neither does the acting member's id: the console sees THAT decisions happened; the reviews/appeals/claims tables say what they were and who wrote them under their own policies.
- **Members get nothing**: the door re-checks role and the grant excludes anon, so a member's client can't pull the trail even by guessing the function name.
- **Reversal:** if the trail should stay entirely inside the service, delete the door and its pgTAP `audit_trail_test`; nothing else reads these rows, and the trail-writing side is unchanged.

## 2026-11-02 — The member's cover console offers only the two doors a member truly owns

- **The dues/premium schema had no member surface**: filed rates, classes and plan choices landed in SQL (pgTAP-pinned) but nothing let a member see or change what they own, so premiums read as an invisible deduction. A new route `/app/cover` reads their own vehicles, the filed rates that apply, and the annual premium figure, and offers exactly two writes: `set_my_plan` (which filed set applies) and `set_vehicle_class` (the rating-law class on their own vehicle).
- **Nothing else is writable from the member side**: filed rates are the partner insurer's and are written service-only; the console never restates or accepts them, and it never calls dues money a premium (the member's side keeps the dues word) — the paid-in-full premium figure is a read, not a lever.
- **Reachable from everywhere**: the member nav gains `Cover`, so `/app/cover` sits with Home, Board, Loans and Invites rather than being a hidden page.
- **Class before premium**: an unclassed vehicle takes no premium money (pgTAP-pinned), so the console shows the class as the missing step rather than inventing a default class — a default would silently price a vehicle against the member's own knowledge of it.
- **Reversal:** if the class and the plan should come only from onboarding, delete `/app/cover` (route ts/svelte, `lib/cover/*`) and keep the doors; nothing in the schema or the ledger depends on the console existing, and no new SQL was added for it.

## 2026-11-02 — The console reads WHAT the checks found, never HOW they match (`review_fraud_signals`)

- **Fraud standing was invisible to the people who act on it**: `private.fraud_signals` decides scoring (`in_review` on a high-severity finding) but nothing let a reviewer read it — the console promised fraud signals with no door behind the promise. New door: kind + severity, high first, resolved findings gone.
- **The match `detail` stays private** (photo hashes, cross-reference ids): a reviewer sees THAT a pattern was found, not HOW the checks matched, so the checks' keying can't be reverse-engineered from the console. The read answers through the function, not a table policy — `private.fraud_signals` keeps its no-raw-reads default and only the door can be called.
- **Every look is on the trail** (`fraud_signals.read`, count only): fraud standing is PII-adjacent, and this repo audit-logs every privileged read of member-adjacent state.
- **A console refusal is not a broken queue**: the read treats 42501 as "not for this role" (panel members keep their queue), while any other failure still reaches the console loudly.
- **Reversal:** if findings should stay entirely inside scoring, delete the door and the `findings` leg (`queries.ts`, `queue.ts`, the card block); the triggers that move statuses never consult these fields, and the web layers carry everything else.

## 2026-11-02 — A pending identity check is named on the home, not left implicit

- **Silence is the worst failure mode for a new member**: signing up leaves a member `pending_verification`, and every read the member area does comes back empty — an empty home reads as "there is nothing here", not as "you cannot post yet". The home now carries an identity-check block (status via `identityWord`, plus what passing unlocks) while the check is outstanding, so the reason is on the page the member is already looking at.
- **Status comes from the member's own row, read through normal RLS** (`members.select('status, joined_at').eq('id', uid)`): the account's state is the member's own fact, and the schema already lets a member read their own row — no new read door was opened.
- **Nothing is claimed about the vendor**: the block says Kinfold keeps only the vendor's reference and the outcome, never the documents, matching 1b; it does not invent a retry button the schema has no door for.
- **Reversal:** if the check's state should belong only to a dedicated onboarding page, delete the block and the `identity` field (with its two loader arguments); the tests cover both halves and nothing in the schema depends on them.

## 2026-11-02 — The phone app (roadmap 1a) stays unbuilt while the toolchain is missing

- **Decision:** `apps/mobile` is not scaffolded. The Flutter/Dart toolchain isn't on this machine, so anything written would be code nothing can compile, check or test — the repo rule ships tests with code, and an untestable shell would quietly claim more than it does. The web member area carries every affordance built so far, so nothing built elsewhere is blocked on it.
- **Reversal:** the moment `flutter --version` answers, 1a becomes a normal leg (sign-up, Supabase Auth, profile, Flutter tests) and its claim belongs on roadmap row 1a, not here.

## 2026-11-02 — Car-cover requests point at the public help beside them (`CoverHelpPanel`)

- **Kinfold stays a holder of member shares, never a writer of others' policies**: the web request page for a car gap now names the programmes that sit beside that gap — state low-cost auto insurance where it exists, and FEMA/SBA/USDA disaster-repair help — so a member whose own insurer won't take the loss has somewhere real to go (design.md "Pointing members to public help"), rather than an unhelped "no, ask your people" wall.
- **Names only, never money**: every line says the programme's own terms move that money outside the pool, so no read of this page can be taken as Kinfold administering a federal or state programme — 2e's loans still wait on the partners.
- **Reversal:** if the operator wants the pointer kept off the member console (say, once the state programmes are verified against current notices per the followup list), delete the panel and its import; nothing in the schema or a test depends on the copy.

## 2026-11-02 — The written agreement is read where the pair reads their loan (`agreement_text` on the loan page)

- **Paperwork must be readable where the deal is discussed**: the loans console now shows the agreement the servicing wrote — amount, schedule, pause allowance, lien, default plan — beside the terms it was written from, and says "not written yet" while a loan is unsigned. A member who has to answer a tax accountant, or a repair shop's credit question, reads the same record the schema wrote.
- **Read through the seam, never a hand-edit of generated types**: `family_loans` predates the newest migrations, so the read is `fromNew(db,'family_loans').select('agreement_text, agreement_finalized_at')`; `database.types.ts` stays untouched until the stack regenerates it (see the earlier ledger entry on seams).
- **The page quotes it, never restates it**: the copy under it says the text is history and to cite it as it stands, so nobody reads a paraphrase as the agreement.
- **Reversal:** if the written text should stay off the member console (only in a downloadable statement), delete the block and the two loader fields; the schema, the servicing job and every test are untouched.

## 2026-11-02 — A signed loan's agreement gets written down (`finalize_loan_agreement`)

- **Paperwork is a product, not an afterthought** (design.md:149): because Kinfold documents every loan properly, an unpaid family loan can qualify as a bad-debt tax deduction for the lender, which an informal handshake loan usually can't. So once both sides have signed, the loan-servicing event writes the agreement in plain words on the loan — amount, schedule as set, pause allowance, lien/IRS rate, default plan — and the job sweeps exactly the signed loans that have none yet.
- **The written text is history**: written once, never edited, never re-priced; a replay is a no-op, so the loan-servicing job can run daily without fear of rewriting an agreement someone cited to an accountant.
- **Only the event writes agreements** (service-role only): a member can't author their own agreement text after the fact, because the record of what was agreed has to come from the signing, not from whoever notices later. **Reversal:** letting the borrower or lender edit the text would let a loan's paperwork claim a different deal than the one e-signed; the ladder keeps the schema as the writer.

## 2026-11-02 — A family loan's schedule changes only by agreement ('loan_restructures')

- **Ladder step 3 for family loans** (design.md:137, "a new schedule both sides sign"): either side stages a restructure (smaller payments over a longer term, or a new start date) on their collecting loan; the *other* side signs it, and only on that signing do the unpaid installments re-spread — on the loan's payment day, like every other schedule (`set_loan_schedule`), so the loan keeps its payday rhythm.
- **A staged ask alone moves no money** — until both sides have signed, the schedule on the books is still the old one. One pending ask per loan; a second ask is refused while one waits.
- **The re-spread covers exactly the money still owed**: installments already paid keep their dates and amounts, so `loan_outstanding_cents` never changes across a restructure. **Reversal:** re-spreading paid money would rewrite repayment history (and the reliability record that reads it); the ladder keeps paid installments as facts.

## 2026-11-02 — Beyond the pause allowance a Fund loan borrower asks the lending Fund to restructure (`restructure_fund_loan`)

- **The borrower stages a restructure on their own collecting monthly fund loan** — smaller payments over a longer term or a new start date (design.md:137 ladder step 3). The Fund has already signed the agreement (it is the lender), so the ask only waits for the lending partner's servicing event (`apply_fund_loan_restructure`), which re-spreads **only the unpaid installments** over the new dates.
- **A restructure never changes what's outstanding** — money already returned keeps its date and amount, so the ladder can only repay the same money over different dates, never less. **Reversal:** re-spreading paid installments too would rewrite repayment history; the ladder re-plans the future, not the past.
- **One ask at a time**: while a restructure is un-applied a second ask is refused, and income schedules have nothing to reschedule (they are computed from income, not scheduled).
- **A paused loan can still ask to restructure** — the ladder goes pause, then restructure; pausing never blocks the bigger agreement step.

## 2026-11-02 — A Fund loan borrower pauses and resumes by agreement (`pause_fund_loan`)

- **The borrower pauses their own fund loan** within the loan's allowance (default 3 months a year, same ladder as family loans, design.md:169); the pause records an append-only `fund_loan_pauses` row with its reason, pushes unpaid installments back, and leaves what's owed unchanged — pausing buys back dates, not money.
- **Beyond the allowance the ask becomes a restructure** the lending partner owns: the schema refuses the pause with the allowance numbers, never a silent yes. **Reversal:** auto-approving pauses past the allowance would grow the borrower's grace period with no agreement recorded; the ladder stays finite.
- **A paused fund loan still takes payments** — a pause is not a freeze on money moving, only on the dates; the partner may keep disbursing while the borrower catches up.
- **The borrower may resume early at any time**; the loan-servicing service (`resume_ended_fund_pauses`) may only flip loans whose pause ran out, and the schema — not the job — decides which loans those are.
- **Only the borrower reads their pauses** (RLS): pauses carry reasons, and reasons stay between the loan's own two sides.

## 2026-11-02 — Reviewers answer needs edge cases beside the ranking (`needs_reviews`)

- **A reviewer from another state answers an edge case** next to the Fund's published needs ranking (3b's "panel review for edge cases"): the answer names the formula version it was made against and carries a written reason the applicant reads without the reviewer's name. Only an applicant the Fund has ranked can be answered.
- **The answer never edits the score** — `needs_reviews` is append-only history beside `needs_records`, so the published ranking stays exactly what the formula said and the judgement sits next to it, auditable at annual fairness time. **Reversal:** letting an answer overwrite a score would quietly rewrite the published formula's output; the ladder keeps both.
- **One answer per reviewer per formula version**; the console's `NeedsForm` never shows a reviewer's own identity, and RLS answers decisions only for requests the viewer may review.

## 2026-11-02 — Mortgage gaps point at public help; Kinfold never becomes a counselor (`PublicHelpPanel`)

- **A mortgage-gap request page carries a public-help panel**: HUD-approved housing counselors (you go to theirs, not to Kinfold — design.md says Kinfold partners with a certified agency rather than becoming one) for forbearance and loan modification, plus state and federal repair help. **Public money never joins the Fund** — the copy says so, matching 24 CFR 92.503: programme rules follow the money forever.
- **The Fund's own bridging loan stays gated on pilot lending-licence review** (12 CFR 1026.43: federal ability-to-repay rules apply unless the lender is a certified CDFI or a 501(c)(3) lending at or below 80% AMI). **Reversal:** letting Kinfold itself counsel borrowers would put a lending licence on the wrong actor; a referral keeps the certification with the partner who holds it.

## 2026-11-02 — The Fund ranks its applicants by a published needs formula, and the ranking can be re-derived (`needs_formula`)

- **Home Fund applicants are ranked by need, readiness and reliability** (design.md: the same evidence score as every request plus need, readiness and reliability — rent paid on time, family loan repayments). Each component is a banded 0–100 points figure, and the weights live in a published, versioned table (`needs_formulas`) so the formula can move with the Fund's fee economics and be audited annually. Ranking waits for a scored request and only ever touches Home Fund kinds; car requests stay ranked by the pool bands.
- **Every applicant row logs its formula version and an inputs hash**, so the annual fairness audit can re-derive a published score rather than argue with it; rows are append-only, so a formula change never rewrites an applicant's past ranking. Hardship details never enter the row — only banded points, matching the rule that hardship details stay private.
- **Panel review stays the edge-case channel** (design.md): the reviewer and panel console already decide with written reasons and appeal; a needs-edge-case affordance is a console task, not a new rule. **Reversal:** an unlogged, single-weighted score would be unfalsifiable at audit, and fair-lending law asks that any ranking formula be published and bias-auditable.

## 2026-11-02 — The dues screen names its earnings check (`income_verifications` on the home)

- **The membership block now shows which earnings check priced dues** (bank link / tax return / self-attestation, verified on, and whether it is still live until its expiry), so a member can see that an expired check needs redoing rather than silently pricing off old income. No check yet is honest ("No earnings check yet"), never a $0 income. **Reversal:** hiding the method would make dues look like a flat fee when the whole design says they track verified earnings.

## 2026-11-02 — The Fund lends to people with less cushion (`fund_loans`, pgTAP `fund_loans_test`)

- **A fund loan's lender is the Fund itself**, so the Fund's agreement signs at once when the partner opens it (there is no lender member to wait for), and the borrower signs their own side before money moves. **Income-based schedules read the member's live income every month**: the schema caps each month's payment at the recorded share of verified income, so payments shrink by themselves when income does — no silent renegotiation. Disbursement and payments are only ever the partner's statements (`activate_fund_loan`, `record_fund_loan_payment`, service only; webhook events `fund_loan_disbursed`/`fund_loan_paid`), which also answers the open question of how a loan with no request ever becomes `active`. **Reversal:** fixing income schedules by rewriting the schedule on income change (as income-based dues already re-price) would let a falling income quietly *raise* future payments' share; capping the payment at income makes the money moving track the cushion, which is the whole point of lending to people with less of it.

## 2026-11-02 — Premiums are paid out of dues money, into a ledger account of their own (`premium_dues`, pgTAP `premium_dues_test`)

- **The cooperative pays a member's cover premiums from dues**, never on the member's side and never as insurance-agency commission (anti-rebating law). The filed `cover_plans` rates price the member's classed covered vehicles; `pay_cover_premium` (service only) moves that money out of the fund's dues money into a `premiums` account, journaling both sides, and refuses when dues money doesn't actually cover them — premiums are paid, never minted. Two members with very different incomes pay the same premium for the same vehicle class, which the test pins directly.
- **Premium money is money the fund has committed to cover**, kept out of the fund's `available` balance so premiums and pool money never double-count each other; it is still the partners' money and stays in ledger accounts throughout.
- **Unclassed vehicles take no premium**, an honest stand-in until the member states the class (the vehicle's rating-law class is a person's statement, not something to guess). **Reversal:** treating premiums as dues themselves (one earnings-based figure) would price insurance by earnings, which rating law forbids.

## 2026-11-02 — Big money waits for a pair of eyes (`inspections`, pgTAP `in_person_inspection_test`)

- **A large request can't move money until someone has actually looked**: requests at or above their fund's `inspection_min_cents` line in `fund_settings` are refused on any change toward `funded` or `paid` unless a recorded inspection says `clear`. The visit itself is the partner's statement (service-only `record_inspection`, append-only, replay-keyed by `inspector_ref`) — the database never decides what the shop looked like, only that nothing large may skip the visit. **Reversal:** letting large requests fund on automated scores alone would let a well-fabricated big claim through unexamined, which is exactly what the pool is for.

## 2026-11-02 — Cover comes in filed plans, priced by risk not earnings (`cover_plans`, pgTAP `cover_plans_test`)

- **The partner insurer's filed group rate lives in the data**: one premium and cap per vehicle CLASS and PLAN (Basic, Standard), with the schema refusing any write that would price Standard at or below Basic inside a class (more premium must buy at least as much cap). A member chooses their plan (`cover_choices`, `set_my_plan`) but can never write a filed rate — only the service files, and each change leaves a history row and an audit trail. **Reversal:** a single global cap (the old `fund_settings.max_request_cents` alone) can't express class-based rates without turning earnings into a cap, which rating law forbids.

## 2026-11-02 — Subrogation money is recorded verified in one step (`record_partner_recovery`)

- **When another driver is at fault, the at-fault party's insurer should pay** (design.md: Kinfold's cover must not subsidise other insurers). The partner insurer reports the money that moved; the schema records it **already verified, in one write** — a separate `verify_recovery` step could leave a half-verified row a retry would double-count. Retry-safe by the partner's reference. Money moved between insurers, so it never joins Kinfold's ledger; the pledge caps and pool needs subtract it. **Reversal:** letting members write subrogation money themselves would let a member claim money no insurer moved.

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
