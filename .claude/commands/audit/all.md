---
description: Run the core audit sweep (secrets, xss, rls, money-path, deps, infra, cost-controls) in parallel and consolidate one report
argument-hint: [security|money|deps|infra|cost] (optional area filter)
---

Run Kinfold's core audit sweep. By default, runs every audit below; with an argument, runs the named subset. Every other `/audit/<name>` (see `README.md`) runs on its own when its trigger applies.

## Areas

- **security**: `audit/secrets`, `audit/xss`, `audit/rls`
- **money**: `audit/money-path`
- **deps**: `audit/deps`
- **infra**: `audit/infra`
- **cost**: `audit/cost-controls`

`rls` and `money-path` are in the core sweep because they guard Kinfold's two worst failure modes (exposed PII, money moving wrongly) and are cheap while the schema is small: the schema is four migrations and two finance modules. If an area's surface doesn't exist yet (no `infra/`, no edge functions), its agent reports "not applicable yet" under Clean.

## Procedure

1. Pick the audits from `$ARGUMENTS`:
   - no argument → all seven
   - `security` → secrets + xss + rls
   - `money` → money-path
   - `deps` / `infra` / `cost` → that one
2. **Spawn one agent per audit, in parallel** (a single message with several Agent calls):
   - `secrets`, `xss`, `rls`: separate `repo-security-auditor` runs, each with its area as the prompt's first sentence and the command file's body as the checklist.
   - `money-path`: `money-path-reviewer` in sweep mode with `money-path.md` as the prompt.
   - `deps`, `infra`, `cost-controls`: a `general-purpose` agent each, with the command file's body as the prompt.
3. **Consolidate** into one report grouped by severity (Critical / High / Medium / Low), then by audit. For each finding: file:line, what's wrong, the audit that found it.
4. **Recommend a fix order**, but apply nothing without explicit confirmation. Critical/High: "fix before next deploy". Medium/Low can be batched into tracked issues (confirm before creating them).

## Output shape

```
# Audit report — <date>

## Critical (N)
- [audit/<area>] file:line — <one-line>

## High (N)
## Medium (N)
## Low (N)

## Clean (no findings)
- [audit/<area>] no issues (or: not applicable yet — <surface> doesn't exist)

## Recommended order
1. ...
```

Persist the consolidated report to `reviews/audit-all.md` (git-ignored); each sub-audit also updates its own `reviews/audit-<name>.md`.

## Notes

- Read-only. The report is the deliverable.
- List clean audits explicitly; it makes the next run's regressions easy to spot.
- For a change confined to one surface, the matching single audit is usually enough; the full sweep is for release prep and monthly drift checks.
