---
description: Map every outbound personal-data hop into a sub-processor list ready for the Privacy Policy
---

Audit every outbound flow of personal data to a third-party processor. Output is the input to a Record of Processing Activities (GDPR Art 30 shape, also what US state privacy laws and partner due diligence ask for) and the sub-processor list of a Privacy Policy.

## Goal

A regulator's or partner's first ask in any incident is "show me your sub-processor list". A member's most-clicked Privacy Policy section is "who does my data go to?". Both need the same artefact: a table of provider × data × purpose × region × DPA + opt-out path. This audit produces it by walking the codebase — and, for Kinfold today, by walking `docs/design.md`, because most processors are designed but not yet chosen or integrated.

Kinfold handles unusually sensitive data: identity, income and bank-statement data, loan amounts, hardship details, photos of people, vehicles and homes, police reports (`docs/STACK.md` § Domain rules: financial and identity data is sensitive).

## What to check

1. **Provider inventory — in code.** Grep `apps/` for outbound base URLs and SDK imports (`fetch(`, `https://`, `@supabase/`, provider SDKs), `apps/backend/supabase/config.toml` for auth providers, SMTP, storage S3 settings and `[edge_runtime]`, and `.github/workflows/` for third-party actions that see data. Today expect: Supabase (auth, Postgres, storage) and, for the static site, whatever `apps/web` loads at runtime (fonts, analytics — check `src/app.html` and `+layout.svelte`; none is expected).

2. **Provider inventory — designed, not yet chosen** (`docs/design.md` § Structure and § Open questions; `docs/backend.md` § Architecture draws the full partner set). List each as a pending row so the Privacy Policy draft can't forget it:
   - **KYC vendor** — identity documents and selfies; Kinfold keeps only the vendor reference and outcome (`private.member_identity`).
   - **Bank-link provider** — read-only bank statements for earnings verification (`docs/design.md` § The subscription).
   - **Payment partner** — moves money between people and to payees; sees names, amounts, payee details.
   - **Licensed partner insurer / reciprocal** — holds the community pool; receives claim data.
   - **Partner credit union / CDFI** — holds the Home Fund; receives applicant data and needs assessments.
   - **AI scorer provider** — receives unredacted evidence (see `/audit/llm-endpoint`).
   - **Redaction service** — if redaction is a hosted API rather than a self-hosted model.
   - **Insurer databases** — duplicate-claim checks "where a partner gives access" (`docs/design.md` § Fraud-proofing).
   - **E-signature provider** — loan agreements and promissory notes.
   - **County lien recording** — secured family loans record a lien on the home (`docs/design.md` § Product 1); the lien is a public record by design.
   - **Email provider** — transactional email (local: Mailpit on port 54724).
   - **Hosting** — AWS S3 + CloudFront for `apps/web` once `infra/` lands.

3. **Per-flow analysis.** For each:
   - What member data leaves? (email, IP, identity document, bank data, evidence photos, request text, amounts, hardship details)
   - From where? (browser, edge function, DB job, partner webhook)
   - To which region?
   - DPA / data-sharing agreement URL, or "contract pending"?
   - Opt-out, if any? (most of these are necessary for the service and have none — say so)
   - Legal basis? (contract / consent / legal obligation for KYC)

4. **Third parties in the evidence.** Photos and reports contain people who are not members (the other driver, passers-by, plates). Redaction protects the public copy; the original still flows to the scorer and reviewers. Note this as a disclosure item.

5. **Funders.** Family and friends who give or lend through a shared request may not be members. Their data (name, payment details via the payment partner, loan agreement) is personal data Kinfold processes — list where it goes.

6. **Error monitoring and analytics.** Any error monitor or analytics added to `apps/web` sees URLs and possibly request ids. Confirm none is present without disclosure, and that session replay is off.

7. **Inbound webhooks.** Payment partner and KYC webhooks create data here; record the retention obligation they create.

8. **Sub-sub-processors.** Supabase and AWS have their own sub-processor lists; the Privacy Policy points to them rather than enumerating them.

## Report

Output two artefacts:

### (A) Sub-processor table

| Provider | Status (live / designed) | Data | Region | Purpose | DPA / agreement | Opt-out |
|---|---|---|---|---|---|---|

One row per flow.

### (B) Findings

- **Critical** — personal data leaving to a processor that is not disclosed anywhere; unredacted evidence reaching a processor other than the scorer.
- **High** — a flow that bypasses an opt-out the member was offered; identity documents stored by Kinfold rather than the KYC vendor.
- **Medium** — missing region or retention detail.
- **Low** — undocumented sub-sub-processor chain.

End with a **clean** section: outbound endpoints confirmed to carry no personal data.

## Delegate to

Use the `compliance-auditor` agent: `"Map every outbound personal-data flow in this repo, plus the processors designed in docs/design.md, into a sub-processor list."`

Read-only. Output the table + findings. Questions about what the law requires go to `legal-researcher`.
