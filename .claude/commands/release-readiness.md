---
description: Pre-tag readiness gate. Checks working tree, main, CI status, and the per-workspace deltas since the last release tag. Reports a green/red checklist. Read-only; never tags.
---

Run a pre-tag readiness audit before publishing a GitHub release. Report a green/red checklist; never tag, push, or publish anything. The user does the actual `gh release create` after they've reviewed the report.

## Why this exists

Kinfold has no deploy workflow yet: `.github/workflows/` holds only `deploy.yml.example` (the template's gated pattern — every deploy job on `environment: production` with the operator as required reviewer, per root `CLAUDE.md` § Repo-wide hard rules). When deploys land they will be release-gated per workspace: `apps/web` (the prerendered build from `pnpm build:web`, to S3 + CloudFront per `docs/STACK.md`) and `apps/backend` (Supabase migrations + edge functions pushed to the hosted project). Cutting a tag with the working tree dirty, CI red, or unpushed commits means the deploy doesn't match what you think it does. Until a real `deploy*.yml` exists, run this as a dry readiness check and say in the verdict that nothing will auto-deploy.

The gates are scattered (CI status, working tree, push state, last-tag delta per workspace) and the human-eyeball version is unreliable. This command runs them in one shot.

## When to use

**Right fit:** you're about to cut a release and want a single yes/no.

**Wrong fit — refuse:**
- The user is on a feature branch (not `main`) — explain that releases tag from `main`, ask whether to switch.

## Procedure

### 1. Confirm we're on main

```
git rev-parse --abbrev-ref HEAD
```

If not `main`, abort with: "releases tag from `main`; you're on `<branch>`. Switch with `git checkout main && git pull`, then re-run."

### 2. Run the universal gates

For each, mark **green** / **red** and capture a one-line reason for any red.

#### 2a. Working tree is clean

```
git status --porcelain
```

Empty → green. Anything → red ("uncommitted changes in: <files>"). Pay particular attention to plaintext env files (`.env`, `*.env.development.local`, `apps/backend/supabase/.env`, `infra/terraform.tfvars` once `infra/` exists) — if they're showing up tracked, that's a separate Critical to flag.

#### 2b. main is up to date with origin

```
git fetch origin main
git rev-list --count HEAD..origin/main
git rev-list --count origin/main..HEAD
```

Both `0` → green. Behind → red. Ahead → red ("local main has unpushed commits — push first, wait for CI, then re-run"). Note: `git push` is on the `.claude/settings.json` deny list by default; surface this as a manual step.

#### 2c. Latest CI run on main is green

```
gh run list --branch main --limit 1 --json status,conclusion,workflowName,headSha,createdAt
```

`status=completed` and `conclusion=success` → green. Anything else → red ("CI on the head commit is `<status>/<conclusion>` — wait for green or investigate").

Also check the most recent runs of `security.yml`, `audit.yml`, `gitleaks.yml` and any CI workflow that exists by then — if any of those have an open failed run, surface as an amber row (informational; doesn't block but worth knowing).

If the user has `gh` but isn't logged in, recommend `gh auth login` and skip — don't fail the whole report.

### 3. Per-workspace deltas since last release

Find the last release tag:

```
git describe --tags --match 'v[0-9]*' --abbrev=0
```

If there is no tag yet, compare against the root commit and say this is the first release. For each workspace, list the commits + files changed since that tag. Deploy workflows (once they exist) will skip-if-unchanged per workspace; this section makes the "what will actually deploy" picture explicit.

```
# Web (prerendered marketing / preview site)
git log --oneline <last-tag>..HEAD -- apps/web/
git diff --stat <last-tag>..HEAD -- apps/web/

# Backend (Supabase migrations, pgTAP tests, edge functions)
git log --oneline <last-tag>..HEAD -- apps/backend/
git diff --stat <last-tag>..HEAD -- apps/backend/supabase/migrations/

# Infra (not a workspace yet; only once infra/ exists)
git log --oneline <last-tag>..HEAD -- infra/

# Workflows / .claude (informational — never deploys)
git log --oneline <last-tag>..HEAD -- .github/workflows/ .claude/
```

For each workspace, report:
- **Commits since:** count + one-line summaries
- **Will deploy:** `Yes` if any commit touched the workspace's tree and a deploy workflow for it exists, `No` otherwise, `n/a — no deploy workflow` until one lands
- **Backend only:** a new migration since the last tag is a production schema change — list each file, and confirm `/safe-migration` ran on it (its commit should be path-scoped `feat(db):` / `fix(db):`). A migration touching money, scoring or the `private` schema is an amber row: name it so the operator reviews it before release.

If `Commits since` is `0` for every workspace, flag as red — there's nothing to release.

### 4. Sanity checks

#### 4a. Security posture

Surface anything from the last `audit.yml` run that's still open:

```
gh issue list --label dependency-audit --state open
```

If issue exists, flag as amber and include the title — operator should know if a CVE issue is open before releasing.

```
gh api repos/{owner}/{repo}/code-scanning/alerts --jq '[.[] | select(.state=="open")] | length'
gh api repos/{owner}/{repo}/dependabot/alerts --jq '[.[] | select(.state=="open")] | length'
```

Non-zero either → amber. Don't block; just surface.

#### 4b. Plaintext env files not tracked

```
git ls-files | grep -E '(^|/)\.env($|\.)|\.env\.development\.local$|terraform\.tfvars$'
```

Only committed, non-sensitive `.env.development` files are allowed (root `CLAUDE.md` § "Local-dev env is committed; real secrets never are"). Any other hit → red. Do not open or print the file's contents — report the path only.

#### 4c. Local gates pass

```
pnpm check
pnpm test
pnpm build:web
```

Plus `pnpm test:backend:db` when the backend changed and the local stack is up (`pnpm dev:db:up`). Any failure → red.

### 5. Build the report

```
# Release readiness — proposed `v<x.y.z>`

## Universal gates

| Gate | Status | Detail |
|---|---|---|
| On main | ✓ / ✗ | ... |
| Working tree clean | ✓ / ✗ | ... |
| main pushed + in sync with origin | ✓ / ✗ | ... |
| CI green on HEAD | ✓ / ✗ | ... |

## Per-workspace deltas since `v<last>`

| Workspace | Commits since | Will deploy | Notes |
|---|---|---|---|
| apps/web | <n> | Yes / No / n/a | <one-line> |
| apps/backend | <n> | Yes / No / n/a | <one-line; list new migrations> |
| Infra | <n> | n/a | <one-line, or "no infra/ yet"> |

## Open audit signals

- audit.yml issue open: <yes/no, with title if yes>
- CodeQL alerts open: <count>
- Dependabot alerts open: <count>

## Changelog draft (commits since `v<last>`)

- abcd123 commit subject
- ...

## Verdict

<ALL GREEN — ready to publish a release with:
  gh release create v<x.y.z> --title "v<x.y.z> - <short summary>" --notes "<...>">

or

<NOT READY — fix the red items above first>
```

### 6. Hand off

End with:

> If everything's green, the next step is:
> ```
> git push origin main      # if you have commits ahead
> gh release create v<x.y.z> --title "..." --notes "..."
> ```
> I won't run those — `git push` and `gh release create` are both on the deny list by default. That's your call.

**Do not tag, do not push, do not create a release, do not auto-fix any of the red gates.** This command is read-only.

## Notes

- The whole thing should take under a minute. If a gate hangs (e.g. `gh run list` on a slow connection), skip it with a `⚠ skipped — <reason>` row rather than blocking the report.
- `gh` is required for the CI-status check and the open-alert sweep. If unavailable, fall back to a one-line note: "install `gh` to auto-check CI; manual: open the Actions tab and confirm green on the head commit."
- This command does NOT replace a deployment runbook (none exists yet; when deploys land, document them in `docs/` and link it here). It's a pre-flight, not the release procedure itself.
