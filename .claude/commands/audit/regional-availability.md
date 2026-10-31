---
description: Check the US states Kinfold lets people join from against the states where each product (family loans, the community pool, the Home Fund) can lawfully run, and against what the site claims
---

Audit where Kinfold can honestly be offered, state by state, versus where signup lets someone in and what the marketing site promises.

## Goal

Kinfold is jurisdictional in a way most apps are not (`docs/design.md` § Legal reality, § Roadmap, § Open questions):

- **Family & Friends loans**: promissory notes, lien recording on a home and the Applicable Federal Rate gift setup vary by state; lien recording rules decide where larger loans work at all.
- **Community protection**: a promise to pay is insurance; the pool runs only through a licensed partner insurer, which is licensed per state. Phase 2 is **one state**.
- **Community Home Fund**: a partner credit union or CDFI, usually with a geographic field of membership. Phase 3 is **one city**.
- **Liability cover** stays mandatory everywhere; the pool covers own damage only.
- **The launch state is undecided** (design.md § Open questions). Until it is, the honest product is Phase 1 everywhere it's lawful, with nothing implying pooled cover.

The failure mode: a member in a state with no partner joins, pays a subscription, posts a damage request, and only then learns the pool can't pay in their state.

## What to check

1. **Where signup lets people in.** `public.members.region` is a two-letter US state code (`apps/backend/supabase/migrations/20261030120000_members.sql`). Is there an allowlist of launched states, or does any code accept all? Is region verified (KYC address) or self-declared? A self-declared region that gates insurance is a finding.
2. **Per-product gating.** Fund availability should be data, not code (fund settings are already data in `public.fund_settings`); check whether pool and Home Fund eligibility consult a per-state table, and that a member outside it can still use Phase 1 (gifts and family loans) with a clear message.
3. **Claims versus capability on the site.** `apps/web/src/lib/landing/` (Hero, Products, HowRequestsWork, Roadmap, RequestBoard, SavingsCalculator): does any copy promise pool cover, Home Fund help or a payout time without saying it's limited to launched states, pending a licensed partner, or a design target? Implying insurance where none is licensed is High.
4. **Family-loan documents per state.** When note/lien templates exist, confirm each is keyed by state and that a state without a reviewed template blocks the lien step rather than falling back to another state's form.
5. **Tax figures.** The $10,000 below-market-loan threshold and AFR are federal; the gift-tax annual exclusion changes yearly. Confirm they're sourced data with a date, not constants silently going stale.
6. **Payment partner coverage.** Whichever partner moves money between people may not onboard every state or entity type; that limit should be visible before a member shares a request.
7. **Non-US visitors.** The site is public worldwide. Confirm signup doesn't accept non-US members by accident (no non-state region values, no non-US KYC path).
8. **Locale defaults.** USD and US date formats via `Intl` with `en-US` (`apps/web/src/lib/core/format.ts`); flag hard-coded formats.

## Report

Frame findings as **capability versus claim**:

- **High**: the product or site implies a regulated capability (pooled cover, Home Fund lending) in a state where no licensed partner exists; region self-declared yet gating insurance.
- **Medium**: a member can join and reach a dead end with no forewarning.
- **Low**: stale tax constants, undocumented partner coverage limits, locale nits.

Most fixes are **product or copy** rather than code; say which. Questions that turn on state law go to the `legal-researcher` agent, not a guess.

End with a **clean** section: what is confirmed available everywhere today.

## Delegate to

The `compliance-auditor` agent (`.claude/agents/audit/`): `"Audit regional availability state by state: signup and region verification, per-product gating for family loans, the community pool and the Home Fund, site claims versus licensed capability, per-state document templates, tax constants, and payment-partner coverage."` Read-only.

## Output → `reviews/`

Persist findings to `reviews/audit-regional-availability.md` (git-ignored; see `reviews/README.md`), one finding per entry with a `[ ]` status box, grouped by severity, updated in place on re-runs. Writing this one file is the only change the audit makes.
