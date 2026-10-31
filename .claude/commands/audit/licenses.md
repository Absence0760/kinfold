---
description: Inventory dependency licenses across the pnpm workspace and Deno imports and flag copyleft, unknown or attribution-missing licenses
---

Walk every dependency tree, collect each package's declared license, and flag the ones that create legal risk for what Kinfold ships: a prerendered SvelteKit site served from S3 + CloudFront, and a Supabase backend (Postgres migrations, Deno edge functions planned).

## Goal

`/audit/deps` walks the same trees for CVEs and version drift; this audit walks them for **legal risk**.

- **Strong copyleft (GPL / AGPL / SSPL)**: GPL code in the client bundle is distribution; AGPL in a hosted server function can require releasing source. The headline class.
- **Weak copyleft (LGPL / MPL-2.0 / EPL)**: usually fine; flag for review, don't assume.
- **Permissive-with-attribution (MIT / BSD / Apache-2.0 / ISC)**: fine to ship but the notice must be reproduced. For the web bundle that means a licenses/NOTICE page or a bundled third-party notice file.
- **Unknown / unlicensed / custom / dual-licensed**: needs a human read; unknown is risk, not safe.

Also confirm the repo's own `LICENSE` matches the intended posture for a member-owned cooperative (a template-default license left in place is worth naming; the choice itself is the operator's).

## What to check

1. **pnpm workspace**: root `package.json`, `apps/web/package.json`, any `apps/backend/package.json`. Use `pnpm licenses list --long` (or `--json`) from the root. Mark each as client bundle / build-only / dev-only (`pnpm why <pkg>` if unsure).
2. **Deno edge functions**: `apps/backend/supabase/functions/*` (to build; say "none yet" if absent). URL / `npm:` / `jsr:` imports have no license field of record; resolve each to its source and license. Server-side, so AGPL matters most.
3. **Postgres extensions** enabled in migrations: note license (e.g. PostGIS is GPL but runs inside Supabase's managed server; record, don't alarm).
4. **Fonts, icons and static assets** under `apps/web/static/` and anything imported from `src/app.css` (OFL / CC licenses carry attribution or naming terms).
5. **AI model / redaction / KYC SDKs** once added: their terms (data use, output ownership) belong in `/audit/third-party-data-flows`; record only the code license here.

For each: package → version → SPDX license → where it ships → risk class.

## Report

- **Critical**: GPL in the shipped client bundle; AGPL/SSPL in a hosted function.
- **High**: weak copyleft or unknown/custom license in shipped code; dual-licensed with the chosen license unpinned.
- **Medium**: permissive dependencies shipping with no attribution surface.
- **Low**: build-only copyleft; first-party license-field gaps.

Each finding: package + version, tree, license, distributed vs hosted vs build-only, the obligation, and the remediation (replace, move build-only, add attribution, or get counsel sign-off). This is an inventory, **not legal advice**; Critical/High end with "confirm with counsel" and can be handed to the `legal-researcher` agent.

## Delegate to

The `compliance-auditor` agent (`.claude/agents/audit/`): `"Inventory dependency licenses across the pnpm workspace, Deno imports, Postgres extensions and static assets, and flag copyleft / unknown / attribution-missing licenses. Write the report to reviews/audit-licenses.md."` Read-only.

## Output → `reviews/`

Persist the inventory table and findings to `reviews/audit-licenses.md` (git-ignored; see `reviews/README.md`), findings grouped by severity with `[ ]` boxes, updated in place on re-runs. Writing this one file is the only change the audit makes.
