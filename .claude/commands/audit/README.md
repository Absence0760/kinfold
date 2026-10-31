# Audit commands

Focused, read-only sweeps over one surface of Kinfold: a prerendered SvelteKit site (`apps/web`), a Supabase backend (`apps/backend/supabase`: Postgres 17 with RLS, pgTAP tests, Deno edge functions to build; see `docs/backend.md`), and a domain where mistakes move money, expose identity or treat members unfairly. Each command reports findings; none applies a fix without explicit confirmation.

Invoke as `/audit/<name>`. Most persist their findings to `reviews/audit-<name>.md` (git-ignored; see `reviews/README.md`) and update that file in place on re-runs.

Several audits target surfaces that don't exist yet (edge functions including the LLM scorer, Terraform, partner integrations; see `docs/backend.md` § Not built yet). They say "not applicable yet" for those parts and list what the first change there must meet, rather than inventing findings.

## Index

### Security

| Command | What it checks | Agent |
|---|---|---|
| [/audit/secrets](secrets.md) | SOPS / `infra-secrets` posture, plaintext in git history, server-only values in the static bundle, Actions secret hygiene | `repo-security-auditor` |
| [/audit/xss](xss.md) | Svelte `{@html}`, dynamic `href`/`src`, member-supplied text on the members-only board | `repo-security-auditor` |
| [/audit/auth](auth.md) | Route and function gating, identity derived from the session, never from the request | `repo-security-auditor` |
| [/audit/rls](rls.md) | RLS on every table, default grants revoked, the `private` schema, `security definer` functions, positive-control pgTAP tests | `repo-security-auditor` |
| [/audit/storage](storage.md) | Evidence buckets: private originals, redacted copies public only after member confirmation, paths, signed URLs, EXIF | `repo-security-auditor` |
| [/audit/llm-endpoint](llm-endpoint.md) | The scoring model's endpoint: prompt injection via evidence, PII in prompts, cost and abuse limits | `repo-security-auditor` |

### Money and fairness

| Command | What it checks | Agent |
|---|---|---|
| [/audit/money-path](money-path.md) | No interest or late fees, integer cents, app never holds money, pay the payee, pools separate, allocation follows the published band rule | `money-path-reviewer` |

Scoring fairness is reviewed per change by `scoring-fairness-reviewer` through `/check`; the yearly bias audit itself (design.md § Legitimacy score) is an operator process, not a command.

### Privacy and compliance

| Command | What it checks | Agent |
|---|---|---|
| [/audit/gdpr](gdpr.md) | Data-protection posture (US privacy law first: CCPA/CPRA and state laws; GDPR if EU members are ever accepted) | `compliance-auditor` |
| [/audit/pii-in-logs](pii-in-logs.md) | Identity, earnings, hardship, loan and evidence data in logs, error bodies or an external sink | `compliance-auditor` |
| [/audit/data-export-completeness](data-export-completeness.md) | A member's export covers everything held about them | `compliance-auditor` |
| [/audit/account-deletion-completeness](account-deletion-completeness.md) | Deletion reaches every table and object, while keeping records the law requires | `compliance-auditor` |
| [/audit/cookie-consent](cookie-consent.md) | Cookies and trackers on the public site versus consent | `compliance-auditor` |
| [/audit/third-party-data-flows](third-party-data-flows.md) | The sub-processor map (KYC, bank link, payment partner, scoring model, redaction) | `compliance-auditor` |
| [/audit/regional-availability](regional-availability.md) | State-by-state: where each product can lawfully run versus where signup lets people in and what the site claims | `compliance-auditor` |
| [/audit/licenses](licenses.md) | Dependency licenses: copyleft, unknown, missing attribution | `compliance-auditor` |
| [/audit/accessibility](accessibility.md) | WCAG 2.2 AA on the public site and member flows | `compliance-auditor` |

### Health

| Command | What it checks | Agent |
|---|---|---|
| [/audit/deps](deps.md) | `pnpm audit`, Dependabot coverage, Actions pinning, override hygiene | `general-purpose` |
| [/audit/infra](infra.md) | Terraform and hosting (S3 + CloudFront, OIDC, headers) once `infra/` exists | `general-purpose` |
| [/audit/cost-controls](cost-controls.md) | Denial-of-wallet: scoring-model spend, storage, rate limits, budget alarms | `general-purpose` |
| [/audit/migration-locks](migration-locks.md) | Online-DDL safety of migrations against a populated database | `migration-coordinator` (audit mode) |
| [/audit/db-performance](db-performance.md) | Indexes (including RLS predicate and FK columns), composite order, N+1, scan-at-scale | `general-purpose` |

### Dispatcher

| Command | What it does |
|---|---|
| [/audit/all](all.md) | Runs the core sweep in parallel and consolidates one report. Optional area filter. |

## Conventions

- **Read-only by default.** The deliverable is a findings report, not a diff. Writing its own `reviews/audit-<name>.md` is the one allowed write.
- **Severity**: Critical / High / Medium / Low.
- **Self-contained.** Each command runs from a fresh session with no prior context.
- **Cite the rule.** Findings tie back to `docs/STACK.md` § Domain rules, `docs/design.md` § Principles / Fraud-proofing / Risks and safeguards, the migration conventions at the top of `apps/backend/supabase/migrations/20261030120000_members.sql`, or root `CLAUDE.md`.
- **Agents live in team folders** (`.claude/agents/audit/`, `.claude/agents/engineering/`); they're invoked by `name:`, the folder is organisation only.
- **Legal questions** an audit raises go to the `legal-researcher` agent (`.claude/agents/legal/`), never a guess. Research is not legal advice.

## Diff-time enforcement (complementary)

- [/check](../check.md): pre-commit gate over the working diff (`code-reviewer`, `test-gap-checker`, `doc-hygiene-checker`, plus `money-path-reviewer`, `scoring-fairness-reviewer` and `migration-coordinator` when the diff reaches their surface).
- [/safe-edit](../safe-edit.md): coder and reviewer loop for RLS, identity, evidence, scoring and money changes.
- [/safe-migration](../safe-migration.md): any change under `apps/backend/supabase/migrations/`.
- [/release-readiness](../release-readiness.md): pre-release gate.

## When to run

- **Before a release**: `/audit/all`, fix Critical/High, then `/release-readiness`.
- **After a migration lands**: `/audit/rls`; `/audit/migration-locks` once production has data.
- **After touching finance, allocation, fund settings or payouts**: `/audit/money-path`.
- **When evidence upload or redaction changes**: `/audit/storage` and `/audit/pii-in-logs`.
- **When site copy about cover, the pool or the Home Fund changes**: `/audit/regional-availability`.
- **After a dependency major bump**: `/audit/deps` and `/audit/licenses`.
- **Monthly**: `/audit/all`. The weekly `.github/workflows/audit.yml` covers `pnpm audit`; `/audit/all` adds the rest.
