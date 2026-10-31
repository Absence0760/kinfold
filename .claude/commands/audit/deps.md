---
description: Cross-workspace dependency audit (pnpm + Dependabot config + GitHub Actions pinning)
---

Sweep dependencies across every workspace for known CVEs and version drift; verify Dependabot covers everything and CI workflow pins aren't a supply-chain risk.

## What this is

The repo is a pnpm workspace (`pnpm-workspace.yaml`, `apps/*`):

- `apps/web` — SvelteKit 5, `adapter-static`, Vite, Vitest, svelte-check
- `apps/backend` — Supabase: SQL migrations and (planned) Deno edge functions under `apps/backend/supabase/functions/`. Any `package.json` there is tooling only; edge functions pin their imports (`npm:`, `jsr:`, URL imports, or an import map / `deno.json`) outside pnpm's view
- no `infra/` yet (Terraform, when it lands, has no Node deps)

Plus:

- **Root `package.json`** — workspace orchestration (`packageManager: pnpm@…`, `engines.node >= 22`) and any `pnpm.overrides`
- **GitHub Actions** — `.github/workflows/*.yml` — action SHA pinning vs floating tags
- **Dependabot config** — `.github/dependabot.yml` — one `npm` entry at `/` covering the whole workspace, plus `github-actions`

There's already a scheduled `audit.yml` workflow that runs `pnpm audit` weekly and files an issue on findings. This command does the equivalent sweep on demand plus the supply-chain checks the scheduled job doesn't cover (Dependabot config drift, workflow pinning).

## What to check

1. **`pnpm audit` per workspace.** Run from the repo root:
   ```
   pnpm audit --audit-level=moderate
   ```
   (one lockfile covers the workspace; `pnpm -r why <pkg>` traces a finding to the workspace that pulls it in). Collect moderate+ findings. For each: package, version, CVE, fix version, which workspace. A transitive that upstream hasn't fixed gets pinned via the root `package.json`'s `pnpm.overrides` block, with a comment naming the advisory.

   **Edge functions** (once `apps/backend/supabase/functions/` exists): list each function's imports and their pinned versions; flag unpinned URL imports and `npm:` specifiers without a version. `pnpm audit` does not see these.

2. **Open audit issue.**
   ```
   gh issue list --label dependency-audit --state open
   ```
   If one exists, surface its title — that's the scheduled `audit.yml`'s most recent flagged set. Confirm whether the findings match what `pnpm audit` returns today.

3. **Dependabot coverage.** Read `.github/dependabot.yml`. The expected shape is:
   - `package-ecosystem: npm`, `directory: "/"` — covers the root and every `apps/*` workspace through the shared lockfile.
   - `package-ecosystem: github-actions`, `directory: "/"`.
   - Schedule weekly; minor + patch grouped.
   - When edge functions land, Dependabot has no Deno ecosystem — note that their imports need a manual bump cadence (or a `deno.json` import map reviewed in this audit).
   - Flag a missing ecosystem, a non-weekly schedule, or an ungrouped flood of related packages.

4. **Lockfile-sync workflow exists.** Dependabot edits `<workspace>/package.json` but never touches the root `pnpm-lock.yaml`, which breaks any CI step running `pnpm install --frozen-lockfile`. The compensating workflow is `.github/workflows/dependabot-lockfile.yml` — it regenerates the lockfile on every Dependabot PR and commits the result back so CI retriggers and the PR can go green without manual intervention. Verify:
   - The workflow file exists.
   - It uses `DEPENDABOT_LOCKFILE_PAT` (a fine-grained PAT with `Contents: Write`), not `GITHUB_TOKEN` — GitHub blocks the latter from retriggering `pull_request` events.
   - The PAT is scoped to this repo and has an expiry. If it's stale or revoked, dep PRs pile up unmerged.

5. **GitHub Actions pinning.** Grep `.github/workflows/` for `uses: <action>@<ref>`.
   - Floating refs (`@main`, `@v6`) are supply-chain risks for actions that can be force-pushed by the publisher.
   - SHA pins (`@<sha>`) are the safer default for workflows that touch `${{ secrets.* }}` or deploy.
   - Flag floating refs on any deploy workflow (none live yet; `deploy.yml.example` is the template) and `claude.yml` (which has access to project tokens). `security.yml`, `audit.yml`, `gitleaks.yml`, `pr-title-lint.yml`, `labeler.yml` are lower-stakes but worth surfacing too.

6. **Override hygiene.** Read the root `package.json` `pnpm.overrides` block. For each override:
   - Confirm it's still needed — has upstream shipped a fix that lets us drop the override? Pull the latest version of the package from npm and check.
   - Confirm the override range is tight (e.g. `^0.7.0` not `>=0.7.0`).
   - Confirm there's a comment or commit message explaining *why* (the original CVE).

7. **Node engines.** Root `package.json` declares `"engines": { "node": ">=22" }`. Confirm:
   - CI workflows use `node-version: 22` or newer (or read `.tool-versions`), not unspecified.
   - `.tool-versions` agrees with `engines` and the `packageManager` pnpm version.
   - Edge functions run on Supabase's Deno runtime (`[edge_runtime]` `deno_version` in `apps/backend/supabase/config.toml`); note the version.

8. **Local toolchain drift.** Optional but worth flagging if obvious: check the user's `~/.bashrc.d/` setup gives a recent enough pnpm + node. The `update-all` function in `~/.bashrc.d/32-functions-update.sh` covers system tools; if local node/pnpm versions are wildly out of sync with what CI uses, flag it.

## Report

- **Critical** — known-exploited CVE in a runtime path (code shipped in the prerendered `apps/web/build/` bundle, or an edge function), not just a dev-only transitive. Note that `apps/web` ships only static output, so most of its tree is build-time only — say which side of that line each finding is on.
- **High** — a CVE with a fix available; a deploy workflow using a floating action ref; Dependabot missing an entire workspace.
- **Medium** — version drift with no CVE but the upgrade is overdue; loose override range; Node version mismatch between `engines`, `.tool-versions` and CI; unpinned edge-function imports.
- **Low** — undocumented override, floating ref in a non-deploy workflow, dependabot grouping that could be tightened.

For each finding: package + version + advisory link + the file to change + the upgrade command (or the override expression).

## Useful starting points

- `package.json` (root) — workspace orchestration + overrides
- `apps/web/package.json`, `pnpm-workspace.yaml`, `.tool-versions`
- `.github/workflows/*.yml`
- `.github/dependabot.yml`
- `apps/backend/supabase/config.toml` (`[edge_runtime]`), `apps/backend/supabase/functions/` once it exists
- The latest `audit.yml` workflow run for the current findings set

## Delegate to

Use a `general-purpose` agent — the work is mostly running each tool in turn and reading the output. Pass this file as the prompt body.

Read-only audit. Recommend upgrades; don't apply them without instruction (a major bump is its own conversation).
