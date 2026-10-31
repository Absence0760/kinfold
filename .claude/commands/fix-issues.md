---
description: Fix N open GitHub issues in parallel, one worktree-isolated agent per issue, each fixing at the root with tests + docs per Kinfold's domain rules, then handing back a verified local branch per issue. Defaults to 5. Claude never pushes or opens PRs; it prints the commands for the operator.
argument-hint: "[count | issue numbers | label filter] [single-branch] e.g. \"5\", \"#12 #19\", \"label:bug 3\", \"single-branch\". Omit to fix 5 open issues."
---

Fix open GitHub issues in this repo using **parallel agents, one per issue**.
Scope: `$ARGUMENTS` (if empty, fix **5** open issues, each on its own branch).

This is a **fan-out fix** loop: **select → confirm → fan out (one worktree per
issue) → each agent fixes + tests → verify → hand over → report.**

## Publishing is the operator's call

Root `CLAUDE.md` § Working alongside other Claude sessions: **never `git push`
in this repo.** This command ends with verified local branches plus, for each,
the one-line `git push` and `gh pr create` commands for the operator. It never
pushes, opens, merges or comments on a PR or issue itself.

## Why worktrees are mandatory here

The scope guard (`.claude/hooks/git-scope-guard.py`) is path-granular, not
hunk-granular: several agents editing the same file in one shared checkout
would capture each other's edits in path-scoped commits. So **every fixer
agent runs with `isolation: "worktree"`**: its own tree, index and branch.
Never fan file-editing agents out into the shared checkout.

## The base rule

`.claude/settings.json` sets `worktree.baseRef: "head"`, so a fresh worktree
starts from local HEAD, which may hold the operator's **unpushed** commits. A
branch built on those would publish them when pushed. So each agent's first
git action is:

```
git fetch origin && git checkout -B fix/issue-<N> origin/main
```

At selection time also check `git log origin/main..main --oneline`: if an issue
is already fixed by an unpushed local commit, **drop it** and tell the operator
the fix exists and just needs pushing.

## When to use this command

**Right fit:** several independent, well-scoped, code-fixable issues (concrete
bugs or small enhancements with an obvious root-cause fix).

**Wrong fit (drop the issue from the batch):**
- Issues that need a **product or policy decision** first: anything
  `docs/design.md` § Open questions leaves open, the scoring threshold or band
  rules, subscription formula, which partner or state.
- Issues that need **counsel** (`docs/design.md` § Legal reality): use the
  `legal-researcher` agent and stop.
- Discussions, questions, duplicates, or a feature epic (use `/safe-edit`).

## The loop

### 1. Select the issues (orchestrator, not parallel)

Parse `$ARGUMENTS`: a bare number is how many (default **5**); explicit
`#N` numbers fix exactly those; `label:<x>` restricts the pool; `single-branch`
consolidates the fixes onto one branch (step 5).

```
gh issue list --state open --limit 40 --json number,title,labels,body
```

**Exclude any issue that already has a fixing PR.** `gh issue list` doesn't
show linked PRs, so query GitHub's closing references (a bare mention isn't
one):

```
gh api graphql -f query='
query($owner:String!,$repo:String!){
  repository(owner:$owner,name:$repo){
    issues(states:OPEN, first:40, orderBy:{field:CREATED_AT, direction:DESC}){
      nodes{ number
        closedByPullRequestsReferences(first:5, includeClosedPrs:true){ nodes{ number state url } } }
    }
  }
}' -f owner=<OWNER> -f repo=<REPO>
```

`<OWNER>`/`<REPO>` from `gh repo view --json owner,name`. Then:

- **Skip** if any linked PR is `OPEN` (fix in flight) or `MERGED` (fixed, issue
  just not closed).
- **Skip** if fixed by an unpushed local commit; report "fixed locally, needs
  push".
- **Don't skip** on a linked PR that is only `CLOSED` (abandoned); say you're
  re-attempting it.
- With explicit issue numbers, still run the check and warn before duplicating.

From the survivors, keep only issues that pass the **actionable bar**: a
concrete, bounded, code-level fix with a clear root cause. Prefer `bug` over
`enhancement`. If fewer than requested survive, take what qualifies and say so.

### 2. Confirm before spending (checkpoint)

Print the selected issue numbers, titles, one-line fix intent each, and the
branch strategy, and get a go-ahead. Explicit issue numbers count as the
go-ahead.

If any fix needs the local database, run `pnpm dev:db:up` **once from the
orchestrator** before fanning out. The Supabase stack (ports 54721-54729) is
shared by every worktree; agents must not stop or restart it, and only one
agent at a time may run `pnpm dev:db:reset` or `pnpm test:backend:db` (they
rebuild the same database). Tell agents to take a lock around those:
`until mkdir /tmp/kinfold-db.lock 2>/dev/null; do sleep 5; done; <command>; rmdir /tmp/kinfold-db.lock`.

### 3. Fan out: one worktree-isolated agent per issue (one message)

Spawn every fixer in a single message so they run concurrently: each a
`general-purpose` agent with `isolation: "worktree"`, scoped to exactly one
issue, with this contract:

> You are fixing GitHub issue **#N** in an isolated git worktree of Kinfold.
> Work only on this issue.
>
> 1. **Re-root first:** `git fetch origin && git checkout -B fix/issue-N origin/main`.
> 2. **Bootstrap:** `pnpm install` (node_modules don't carry into a worktree).
>    The local Supabase stack is already up and shared: never stop it; take
>    the DB lock (given above) around `pnpm dev:db:reset` / `pnpm test:backend:db`.
> 3. **Reproduce and locate.** Find the root cause; cite `file:line`. If you
>    can't reproduce, or the fix needs a product, policy or legal decision,
>    stop and report instead of guessing.
> 4. **Fix at the root** (CLAUDE.md § Fix bugs at the source): no sleeps,
>    retries, loosened assertions or swallowed errors.
> 5. **Honour the domain rules** (`docs/STACK.md` § Domain rules): no interest
>    or late fees in any code path, schedules sum to the principal; money is
>    integer cents (`bigint` in SQL, integer arithmetic in TS), never floats;
>    the app never holds member money; request money goes to the payee, never
>    the requester; the protection, Home Fund and lending data stay separate;
>    a score never refuses, only a recorded human decision does, and every
>    score keeps model version, inputs and reasons; shared evidence is
>    redacted and confirmed, originals private; identity, income, hardship
>    and loan data are PII and stay out of logs and public tables. Schema
>    work follows the migration conventions at the top of
>    `apps/backend/supabase/migrations/20261030120000_members.sql` (RLS on,
>    default grants revoked, `private` schema, `search_path = ''` on definer
>    functions) with `/safe-migration` rigour.
> 6. **Tests in the same commit as the fix**: a Vitest case beside the module
>    for `apps/web`, a pgTAP case under `apps/backend/supabase/tests/` for SQL.
>    It must fail before and pass after. If genuinely untestable, say why.
> 7. **Docs in the same commit**: `docs/STACK.md`, `docs/design.md` or the
>    relevant doc the change touches.
> 8. **Commit path-scoped** (`git commit -m "…" -- <paths>`), conventional
>    messages, no AI attribution of any kind. **Do not push.**
> 9. Run `pnpm check`, the targeted tests, and `pnpm build:web` if `apps/web`
>    changed. Report pass/fail honestly.
> 10. **Report back:** branch, commits, files, test results, and a proposed PR
>     title (`type(scope): subject`, lowercase, no period;
>     `.github/workflows/pr-title-lint.yml` rejects anything else) and body
>     ending `Fixes #N`.

### 4. Verify each agent's work

Don't trust a "done". For each fix: the branch is rooted on `origin/main`
(`git merge-base --is-ancestor origin/main fix/issue-N` and no commits from
`origin/main..main`), the root cause is real, the test fails before and passes
after, docs were updated, and nothing unrelated was swept in. For a fix that
touches RLS, grants, identity, evidence storage, scoring or any money path, run
`/check` over the branch diff; it brings in `money-path-reviewer` and
`scoring-fairness-reviewer` where they apply. Bounce anything that masked the
bug back to its agent (via `SendMessage`, keeping its worktree context).

### 5. Hand over

**Re-check the closing references for each issue** right before handing over;
another session may have opened a fix while the fan-out ran. Drop and report a
collision.

- **Default, one branch per issue:** give the operator, per issue,
  ```
  git push -u origin fix/issue-<N>
  ```
  ```
  gh pr create --base main --head fix/issue-<N> --title "<title>" --body-file <path>
  ```
  writing each PR body to a file under the scratchpad (never into the repo).
- **`single-branch`:** create `fix/issues-<date>` off `origin/main` and
  cherry-pick each worktree branch's commits onto it in turn (linear, no merge
  commits), resolve conflicts, rerun the checks, and give one push + one
  `gh pr create` whose body lists `Fixes #N` for each issue. Only when asked.

### 6. Report

One table: issue # → branch → test result → reviewer verdict. Then the publish
commands. Note each dropped issue and why. Remove finished worktrees
(`git worktree remove`) once their branch is verified; keep the branches until
their PRs merge (the SessionStart unmerged-worktree warning will name them,
which is expected).

## Guardrails

- **Never re-fix** an issue with an open or merged fixing PR, or an unpushed
  local fix (checked at step 1 and again at step 5).
- **Branches build on `origin/main` only.**
- **Fix only what the issue describes.** No drive-by refactors.
- **Never push, open, or merge.** The operator publishes.
- **A dropped issue is a fine outcome.** "3 of 5 were actionable; 2 need a
  decision" beats shipping two guesses.
