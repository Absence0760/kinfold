---
description: Audit Kinfold's privacy-law posture — US state privacy laws (CCPA/CPRA and peers) and GLBA-style financial privacy first, GDPR / UK GDPR only if non-US users are admitted — notice, lawful basis, consent, data-subject requests, retention vs. record-keeping duties, transfers, minors, breach plan
---

Audit the privacy posture of Kinfold. The goal is a punch list the operator can take to counsel before the member app opens sign-up. (The file keeps its `gdpr` name for continuity with the other estate repos; the content is Kinfold's actual regime.)

## Goal

Kinfold is a US-first cooperative: `public.members.region` is a two-letter US state code (`apps/backend/supabase/migrations/20261030120000_members.sql`), and launch is one state at a time (`docs/design.md` § Roadmap, § Open questions). It handles some of the most sensitive categories there are — identity, income and bank-statement data, loan amounts, hardship details, photos of people and property, police reports (`docs/STACK.md` § Domain rules: financial and identity data is sensitive). So the regimes that matter first are:

- **State consumer privacy laws** (CCPA/CPRA and the growing set of peers) — notice at collection, right to know / delete / correct, sensitive personal information limits, no sale or sharing.
- **Financial privacy** — GLBA's privacy and safeguards rules may apply to Kinfold or flow down through the payment partner, the partner credit union and the partner insurer by contract. Whether Kinfold itself is a "financial institution" is a question for `legal-researcher` and counsel.
- **FCRA / ECOA** — if the reliability record or the Home Fund needs formula functions like a credit decision (`docs/design.md` § How the pieces connect: "The record replaces a credit score"), adverse-action and fair-lending duties may attach. Flag, don't decide.
- **GDPR / UK GDPR** — only if non-US residents can join. Check whether anything prevents it; if nothing does, the GDPR checks below apply too.

Kinfold is pre-launch: the web app is a prerendered marketing site and the backend is an early schema. Many checks will be "not built yet" — record what the first member-facing release must include.

## What to check

1. **Privacy notice + terms.** Do `/privacy` and `/terms` routes exist under `apps/web/src/routes/`? Linked from the footer (`apps/web/src/lib/landing/SiteFooter.svelte`) and, once it exists, from sign-up? A notice at collection is required before the first byte of personal data is collected.
2. **Personal-data inventory.** List every table and column holding personal data across `apps/backend/supabase/migrations/`, noting which schema (`public` vs `private`) and which are sensitive (identity, financial, hardship, precise location, photos of people). Cross-check against what the design says Kinfold keeps — e.g. identity: only the KYC vendor's reference and outcome, never the documents (`private.member_identity`).
3. **Lawful basis / purpose per category.** For each category, the purpose and basis (contract, legal obligation such as KYC, consent). Sensitive personal information used only for the purpose collected (CPRA limit-use); hardship details used only for Home Fund needs assessment.
4. **Consent.** The marketing site should need no consent banner if it loads no non-essential third parties (see `/audit/cookie-consent`). Consent for bank-link access and for sharing a request with family and friends is explicit and revocable.
5. **Data-subject requests.** Right to know / access (and GDPR Art 15/20), deletion (Art 17), correction (Art 16). Is there a planned path for each? See `/audit/data-export-completeness` and `/audit/account-deletion-completeness`.
6. **Retention vs. record-keeping.** `docs/backend.md` § "Privacy and retention" states the design targets (originals ~2 years after close; financial records ≥ 5 years with personal fields separable). Check the code matches. Kinfold must keep some records even after a deletion request: loan agreements, repayment history, gift letters and tax paperwork (`docs/design.md` § Product 1), payout records, KYC outcomes, audit logs of sensitive reads. Each needs a documented retention period and a legal basis for keeping it; everything else needs a purge. "Keep forever" is a finding.
7. **Public vs private.** Aggregates are public (`public_stats`, `pool_runs`); personal details never are (`docs/design.md` § Principles 6). The board is members-only and shows only the redacted summary, kind, amount, score, state and week — never names, towns or exact dates (`board_requests` view, `docs/backend.md`). Confirm nothing more leaks, Home Fund hardship details never appear, and the giving record stays private to the member (`my_giving_record()`).
8. **Sale / sharing.** Kinfold never sells member data (`docs/design.md` § Sustainability). Confirm no analytics or ad SDK "shares" data in the CPRA sense; mortgage-partner referrals pass data only with the member's explicit action.
9. **Cross-border transfers.** Region of each processor (Supabase project region, AWS, AI scorer provider, KYC vendor). Only matters for GDPR if non-US users are admitted; also matters if a processor stores US financial data abroad and a partner contract forbids it.
10. **Minors.** Members must be adults to sign agreements and lend; is there an age attestation or KYC-derived check? Funders who aren't members may include minors receiving a share link — note it.
11. **Breach notification.** Is there a runbook? US state breach laws (and GDPR's 72 hours, if applicable) and partner contracts all impose clocks.
12. **Safeguards.** Encryption at rest, least-privilege access, audit-logged reads of sensitive data (`docs/STACK.md` § Domain rules). Check that sensitive tables are in `private` with no client grant, and that a read-audit mechanism is planned.
13. **Automated decision-making.** Scores never refuse on their own (`docs/design.md` § Principles 8). Confirm the notice explains the score, its reasons, human review and appeal — this is also what GDPR Art 22 and emerging state AI rules ask.

## Report

- **Critical** — personal data collected with no notice; sensitive data in a `public` table readable by other members; an automated refusal; data sold or shared with an ad/analytics provider.
- **High** — no deletion or access path planned; retention undefined for financial or identity records; hardship data exposed beyond the Home Fund review.
- **Medium** — no breach runbook, no RoPA / data map, no documented basis for retained records after deletion.
- **Low** — defence-in-depth (read-audit log not yet designed, minor gaps in notice wording).

For each: the regime and section (CCPA §1798.xxx, GLBA, GDPR Art X, or "ask counsel"), and the concrete fix scope (file, or "policy doc + product change").

End with a **clean** list of areas that look fine.

## Delegate to

Use the `compliance-auditor` agent: `"Audit Kinfold's privacy-law posture (US state privacy laws, financial privacy, GDPR only if non-US users can join)."` Route open legal questions to `legal-researcher`.

Read-only. Findings only. Always end legal claims with "ask counsel if unsure" — this is not legal advice.
