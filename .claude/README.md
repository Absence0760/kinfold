# .claude/ — Claude Code tooling

Agents, commands and hooks for this repo. They started from the `templates` repo's `base` branch and are adapted to Kinfold: a prerendered SvelteKit 5 site (`apps/web`) and a Supabase backend (`apps/backend/supabase`, described in `docs/backend.md`), with the money, privacy and fairness rules in `docs/STACK.md` § Domain rules, `docs/design.md` § Principles and `docs/backend.md` § Where each rule is enforced. Every agent names real paths and rules; a placeholder or a path that doesn't exist is a bug to fix, not a template to fill in. Surfaces that aren't built yet (edge functions, the Flutter member app, the reviewer console, partner integrations, `infra/`) are named as such, and audits report them "not applicable yet" rather than inventing files.

## How the pieces fit

1. **Gate every change**: `/check` runs the engineering agents over the diff, adding the domain reviewers when the diff reaches money or scoring; `/safe-edit` and `/safe-migration` where the change warrants them.
2. **Sweep periodically**: `/audit/*`, `/persona`, the hunt loops, and `/release-readiness` before a release.

Agents are grouped by team, one folder each under `agents/` (Claude Code discovers agents recursively, so the folder is organisation only; an agent is still invoked by its `name:`). The session doing the work builds; agents review, audit, or produce one well-defined artefact. Most are read-only; the exceptions are marked **edits**.

## Agents (`agents/`)

### `engineering/` — the per-change gate

| Agent | What it does |
|---|---|
| [`code-reviewer`](agents/engineering/code-reviewer.md) | Reviews the diff against root `CLAUDE.md`, `docs/STACK.md` § Domain rules, the migration conventions header and the static-site rules. `CLEAN` / `NEEDS_CHANGES` with file:line findings. Run by `/check`, `/safe-edit`. |
| [`test-gap-checker`](agents/engineering/test-gap-checker.md) | Maps each changed file to the Vitest, pgTAP or root-scripts test it should ship with, and the targeted command to run. |
| [`doc-hygiene-checker`](agents/engineering/doc-hygiene-checker.md) | Maps the diff to the docs it invalidated (`docs/STACK.md`, `docs/design.md`, `README.md`, `CLAUDE.md`, this file). |
| [`migration-coordinator`](agents/engineering/migration-coordinator.md) | For a Supabase migration: naming and forward-only, local reset, RLS / grants / `private` schema / `security definer` hygiene, cents-only money columns, no interest columns, types, the pgTAP tests to add. Audit mode for `/audit/migration-locks`. Run by `/safe-migration`, `/check`. |
| [`money-path-reviewer`](agents/engineering/money-path-reviewer.md) | Domain reviewer for anything that counts, schedules, allocates or routes money: no interest or late fees, integer cents, the app never holds money, pay the payee, the band rule, separate pools, lender protection. Sweep mode for `/audit/money-path`. Run by `/check` and `/safe-edit` when the diff reaches money. |
| [`scoring-fairness-reviewer`](agents/engineering/scoring-fairness-reviewer.md) | Domain reviewer for the legitimacy score, the Home Fund needs formula, review routing and refusals: evidence not popularity, no protected-class proxies, explained and versioned, AI never refuses, review integrity, auditability. Run by `/check` and `/safe-edit` when the diff touches scoring. |

### `design/` — screens

| Agent | What it does |
|---|---|
| [`ui-polisher`](agents/design/ui-polisher.md) | **Edits** in build mode: polishes one `apps/web` page or component to the tokens and primitives in `src/app.css`, with Kinfold's rules for showing money and scores. Review mode is read-only. `/polish-ui <target>`, `/polish-ui review <target>`. |

### `audit/` — periodic sweeps, read-only

| Agent | What it does |
|---|---|
| [`repo-security-auditor`](agents/audit/repo-security-auditor.md) | Seven trust boundaries (public site, member ↔ member RLS, privileged roles, evidence ↔ the members-only board, third parties, secrets, CI/OIDC). Areas `secrets`, `rls`, `auth`, `storage`, `pii`, `xss`, `deps`, `infra`, `llm`. Writes `reviews/security-<area>.md`. |
| [`compliance-auditor`](agents/audit/compliance-auditor.md) | US privacy and consumer-finance posture (CCPA/CPRA and state laws, GLBA, ECOA/Reg B, FCRA, biometric laws, E-SIGN) plus WCAG 2.2 AA: export, deletion, sub-processors, consent, regional availability, accessibility. Writes `reviews/compliance-<area>.md`. |

### `legal/`

| Agent | What it does |
|---|---|
| [`legal-researcher`](agents/legal/legal-researcher.md) | Pre-counsel research on one US law question (pool as insurance, lending and securities, AFR and gift tax, money transmission, liens, automated decisions, privacy, cooperative law). Writes `reviews/legal-<slug>.md`. Research, not legal advice. |

### `personas/` — bug-hunting points of view, read-only

Each walks the app as one kind of person and writes `reviews/<persona>.md` (git-ignored). Run through `/persona`; protocol and how to add one in [`personas/README.md`](personas/README.md).

- Generic: `new-user`, `power-user`, `admin`, `international-user`, `accessibility-user`, `integrator`, `adversary`, `data-subject`.
- Domain: `requester`, `funder`, `claim-fraudster`.

## Commands (`commands/`)

- **`check.md`** — pre-commit gate: the three engineering reviewers in parallel, plus `money-path-reviewer`, `scoring-fairness-reviewer`, `migration-coordinator` and `ui-polisher` review when the diff reaches their area. Advisory.
- **`safe-edit.md`** — coder, reviewer, fix, re-review; for money, RLS, PII, evidence, scoring and auth changes.
- **`safe-migration.md`** — any change under `apps/backend/supabase/migrations/`, with `migration-coordinator`.
- **`polish-ui.md`** — runs `ui-polisher` in build or review mode.
- **`persona.md`** — runs one, several or all personas in parallel and consolidates.
- **`release-readiness.md`** — go/no-go before a release.
- **`endpoint-inventory.md`** — writes `reviews/endpoint-inventory.md`: every table, view and RPC the Supabase API exposes by grant, plus edge functions.
- **`draft.md`** — one local branch for an ad hoc testing session; each issue the operator sends is fixed into it by a background agent; `/draft ready` runs the gate and prints the push / PR commands for the operator (Claude never pushes here).
- **`fix-issues.md`** — fixes several open GitHub issues in parallel, one worktree agent each; prints the publish commands rather than pushing.
- **Hunt and fix loops** (commit path-scoped, never push): `bug-hunt`, `ux-hunt`, `perf-hunt`, `a11y-hunt`, `coverage-hunt`, `audit-and-fix`, `improve-round`, `fix-ci`.
- **`audit/`** — focused read-only audits; index in [`commands/audit/README.md`](commands/audit/README.md). Security (`secrets`, `rls`, `auth`, `storage`, `pii-in-logs`, `xss`, `deps`, `infra`, `cost-controls`, `llm-endpoint`), money and fairness (`money-path`), privacy and compliance (`gdpr`, `data-export-completeness`, `account-deletion-completeness`, `third-party-data-flows`, `cookie-consent`, `regional-availability`, `accessibility`), health (`licenses`, `migration-locks`, `db-performance`). `all.md` runs the core sweep.

## Hooks (`hooks/`, wired in `settings.json`)

- **`git-scope-guard.py`** (PreToolUse on Bash) — blocks whole-tree git commands so sessions sharing one checkout don't sweep up each other's work; each denial names the path-scoped alternative. Tests: `git-scope-guard.test.py`.
- **`unmerged-worktree-check.sh`** (SessionStart) — warns when a branch holds commits not on `main`.

`settings.json` also carries the `permissions` block: an allow list for routine `pnpm`, read-only git and `gh` commands, and a deny list for `git commit --no-verify`, force pushes, `git reset --hard`, `sudo`, `rm -rf /` and `curl | sh`.

## Adding or changing an agent

- Put it in the team folder it belongs to; a new team gets a folder once it has more than one member.
- Name real paths, commands and rules, and cite where each rule lives (`docs/STACK.md` § Domain rules, `docs/design.md` § …, the migration header). Don't copy a rule's reasoning into the agent; point at the doc. A placeholder path is a bug.
- Say whether it is read-only, and what it writes if not.
- Update this file, any command that invokes it, and the "Available Claude tooling" section of root `CLAUDE.md` for a new slash command.
- As pieces from `docs/backend.md` § Not built yet land (edge functions, the Flutter app, the reviewer console, `infra/`), update the agents' "not built yet" notes in the same change. A Flutter app would also warrant porting the mature repos' mobile agents (`mobile-ui-polisher`).

## What lives here vs. what doesn't

- **In `.claude/`**: agent and command definitions, hooks, project-scoped `settings.json`.
- **Not in `.claude/`**: `settings.local.json` (per-user), runtime locks, anything user-specific or secret.
