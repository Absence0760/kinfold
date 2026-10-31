---
description: Verify every personal-data column and Storage object is included in the member's right-to-know / portability export
---

Audit the data-export path for completeness. Every personal-data row Kinfold holds about a member must be reachable via that member's export.

## Goal

Right-to-know (CCPA/CPRA) and portability (GDPR Art 20, if non-US users join) require the export to be **complete and machine-readable**. The risk is silent drift: someone adds a table or column holding member data, forgets to extend the exporter, and a later request gets a partial archive. For Kinfold the export is also a trust feature — members should be able to take their loan agreements, repayment history and reliability record with them (`docs/design.md` § How the pieces connect).

The member app is not built yet. If no export path exists, report "not built yet" and produce the inventory below as the spec the first implementation must meet.

## What to check

1. **Exporter.** Find the export path (edge function under `apps/backend/supabase/functions/` or an RPC in a migration). List every table and column it reads.
2. **Schema.** Walk every `apps/backend/supabase/migrations/*.sql` `create table` / `add column` in both `public` and `private`. Filter to member data. Diff against the exporter's coverage.
3. **What a member should get.** Profile and membership (status, region, joined date, roles); covered assets; requests with amounts, payees, status and outcome; the member's own evidence (originals, not only redacted copies — it's their data); legitimacy scores with model version and reasons; reviewer decisions and appeals about them; subscriptions and payments made; loans as borrower and as lender, with schedules, repayments, forgiveness and gift letters; pledges and gifts given to others; the reliability record.
4. **What a member should not get.** Other people's personal data: a funder's bank details, a reviewer's identity if the design keeps reviewers anonymous, unredacted third parties in someone else's evidence. Be explicit about what is withheld and why.
5. **Identity.** Kinfold holds only the KYC vendor's reference and outcome (`private.member_identity`); export those, and point the member to the vendor for the documents.
6. **Storage.** Every object under the member's prefix in each bucket, walked recursively, plus generated documents (agreements, gift letters).
7. **Format.** JSON (or CSV) in a zip; UTC ISO 8601 timestamps; amounts as integer cents with the currency stated (money is `bigint` cents everywhere — never convert to floats in the export); a schema version stamp.
8. **Authentication.** The exporter uses the JWT-verified `auth.uid()`; it never accepts a member id from the request. A service-role client in the exporter filters by that id on every query.
9. **Size and delivery.** Large exports run async and deliver via a short-lived signed URL; the export file itself is deleted after a set period.
10. **Tests.** A pgTAP or function test that populates every member-data table and asserts each appears in the export.

## Report

- **Critical** — a member-data table is not exported at all; the exporter can be pointed at another member's id.
- **High** — a column on an exported table is missing; a financial record (loan, repayment, payout) absent.
- **Medium** — Storage walked non-recursively; another person's personal data included.
- **Low** — format issues (timestamps without tz, amounts not labelled as cents, no schema version).

For each: the `<schema>.<table>.<column>` or `<bucket>/<prefix>`, and where the exporter would change.

End with a **clean** list of tables / buckets / third-party state that are fully covered.

## Delegate to

Use the `compliance-auditor` agent: `"Audit the member data export for completeness per right-to-know / portability."`

Read-only. Findings only.
