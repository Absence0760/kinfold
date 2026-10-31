---
description: Verify account deletion — every personal-data row, Storage object and third-party link is cleared or deliberately retained under a documented record-keeping duty
---

Audit the account-deletion path for completeness. When a member invokes "delete my account", nothing personal should remain except what Kinfold is legally required to keep, and that remainder should be minimised and documented.

## Goal

Deletion rights (CCPA/CPRA right to delete, GDPR Art 17 if non-US users join) require erasing personal data on request — with exceptions for records a law or contract requires Kinfold to keep. Kinfold has more of those exceptions than most apps: loan agreements and repayment history (a lender's money is still owed), gift letters and tax paperwork, payout records, KYC outcomes, and audit logs of sensitive reads. The two failure modes are both real:

- **Orphaned personal data** — an evidence original surviving in Storage, a request row pointing at a deleted `auth.users` id, a KYC vendor record never told to delete.
- **Over-deletion** — a cascade that wipes a family loan's agreement and repayment history while the borrower still owes the lender, or deletes the ledger rows a pool payout depends on.

The member app is not built yet. If no deletion path exists, report "not built yet" and produce the inventory below as the spec the first implementation must meet.

## What to check

1. **Handler.** Find the deletion path (an edge function under `apps/backend/supabase/functions/`, or a `security definer` RPC in a migration). Map every step to an asset class: DB row, Storage object, third-party link.
2. **Foreign keys.** Walk every `apps/backend/supabase/migrations/*.sql` for `references auth.users` and `references public.members`. For each, decide: `on delete cascade` (personal data with no retention duty), `on delete set null` / pseudonymise (records that must survive without identity), or `restrict` (records that must block deletion until resolved, e.g. an open loan). Flag any FK whose behaviour doesn't match its data's duty. `public.members` cascades from `auth.users` today — check what that cascade reaches.
3. **Personal-data tables.** Inventory every table in `public` and `private` holding member data — the tables in `docs/backend.md` § Data model: `members`, `private.member_identity`, `member_roles`, `income_verifications`, `subscriptions`, `subscription_payments`, `allocation_preferences`, `covered_assets`, `requests`, `request_events`, `evidence`, `scores`, `reviews`, `appeals`, `private.fraud_signals`, `request_invites`, `request_supporters`, `contributions`, `family_loans`, `loan_installments`, `loan_pauses`, `loan_forgiveness`, `payouts`, the `private.ledger_*` tables, `private.audit_log`. `docs/backend.md` § "Privacy and retention" is the intended policy (financial records kept ≥ 5 years with personal fields separated out so they can be deleted). For each: deleted, pseudonymised, or retained — with the retention reason and period.
4. **Two-sided relations.** A family loan has a borrower and lenders; a request has a requester and funders; a review has a member and a reviewer. Deleting one party must not destroy the other party's record of money they're owed or gave. Decide and document what each side keeps.
5. **Open obligations.** What happens when a member with an outstanding loan, an open request, or a pending payout asks to delete? The design's answer (`docs/design.md` § Product 1 protections) should be reflected: the deletion is deferred or restricted, the member is told why, and personal data not needed for the obligation is deleted now.
6. **Storage.** `evidence-original`, `evidence-redacted`, any avatars, generated documents (promissory notes, gift letters). Every object under the member's prefix is deleted or retained with a reason; redacted copies (`evidence-redacted`) are kept only if truly non-identifying and needed for the open books (`docs/backend.md` § "Privacy and retention").
7. **Board and open books.** A deleted member's past requests: removed from the members-only board (`board_requests`), or kept only as the anonymised aggregates the open books need (`pool_runs`, `pool_allocations`, `open_books`). Nothing identifying remains.
8. **Third parties.** KYC vendor (request deletion of the verification record or document the vendor's retention), bank-link provider (revoke the connection), payment partner (close the customer record; transaction records stay with the partner under its own duties), AI scorer provider (document its retention; no deletion API is typical), email provider (suppress, don't keep the address in marketing lists).
9. **Order.** The auth user is deleted last; earlier steps run while RLS still recognises the member, or through a definer function that checks the caller once up front.
10. **Confirmation.** Deletion requires re-authentication or typing a confirmation; the member is shown what will be kept and why.
11. **Audit trail.** A deletion record exists with no personal data in it (an opaque id, timestamp, outcome per asset class).
12. **Re-signup.** The same email later creates a fresh account, not a recovered one.
13. **Tests.** A pgTAP test under `apps/backend/supabase/tests/` that creates a member, populates every personal-data table, runs the deletion, and asserts each table is empty, pseudonymised or retained exactly as documented.

## Report

- **Critical** — personal data survives with no retention reason; or a deletion destroys records a lender, funder or partner is owed.
- **High** — a Storage prefix not walked; a third-party link not revoked; no handling for open loans or requests.
- **Medium** — wrong order; no audit record; no end-to-end test; retained data not minimised.
- **Low** — confirmation too easy; re-signup recovers instead of starting fresh.

For each: the `<schema>.<table>` or `<bucket>/<prefix>` or third party, and where the handler would change.

End with a **clean** list of tables / buckets / third-party links that are fully covered.

## Delegate to

Use the `compliance-auditor` agent: `"Audit account deletion for completeness: every personal-data row, Storage object and third-party link deleted, or retained under a documented duty, with open loans and requests handled."`

Read-only. Findings only. Retention periods and which duties apply are counsel's call — say "ask counsel if unsure".
