---
description: Find server-only secrets that may have leaked into the web bundle, git history, GitHub Actions logs, a public asset, or the Supabase config
---

Audit for secrets / env vars / API keys that should be server-only but are reachable from the web bundle, a public asset, a committed config, or git history.

## Goal

Production secrets live SOPS-encrypted in the **sibling `infra-secrets` repo** under `infra-secrets/kinfold/` (root `CLAUDE.md` § Repo-wide hard rules), NOT in this repo. The slot may not exist yet — Kinfold has no production environment today. The trust boundaries:

- **`apps/web`** is a prerendered static site (`adapter-static`, every route prerendered). Anything it reads at build time is public by construction. Today it reads no env vars at all (`docs/STACK.md`); when the member app lands, the most it may hold is the Supabase URL and the **anon (publishable)** key as `PUBLIC_*`. The **service-role key**, the AI scorer's API key, the payment partner's and KYC vendor's credentials never reach it.
- **`apps/backend/supabase`** — `config.toml` is committed and may only reference secrets as `env(NAME)`, never inline values. Edge function secrets (planned under `apps/backend/supabase/functions/`) are set on the hosted project, and locally live in a gitignored env file.
- Committed **`.env.development`** files may hold only non-sensitive local defaults (root `CLAUDE.md` § "Local-dev env is committed; real secrets never are") — the local Supabase stack's well-known demo keys are fine there; anything that authenticates to a real system is not.

Find any key on the wrong side, confirm no secret (encrypted or not) is committed to this repo, and confirm nothing leaked into history.

**Never decrypt, open, print or paste a secret value** — not with `sops -d`, not by `cat`-ing an env file. Identify findings by variable name + file path only. If a check needs a decrypted value, list it as a manual step for the operator.

## What to check

1. **No secret files in THIS repo.**
   - `git ls-files | grep -E '\.sops(\.yaml)?$'` returns nothing; the `.gitignore` guard (`*.sops`, `*.sops.yaml`) backs this up. Any such file here is a finding — secrets belong in `../infra-secrets/kinfold/`.
   - If `../infra-secrets/kinfold/` exists, confirm by structure only (file names, presence of a `sops:` metadata block and `ENC[` markers via `grep -c`), never by reading values.

2. **Plaintext env files absent from git.**
   - `git ls-files | grep -E '(^|/)\.env($|\.)'` — only `*.example` files and committed, non-sensitive `.env.development` files may appear. For each `.env.development`, check variable *names*: anything named like `*_SECRET`, `*_SERVICE_ROLE*`, `*_API_KEY` pointing at a real provider is a finding.
   - `git log --all --full-history --name-only -- '*.env' '*.env.local' '*.env.*.local' '**/terraform.tfvars'` returns zero commits. Any hit means the value is permanently exposed — Critical, rotate.

3. **Supabase config.**
   - `apps/backend/supabase/config.toml`: every credential field (`openai_api_key`, SMTP `pass`, SMS `auth_token`, external provider `secret`, `s3_*_key`) is either commented out or `env(NAME)`. A literal value is Critical.
   - `apps/backend/supabase/.gitignore` keeps `.env.local`, `.env.*.local`, `.env.keys` out; once `functions/` exists, its env file is ignored too.
   - Seed data (`apps/backend/supabase/seed.sql`, if present) holds no real personal data and no real credentials.

4. **Web bundle leakage.**
   - Grep `apps/web/src/` for `$env/static/private`, `$env/dynamic/private`, `$env/dynamic/public`. The site is fully prerendered with no server; any hit is a finding (Critical if it implies a server adapter was added).
   - Grep `apps/web/src/` for `process.env` — dead code or a bug in a static build.
   - Grep `apps/web/src/` and `apps/web/static/` for `service_role`, `SERVICE_ROLE`, `sb_secret_`, and JWT shapes (`eyJ[A-Za-z0-9_-]{10,}\.`). A service-role key in the web app bypasses every RLS policy — Critical.
   - After `pnpm build:web`, grep `apps/web/build/` for the same shapes (the built output is what actually ships).

5. **Edge functions (once `apps/backend/supabase/functions/` exists).**
   - Secrets read with `Deno.env.get('NAME')`, never hardcoded.
   - A function that uses the service-role key does so server-side only and never returns it or echoes it in an error.
   - No secret logged (`console.log` of headers, env, or a provider response that echoes a key).

6. **GitHub Actions workflow secrets.**
   - `.github/workflows/*.yml`: every `env:` block references `${{ secrets.X }}` or `${{ vars.X }}`, never a literal value.
   - No step `echo`es a secret or runs `set -x` with secrets in scope.
   - Deploy workflows (none yet — only `deploy.yml.example`) must use OIDC (`aws-actions/configure-aws-credentials` with `role-to-assume`) and `environment: production`; long-lived AWS keys or a Supabase access token stored as a plain secret for deploys are findings (the access token belongs to the gated `production` environment, not repo-wide secrets).

7. **Public asset leak.**
   - Search `apps/web/static/` for key shapes — `sk-`, `sk_live_`, `sb_secret_`, `Bearer `, JWTs, hex strings ≥ 32 chars.

8. **Git history pickaxe.**
   - `git log --all -S 'service_role' -S 'SERVICE_ROLE_KEY' -S 'sb_secret_' -S 'AWS_ACCESS_KEY' -S 'sk-' --source --oneline`
   - Inspect each hit's diff for whether the string is a reference (a variable name) or a value. A real value touched once is permanently exposed — Critical, "rotate the credential; the value is recoverable from git history." Report the commit and path, never the value.

9. **`.gitignore` covers the right paths.**
   - `.env`, `.env.local`, `.env.*.local`, `*.sops`, `*.sops.yaml`, `*.tfvars`, `*.tfstate*` (once `infra/` lands), `.envrc`. Any missing → Medium.

## Report

- **Critical** — a real secret in git history, a secret file (`*.sops` or plaintext) committed to this repo, a service-role key or other server credential in `apps/web` or its build output, a literal credential in `config.toml`, an AWS access key in a workflow.
- **High** — a server-only env reference in `apps/web`, a secret logged by an edge function or workflow, a deploy role whose OIDC `:sub` is missing or wildcarded.
- **Medium** — `.gitignore` missing a path, a sensitive-looking name in a committed `.env.development`.
- **Low** — undocumented env intent, missing `.env.example` entry, an overscoped key.

For each: the env-var name and file:line, and what should change. **Never paste a found key value into the report.**

## Useful starting points

- `docs/STACK.md` — what exists today (the web app reads no env vars)
- `apps/backend/supabase/config.toml` — every `env(...)` reference
- `.gitignore`, `apps/backend/supabase/.gitignore`
- `.github/workflows/deploy.yml.example` — the OIDC + `production` environment pattern
- `.pre-commit-config.yaml` + `.github/workflows/gitleaks.yml` — the gitleaks guard
- `../infra-secrets/README.md` — the estate secrets model

## Delegate to

Use the `repo-security-auditor` agent: `"Audit for server-only secrets that may have leaked into the web bundle, a public asset, the Supabase config, a GitHub Actions log, or git history. Never print a secret value."`

Read-only. Recommendations only. Identify by name + location.
