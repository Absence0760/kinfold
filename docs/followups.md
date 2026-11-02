# Follow-ups

Open items that aren't part of a roadmap stage yet. Each says what's wrong, the fix, and when to do it. Tick an item off by deleting it in the change that fixes it. Stage work lives in [roadmap.md](roadmap.md).

Last updated 2026-11-02.

## Do next

- [ ] **Dependabot PR #3** bumps 13 GitHub Actions and wasn't auto-merged, so at least one bump is probably a major version. It also edits `dependabot-lockfile.yml`, now deleted (`f080e95`), so it conflicts until Dependabot rebases it. **Fix:** have Dependabot rebase, review the major bumps against our workflows, then merge or close. **When:** next session.
- [ ] **Code-scanning fixes to send upstream** to the `templates` repo's `base` branch: drop `dependabot-lockfile.yml` for single-workspace projects (CodeQL always flags its PR-head checkout), the `/audit/deps` rewrite, and the `SECURITY.md` private-reporting link in place of the placeholder email. **When:** next templates session.
- [ ] **One Scorecard vulnerability can't be fixed here:** `deepmerge` (GHSA-gcqx-w48m-w2h4, low) has no patched release and `@sveltejs/vite-plugin-svelte` still depends on it, at build time only. **Fix:** bump vite-plugin-svelte once it drops or patches deepmerge. **When:** on the next Dependabot bump of it.
- [ ] **`origin/dev` branch** holds only the original project-insurance vision README (`c17fa00`). Its ideas are in `design.md`, but the original wording isn't on `main`. **Fix:** decide whether to keep it verbatim as `docs/vision.md` and delete the branch, or just delete the branch. **When:** operator's call.

## Backend gaps

- [ ] **Family loans created with no request still never become `active`** (only a request moving to `paid` activates signed loans). Landed 2026-11-02 for Home Fund loans: `fund_loans` activate through the service-only `activate_fund_loan` from the payments webhook's `fund_loan_disbursed` event. **Fix:** give family loans the same disbursement door once a lender partner exists. **When:** with lender partners, Stage 3.

- [ ] **One earnings-funded pool paying by band.** Landed 2026-11-02 so far: insured cover stacks before pledges, and a claims record fed by the partner exists (pgTAP). The schema still models one earnings-funded pool paying by band: `design.md` splits car help into insured deductible cover (the partner insurer pays claims in full; Kinfold records them), a gift-funded repair fund (the only thing `run_pool_allocation` should allocate), and 0% repair loans. Today the `protection` fund's money comes from subscriptions. **Remaining:** fund the `protection` allocation from gifts and grants only, and rename `subscriptions` to dues; with pgTAP and the web `allocation.ts` reference updated together. **When:** Stage 2, steps 2b to 2d.
- [ ] **Cover terms still partly missing.** Landed 2026-11-02: Basic and Standard plans, one filed premium and cap per vehicle class and plan (`cover_plans`, history-trailed), and a member's own plan choice (`cover_choices` + `set_my_plan`, pgTAP `cover_plans_test`). Also landed 2026-11-02: covered vehicles carry their rating-law class, and premiums are paid from dues money into a `premiums` ledger account of their own (`cover_premium_cents`, `pay_cover_premium`, pgTAP `premium_dues_test`, `pay-premiums` cron). Still absent: a cap by vehicle value, a yearly per-member cap, a member share rising with claims, and proof of liability cover. **Fix:** add them with the partner's filed terms. **When:** Stage 2, steps 2a and 2b.
- [ ] **Fair-lending demographics aren't stored.** The CDFI report and the bias audits need race, ethnicity and sex (age may be asked but never weighted against an applicant), and the schema holds none. **Fix:** an optional table in the `private` schema, unreadable by the scorer, reviewers and panel, filled from the government monitoring form on home-purchase and refinance loans (Reg B 1002.13) or a voluntary self-test with its four disclosures (1002.5(b)(1)). Needs `/safe-migration` and compliance review. The pool's audit is an insurance-law question; it estimates race from surname and geography (BISG) instead of asking. **When:** before the first Home Fund application (Stage 3).

## Member area gaps


Found while building the web member area (`/app`, `/app/board`, `/app/review`, `/app/requests`, `/app/invite`, `/app/loans`) on 2026-10-31. Most need a migration through `/safe-migration`; the web app explains each gap to the member rather than faking it.


- [x] **Evidence redaction now runs.** The `redact-evidence` function sets `redacted_path` and `auto_done`, and checks the stored file exists and its SHA-256 matches the row before redacting; the seed now carries one `auto_done` row (b1) so the member's confirm-redaction step exercises locally. **When:** Stage 1, step 1c.
- [x] **No prepayment path**, though the agreement and `design.md` promise members can repay early. Landed 2026-11-02: the payment partner's `loan_repaid` webhook event calls the guarded `record_loan_payment`, which never looks at due dates — an early repayment is collected exactly like an on-date one, and the reliability record counts it honoured (`installments_paid_on_time` asks only `paid_on <= due_on`, so a prepayment is never a penalty). Pinned by the payments-webhook deno tests.

## Funding and structure

- [ ] **Re-check each programme before applying.** The figures in `design.md` "Public and grant funding" were checked on 2026-10-30 (CDFI Fund FY2026 $324M with no FY2026 notice yet; TA $10,000 to $150,000 in FY2025; FHLB AHP cap $32,837 for 2026; the FY2026 USDA cooperative development round closed in July 2026). The CDFI Fund's certification comment period closes 2026-11-30, so check the final rules after it. **When:** at each application, against that programme's current notice.
- [ ] **Counsel list from the funding research** (`reviews/legal-*.md`, git-ignored): a tax-exempt organisations attorney (Home Fund 501(c)(3), Form 1023, the services agreement), state securities counsel (community investment notes), insurance-regulatory counsel for the group car policy (whether the cooperative paying members' premiums is a rebate, the group definition, the Vermont filing; ideally the regulator's written view), consumer-finance counsel in the launch state (lending licence for the Fund, ability-to-repay on bridge loans, RESPA review of anything a mortgage lender pays), insurance-regulatory counsel (the partner's policy wording, disaster payment order), disaster-recovery counsel (HUD duplication-of-benefits treatment of 0% family loans), and a cooperative-law attorney. **When:** with the Stage 0 counsel engagement.
- [ ] **Re-check the insurance sandbox list.** Vermont's sandbox (8 V.S.A. § 15a) was repealed on 1 July 2025 ([Vermont statutes](https://legislature.vermont.gov/statutes/section/08/001/00015a)), so `design.md` no longer counts it as a reason to launch there. Kentucky, West Virginia, North Carolina and South Dakota were listed from the same research and haven't been re-checked. **Fix:** confirm each is still accepting applicants and update "What's still unsolved" and "Launch states" in `design.md`. **When:** with the insurance-regulatory counsel engagement, before the launch state is chosen.

## Decisions waiting on the operator

- [ ] **Approve the redesigned car cover** (`feasibility.md`, "Community car pool"): earnings-based dues paying a group deductible policy, a gift-funded repair fund and 0% repair loans, in place of one earnings-priced pool. `design.md`, `roadmap.md` and the preview site's copy already describe it; reverse them if you disagree.

- [ ] **Turn on private vulnerability reporting and Dependabot alerts.** `SECURITY.md` now points reporters at GitHub's private advisory form, which is off; Dependabot alerts are off too. Both are repo settings: `gh api -X PUT repos/Absence0760/kinfold/private-vulnerability-reporting` and `gh api -X PUT repos/Absence0760/kinfold/vulnerability-alerts`.
- [ ] **OpenSSF Best Practices badge** (Scorecard's CII check) needs the operator to sign up at bestpractices.dev and add the badge to `README.md`.
- [ ] **PR review and branch protection on `main`** are off by choice while pre-launch (`CLAUDE.md`). Switch them back on before Stage 1 has real members, or as soon as a second developer starts pushing. While protection is off, `dependabot-auto-merge.yml` can merge minor and patch bumps without waiting for CI.
- [ ] **The "Hearth" Claude Doc** (the first design write-up, made before the rename) is stale: old name, no request flow, no business-model review. Update it from `design.md`, or delete it.
- [ ] **Numbers needing actuarial review:** subscription formula v1 (floor $1,500/month take-home, 1%, $60 cap), pool minimum score 70, 10-point bands, 20% reserve, 60/90-day waiting periods, cover caps for $0 subscribers.
