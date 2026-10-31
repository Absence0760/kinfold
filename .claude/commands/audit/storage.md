---
description: Audit evidence storage (Supabase Storage buckets, object policies, path guessability, signed URLs) against the private-original / redacted-public rule
---

Audit the evidence storage layer: bucket policies that don't match table-level RLS, paths that make objects guessable, and any route by which an unredacted original becomes reachable.

## Goal

`docs/STACK.md` § Domain rules: **shared evidence is redacted; originals are private.** Nothing reaches the members-only board (`board_requests`) without automatic redaction **plus** the member's confirmation, and the unredacted original is kept for the scorer and reviewers only (`docs/design.md` § 2. Upload evidence). If the requests table hides an original but its object is fetchable by URL, the table-level guarantee is moot. Verify every bucket's read/write policy matches the row-level intent of the table that points at it.

The design is in `docs/backend.md` § Access model: two private buckets, `evidence-original` (files under the member's own folder, readable only by the member; reviewers get short-lived signed URLs from the `evidence-url` edge function, which writes `private.audit_log`) and `evidence-redacted` (readable by the owner, and by verified members once the request is on the board). Buckets and policies are created in `apps/backend/supabase/migrations/20261030120100_requests.sql`. The edge functions (`redact-evidence`, `evidence-url`) are not built yet: report their parts as "not applicable yet" and turn those checks into requirements. Don't invent findings.

## What to check

1. **Bucket inventory.** Every bucket from migrations (`storage.buckets` inserts, `storage.objects` policies) and `apps/backend/supabase/config.toml` `[storage]`. Expect exactly `evidence-original` and `evidence-redacted`, both with `public = false`; any further bucket (signed loan documents, gift letters) must be private to the parties. A bucket with `public = true` is Critical.
2. **Per-bucket policies.** Classify each `storage.objects` policy:
   - **Verified-member read**: only for `evidence-redacted`, and only for objects whose request is on the board (redaction confirmed). No `anon` read on either bucket.
   - **Owner read/write**: `auth.uid()::text = (storage.foldername(name))[1]`, the canonical pattern for a member's own uploads.
   - **Reviewer read**: never a storage policy on `evidence-original`; reviewers reach originals only through `evidence-url` signed URLs, which must refuse their own and same-region requests and write `private.audit_log`.
   - **Authenticated read** (any member): flag and confirm it's deliberate.
3. **Confirmation gate.** No object becomes readable by other members before redaction has run and the member confirmed (`submit_request` requires every redaction `confirmed`). Check the code path, not just the policy: a pipeline that writes redacted output straight to the public bucket before confirmation is High.
4. **Path discipline.** `{member_id}/{request_id}/{object_id}.ext` or similar; no flat namespace, no sequential ids, no original filename (it can carry a name or plate). Public paths must not reveal the original's path.
5. **Revocation.** When a request is withdrawn or a member is deleted, objects are removed or made unreachable; storage doesn't follow row deletes on its own. Cross-reference `/audit/account-deletion-completeness`.
6. **Signed URLs.** `createSignedUrl` TTLs short (minutes) for originals; signed URLs never stored in a public column or rendered into the prerendered site.
7. **Metadata.** Photo EXIF is needed by the scorer (design.md § Fraud-proofing: photo metadata) but must be stripped from the redacted copy (GPS = home address).
8. **Scorer access.** The scoring path reads originals with the narrowest credential available, not the service-role key from a client-reachable place.

## Report

- **High**: an unredacted original or unconfirmed redaction is reachable by someone outside owner/scorer/reviewer; GPS EXIF in a public object.
- **Medium**: broader than needed but no concrete leak (authenticated-read on originals, long TTLs).
- **Low**: undocumented intent, path pattern inconsistencies.

Each finding: file:line and a concrete reproduction path (a curl with the anon key, or steps to build the URL).

## Delegate to

The `repo-security-auditor` agent (`.claude/agents/audit/`), area `storage`: `"Audit evidence storage bucket policies, the redaction-and-confirmation gate, path guessability and signed-URL hygiene."` Read-only; don't change bucket policies without explicit instruction.

## Output → `reviews/`

Persist findings to `reviews/audit-storage.md` (git-ignored; see `reviews/README.md`), one finding per entry with a `[ ]` status box, grouped by severity, updated in place on re-runs. Writing this one file is the only change the audit makes.
