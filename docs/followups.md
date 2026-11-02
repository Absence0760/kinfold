# Follow-ups

Open items that aren't part of a roadmap stage yet. Each says what's wrong, the fix, and when to do it. Tick an item off by deleting it in the change that fixes it. Stage work lives in [roadmap.md](roadmap.md).

Last updated 2026-10-31.

## Do next

- [ ] **Dependabot PR #3** bumps 13 GitHub Actions and wasn't auto-merged, so at least one bump is probably a major version. It also edits `dependabot-lockfile.yml`, now deleted (`f080e95`), so it conflicts until Dependabot rebases it. **Fix:** have Dependabot rebase, review the major bumps against our workflows, then merge or close. **When:** next session.
- [ ] **Code-scanning fixes to send upstream** to the `templates` repo's `base` branch: drop `dependabot-lockfile.yml` for single-workspace projects (CodeQL always flags its PR-head checkout), the `/audit/deps` rewrite, and the `SECURITY.md` private-reporting link in place of the placeholder email. **When:** next templates session.
- [ ] **One Scorecard vulnerability can't be fixed here:** `deepmerge` (GHSA-gcqx-w48m-w2h4, low) has no patched release and `@sveltejs/vite-plugin-svelte` still depends on it, at build time only. **Fix:** bump vite-plugin-svelte once it drops or patches deepmerge. **When:** on the next Dependabot bump of it.
- [ ] **`origin/dev` branch** holds only the original project-insurance vision README (`c17fa00`). Its ideas are in `design.md`, but the original wording isn't on `main`. **Fix:** decide whether to keep it verbatim as `docs/vision.md` and delete the branch, or just delete the branch. **When:** operator's call.

## Backend gaps

- [ ] **Loans without a request never become `active`.** Only a request moving to `paid` activates its signed loans, so a loan created directly (future Home Fund `fund_loans`) stays `signed`, can't be forgiven or paused, and doesn't show missed installments. **Fix:** activate on disbursement from the payments webhook (a service-only `activate_loan(loan)` once the partner confirms the money moved), or from the `fund_loans` disbursement path. **When:** Stage 3, with `fund_loans`.

- [ ] **The schema still models one earnings-funded pool paying by band.** `design.md` now splits car help into insured deductible cover (the partner insurer pays claims in full; Kinfold records them), a gift-funded repair fund (the only thing `run_pool_allocation` should allocate), and 0% repair loans. Today the `protection` fund's money comes from subscriptions, and `run_pool_allocation` computes need as amount minus what people pledged. **Fix:** fund the `protection` allocation from gifts and grants only, make it stack after insured cover (need = amount minus cover paid, before pledges), add a claims record for insured claims fed by the partner, and rename `subscriptions` to dues; with pgTAP and the web `allocation.ts` reference updated together. **When:** Stage 2, steps 2b to 2d.
- [ ] **Cover terms the design needs aren't in the schema.** `fund_settings` has only a flat per-request cap: no cap by vehicle value, no yearly per-member cap, no Basic and Standard plans, no member share rising with claims, no per-vehicle premium, no proof of liability cover. **Fix:** add them with the partner's filed terms. **When:** Stage 2, steps 2a and 2b.
- [ ] **Fair-lending demographics aren't stored.** The CDFI report and the bias audits need race, ethnicity and sex (age may be asked but never weighted against an applicant), and the schema holds none. **Fix:** an optional table in the `private` schema, unreadable by the scorer, reviewers and panel, filled from the government monitoring form on home-purchase and refinance loans (Reg B 1002.13) or a voluntary self-test with its four disclosures (1002.5(b)(1)). Needs `/safe-migration` and compliance review. The pool's audit is an insurance-law question; it estimates race from surname and geography (BISG) instead of asking. **When:** before the first Home Fund application (Stage 3).

## Member area gaps

Found while building the web member area (`/app`, `/app/board`, `/app/review`, `/app/requests`, `/app/invite`, `/app/loans`) on 2026-10-31. Most need a migration through `/safe-migration`; the web app explains each gap to the member rather than faking it.


- [ ] **Evidence redaction isn't running.** New uploads stay `pending`, and `submit_request` refuses them, so a request made in the web app can't be submitted. **Fix:** the `redact-evidence` edge function (sets `redacted_path`, `auto_done`), which must also check that the stored file exists and its SHA-256 matches the row before redacting; seed one `auto_done` row so the member's confirm-redaction step can be exercised. **When:** Stage 1, step 1c.
- [ ] **No prepayment path**, though the agreement and `design.md` promise members can repay early. **Fix:** an extra-payment function through the payment partner. **When:** Stage 1, step 1f/1g with the partner.

## Funding and structure

- [ ] **Re-check each programme before applying.** The figures in `design.md` "Public and grant funding" were checked on 2026-10-30 (CDFI Fund FY2026 $324M with no FY2026 notice yet; TA $10,000 to $150,000 in FY2025; FHLB AHP cap $32,837 for 2026; the FY2026 USDA cooperative development round closed in July 2026). The CDFI Fund's certification comment period closes 2026-11-30, so check the final rules after it. **When:** at each application, against that programme's current notice.
- [ ] **Counsel list from the funding research** (`reviews/legal-*.md`, git-ignored): a tax-exempt organisations attorney (Home Fund 501(c)(3), Form 1023, the services agreement), state securities counsel (community investment notes), insurance-regulatory counsel for the group car policy (whether the cooperative paying members' premiums is a rebate, the group definition, the Vermont filing; ideally the regulator's written view), consumer-finance counsel in the launch state (lending licence for the Fund, ability-to-repay on bridge loans, RESPA review of anything a mortgage lender pays), insurance-regulatory counsel (the partner's policy wording, disaster payment order), disaster-recovery counsel (HUD duplication-of-benefits treatment of 0% family loans), and a cooperative-law attorney. **When:** with the Stage 0 counsel engagement.
- [ ] **Re-check the insurance sandbox list.** Vermont's sandbox (8 V.S.A. § 15a) was repealed on 1 July 2025 ([Vermont statutes](https://legislature.vermont.gov/statutes/section/08/001/00015a)), so `design.md` no longer counts it as a reason to launch there. Kentucky, West Virginia, North Carolina and South Dakota were listed from the same research and haven't been re-checked. **Fix:** confirm each is still accepting applicants and update "What's still unsolved" and "Launch states" in `design.md`. **When:** with the insurance-regulatory counsel engagement, before the launch state is chosen.

## Decisions waiting on the operator

- [ ] **Approve the redesigned car cover** (`feasibility.md`, "Community car pool"): earnings-based dues paying a group deductible policy, a gift-funded repair fund and 0% repair loans, in place of one earnings-priced pool. `design.md`, `roadmap.md` and the preview site's copy already describe it; reverse them if you disagree.

- [ ] **Turn on private vulnerability reporting and Dependabot alerts.** `SECURITY.md` now points reporters at GitHub's private advisory form, which is off; Dependabot alerts are off too. Both are repo settings: `gh api -X PUT repos/Absence0760/kinfold/private-vulnerability-reporting` and `gh api -X PUT repos/Absence0760/kinfold/vulnerability-alerts`.
- [ ] **OpenSSF Best Practices badge** (Scorecard's CII check) needs the operator to sign up at bestpractices.dev and add the badge to `README.md`.
- [ ] **Rename "legitimacy score" to "evidence score"** in the app and site (recommended in `design.md`, "Business model review"). The schema already says `score` neutrally; only copy changes.
- [ ] **PR review and branch protection on `main`** are off by choice while pre-launch (`CLAUDE.md`). Switch them back on before Stage 1 has real members, or as soon as a second developer starts pushing. While protection is off, `dependabot-auto-merge.yml` can merge minor and patch bumps without waiting for CI.
- [ ] **The "Hearth" Claude Doc** (the first design write-up, made before the rename) is stale: old name, no request flow, no business-model review. Update it from `design.md`, or delete it.
- [ ] **Numbers needing actuarial review:** subscription formula v1 (floor $1,500/month take-home, 1%, $60 cap), pool minimum score 70, 10-point bands, 20% reserve, 60/90-day waiting periods, cover caps for $0 subscribers.
