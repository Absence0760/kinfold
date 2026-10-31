---
description: Audit Kinfold's infrastructure-as-code once infra/ exists (S3 + CloudFront for the static site, GitHub OIDC deploy role, budget) and the hosted Supabase project's config — IAM least-privilege, encryption, drift hygiene, cost guardrails. Reports "not applicable yet" until infra/ lands.
---

Audit the infrastructure that hosts Kinfold.

## Current state — check this first

Kinfold has **no `infra/` directory yet**. `docs/STACK.md` says `apps/web` builds to `apps/web/build/` and is deployable to S3 + CloudFront as-is, and `.github/workflows/deploy.yml.example` shows the gated deploy pattern, but no Terraform or deploy workflow has been written. The backend is Supabase (`apps/backend/supabase`), which runs locally from `config.toml` and will run on a hosted Supabase project in production.

So:

1. `ls infra/ 2>/dev/null` and `ls .github/workflows/deploy*.yml`. If neither exists, report **"not applicable yet — no infra/ and no deploy workflow"**, then run only the "Pre-infra checks" below and stop.
2. If `infra/` exists, run the full checklist. Discover the actual files (`ls infra/*.tf`) rather than assuming names.

## Pre-infra checks (always)

- `.github/workflows/deploy.yml.example` is still an `.example` (not accidentally live) or, if a real deploy workflow exists, every deploy job declares `environment: production` and authenticates with OIDC (`role-to-assume`), never static AWS keys (root `CLAUDE.md` § Repo-wide hard rules: CI auth, Deploys go through the `production` GitHub environment).
- No `*.tfvars`, `*.tfstate*` or `*.sops*` file is tracked (`git ls-files`).
- `apps/backend/supabase/config.toml` is local-dev config; note any setting that would be unsafe if copied to the hosted project as-is (e.g. `[auth] enable_confirmations = false`, wildcard redirect URLs, `[api]` exposing the `private` schema). These are Medium findings against the future production config, not against local dev.

## Full checklist (once `infra/` exists)

1. **State backend.** `backend "s3"` with `encrypt = true` and locking (`use_lockfile = true` on Terraform ≥ 1.10 is the simpler modern choice). The state bucket has versioning and Public Access Block. Bucket and key names follow the estate pattern (`<project>-tfstate-<account-id>`), created by the `templates` repo's `new-project-account.sh` baseline, not by this module.

2. **OIDC trust policy.** The deploy role's trust policy has `StringEquals` on `token.actions.githubusercontent.com:aud = "sts.amazonaws.com"` and `:sub = "repo:<owner>/kinfold:environment:production"`. A wildcarded or missing `:sub` is the "fork PR can assume your role" footgun — Critical. Attached permissions are scoped to the site bucket ARN and `cloudfront:CreateInvalidation` on the one distribution; no `iam:*`, `sts:AssumeRole`, or `*` resources.

3. **S3 site bucket.** Public Access Block all four `true`; versioning on; SSE on; bucket policy grants only `cloudfront.amazonaws.com` conditioned on `AWS:SourceArn`; no ACLs; lifecycle expiring non-current versions.

4. **CloudFront.** `redirect-to-https`; `minimum_protocol_version` `TLSv1.2_2021` or stricter; Origin Access Control (not legacy OAI); a response-headers policy on every behavior with HSTS (≥ 1 year, `include_subdomains`, `preload`), `nosniff`, `strict-origin-when-cross-origin`, `frame_options = DENY`. CSP: the marketing site is static first-party content, so a strict CSP is cheap — absent is Low today and becomes Medium once member content renders (`/audit/xss`). Every route is prerendered (`adapter-static`), so the 404 mapping should serve the built `404.html` with a real 404 status, not rewrite to 200. `price_class = "PriceClass_100"` (US audience) unless justified.

5. **DNS and certificates.** ACM cert in `us-east-1` for CloudFront; Route 53 records in the zone the project's AWS account owns (estate map: `~/github/templates/docs/estate-map.md`). No cross-account write access beyond the documented delegation.

6. **Secrets handling.** No secret in `.tf` or committed tfvars. Secret values come from `../infra-secrets/kinfold/` via the sops provider (`data "sops_file"`) or decrypt-to-tfvars; variables holding them are `sensitive = true`; no output exposes one unmarked. Do not decrypt anything to check — verify by structure. The SOPS KMS key (`alias/kinfold-sops`) is provisioned out-of-band by `infra-secrets/bin/sops-init.sh`; no `.tf` file should manage it.

7. **Hosted Supabase.** If Terraform manages the Supabase project (the `supabase/supabase` provider) or a deploy workflow pushes migrations: the access token comes from the gated `production` environment, not a repo-wide secret; migrations are applied with `supabase db push` from CI only after review; the hosted project's auth settings match the reviewed `config.toml` intent (email confirmations on, redirect allowlist exact, spend cap on).

8. **Pinning.** `required_version` and pinned `required_providers` (`~> X.Y` or exact); `.terraform.lock.hcl` committed.

9. **Budget.** `aws_budgets_budget` with `ACTUAL > 50%`, `ACTUAL > 100%`, `FORECASTED > 100%` notifications to a non-empty subscriber list.

10. **Drift hygiene.** Every `lifecycle { ignore_changes = [...] }` is there because CI legitimately mutates the field, and the list is minimal.

11. **Tagging.** Every taggable resource carries at least `project = "kinfold"` and `managed_by = "terraform"`.

## Report

- **Critical** — OIDC trust too broad, a public bucket without OAC, a committed secret or state file, an IAM role with `*`, a live deploy job without `environment: production`.
- **High** — versioning or PAB off, non-HTTPS serving, overscoped deploy permissions, no AWS budget.
- **Medium** — missing security headers, log retention infinite, missing tags, drift-prone resources, unsafe settings that would carry from `config.toml` to production.
- **Low** — loose version pins, undocumented `lifecycle` choices, no CSP on the static site.

For each finding: file:line + the concrete change. If `infra/` doesn't exist, the report is the pre-infra checks plus one line: "not applicable yet".

## Useful starting points

- `docs/STACK.md` — the intended hosting shape
- `.github/workflows/deploy.yml.example` + `.github/workflows/README-ci-gate.md` — the gated deploy pattern
- `apps/backend/supabase/config.toml`
- `~/github/project-mgmt/docs/runbooks.md` — how project AWS accounts are created and baselined (read-only reference)

## Delegate to

`general-purpose` agent with this file as the prompt body.

Read-only. Findings only. Don't run `terraform plan` / `apply` or any Supabase CLI command that reaches the hosted project.
