# Follow-ups

Open items that aren't part of a roadmap stage yet. Each says what's wrong, the fix, and when to do it. Tick an item off by deleting it in the change that fixes it. Stage work lives in [roadmap.md](roadmap.md).

Last updated 2026-10-30, at `ca358dd`.

## Do next

- [ ] **No CI runs the tests.** GitHub Actions only runs security workflows (gitleaks, CodeQL, Scorecard). `pnpm check`, the web Vitest suite, the root scripts guard and the 377 pgTAP assertions have only been run locally, although roadmap Stage 0 says CI runs them on every push. **Fix:** add `.github/workflows/ci.yml` on push to `main`. It should run `pnpm install`, `pnpm check`, `pnpm test:web`, `pnpm test:scripts`, then start Supabase with `supabase/setup-cli` (`supabase start` in `apps/backend`), then `pnpm test:backend:db`. Pin action SHAs like the other workflows. **When:** first thing next session.
- [ ] **Dependabot PR #3** bumps 13 GitHub Actions and wasn't auto-merged, so at least one bump is probably a major version. **Fix:** review the major bumps against our workflows, then merge or close. **When:** next session.
- [ ] **`origin/dev` branch** holds only the original project-insurance vision README (`c17fa00`). Its ideas are in `design.md`, but the original wording isn't on `main`. **Fix:** decide whether to keep it verbatim as `docs/vision.md` and delete the branch, or just delete the branch. **When:** operator's call.

## Backend gaps

- [ ] **Loans without a request never become `active`.** Only a request moving to `paid` activates its signed loans, so a loan created directly (future Home Fund `fund_loans`) stays `signed`, can't be forgiven or paused, and doesn't show missed installments. **Fix:** activate on disbursement from the payments webhook (a service-only `activate_loan(loan)` once the partner confirms the money moved), or from the `fund_loans` disbursement path. **When:** Stage 3, with `fund_loans`.
- [ ] **Partial refunds in the ledger.** `mark_refunded` stores `refunded_cents`, which can be less than the contribution's amount, but status just says `refunded`. **Fix:** the `payments-webhook` refund journal must post `refunded_cents`, not `amount_cents`. Add a pgTAP check once the journal-posting code exists. **When:** Stage 1, step 1f (payments).
- [ ] **A payout returned after a refund isn't blocked in the database.** `refunds_due` splits captured money across live payouts oldest first. If a payout were marked `returned` after contributions were already refunded, the split wouldn't re-run. Normal paths can't reach this, because refusing or withdrawing needs no live payout, but nothing forbids it. **Fix:** in the payout guard, refuse moving a payout to `returned`/`failed` when the request already has refunded contributions, and route it to a person instead. **When:** Stage 1, step 1f.

- [ ] **Small-number suppression in public figures.** `public_stats` gives per-fund totals only today, which identify no one. Before step 2d adds per-state or per-week figures to the transparency dashboard, the view must hide or merge any figure counted from fewer than 10 members or requests (`design.md`, "Dashboards"), with a pgTAP check. **When:** Stage 2, step 2d.
- [ ] **No voluntary demographics for bias audits or grant reporting.** The yearly bias audit and CDFI loan-level reporting need race, ethnicity and age data the schema doesn't hold. **Fix:** an optional, self-reported table in the `private` schema that the scorer, reviewers and panel can't read, used only for the bias audit and aggregate grant reports. Needs `/safe-migration` and compliance review (ECOA/Reg B limits on collecting it). **When:** before Stage 2's first bias audit.

## Funding

- [ ] **Re-check each programme before applying.** The figures in `design.md` "Public and grant funding" were checked on 2026-10-30: CDFI Fund FY2026 appropriation of $324M (enacted after a proposed cut, with late payouts); the ~$125,000 TA award cap comes from older notices; the FY2026 USDA cooperative development round closed in July 2026. **When:** at each application, against that programme's current notice.

## Decisions waiting on the operator

- [ ] **Rename "legitimacy score" to "evidence score"** in the app and site (recommended in `design.md`, "Business model review"). The schema already says `score` neutrally; only copy changes.
- [ ] **PR review and branch protection on `main`** are off by choice while pre-launch (`CLAUDE.md`). Switch them back on before Stage 1 has real members, or as soon as a second developer starts pushing. While protection is off, `dependabot-auto-merge.yml` can merge minor and patch bumps without waiting for CI.
- [ ] **The "Hearth" Claude Doc** (the first design write-up, made before the rename) is stale: old name, no request flow, no business-model review. Update it from `design.md`, or delete it.
- [ ] **Numbers needing actuarial review:** subscription formula v1 (floor $1,500/month take-home, 1%, $60 cap), pool minimum score 70, 10-point bands, 20% reserve, 60/90-day waiting periods, cover caps for $0 subscribers.
