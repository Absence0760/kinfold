---
description: Collect the fixes from one ad hoc testing session on one branch, fix each issue the operator sends into it, and hand it over ready for a draft PR. `/draft [topic]` opens, `/draft resume <branch>` picks one up again, `/draft ready` finishes. Claude never pushes; the operator publishes.
argument-hint: "[topic] | resume <branch> | ready"
---

The operator is testing Kinfold by hand and will send issues one at a time.
Every fix lands on **one** branch in its own worktree. Mode is `$ARGUMENTS`:

- empty or a topic → **Open**
- `resume <branch>` → **Resume**
- `ready` → **Ready**

## Publishing is the operator's call

Root `CLAUDE.md` § Working alongside other Claude sessions: **never `git push`
in this repo.** So this command stops short of GitHub. It builds the branch
and the PR body locally; wherever a mature repo's `/draft` would push or run
`gh pr create`, this one prints the one-line command for the operator to run
and carries on. Never push, open, edit or mark a PR yourself.

## Open

1. Branch in a worktree off the current `main` (CLAUDE.md § Working alongside
   other Claude sessions; `settings.json` sets `worktree.baseRef: head`):
   ```
   git worktree add ../kinfold-adhoc-<slug> -b fix/adhoc-<slug> main
   ```
   `<slug>` is the topic, or today's date (`YYYY-MM-DD`) when there is none.
   If `git log origin/main..main` is non-empty, say so: the branch will carry
   the operator's unpushed commits until they push `main`.
2. Install deps in the worktree once: `pnpm -C ../kinfold-adhoc-<slug> install`.
3. Start a PR body file at `../kinfold-adhoc-<slug>.pr.md` (outside the tree,
   so it is never committed) from `.github/pull_request_template.md`: the
   Summary says it collects fixes from ad hoc testing, and Changes starts as
   `_(none yet)_`.
4. Reply with the worktree path, the branch, and these lines for whenever the
   operator wants the draft PR on GitHub:
   ```
   git -C ../kinfold-adhoc-<slug> push -u origin fix/adhoc-<slug>
   ```
   ```
   gh pr create --draft --base main --head fix/adhoc-<slug> --title "fix: ad hoc testing fixes (<topic>)" --body-file ../kinfold-adhoc-<slug>.pr.md
   ```
   Then wait for the first issue.

## Resume

Find the worktree with `git worktree list` (or add one for the branch). Merge
`main` into it if it fell behind (merge, never rebase: the operator may have
pushed it). Re-read the `.pr.md` body file, then carry on from **Each issue**.

## Each issue

The main session stays free to talk: it triages each issue and hands the fix
to a **background subagent** (the Agent tool, `run_in_background`), one per
issue, then goes back to the operator. It never fixes an issue inline, except
a one-line change it has already diagnosed.

For every issue the operator sends, until they say ready:

1. **Triage (main session).** Restate it in one line. Ask only if two readings
   would build different things; otherwise pick the reasonable one and say
   which. Dig only as far as you need to brief the agent: the page or table,
   the likely files, what you've ruled out.
2. **Dispatch.** Start a background `general-purpose` subagent with a
   self-contained brief: the issue in the operator's words (screenshots
   described, since the agent can't see them), what you've learned, the
   worktree path and branch, and these rules:
   - Work only in the worktree; never touch `main` or the main checkout.
   - **Reproduce, then fix the cause** (CLAUDE.md § Fix bugs at the source),
     with a failing test first where one fits. Route by what it touches:
     `/safe-migration` for anything under `apps/backend/supabase/migrations/`;
     `/safe-edit` for RLS, grants, the `private` schema, identity, evidence
     storage, scoring, or any money path (STACK.md § Domain rules); the
     `money-path-reviewer` for amounts, schedules, allocation or payees; the
     `scoring-fairness-reviewer` for anything that computes or routes on a
     legitimacy score.
   - **Tests and docs in the same commit** (CLAUDE.md § Every code change
     updates tests + docs). Run only what it touched: `pnpm check`,
     `pnpm -C apps/web exec vitest run <file>` for web logic, and
     `pnpm test:backend:db` for SQL (pgTAP under `apps/backend/supabase/tests/`).
   - **Agents share the worktree's local Supabase stack** (ports
     54721-54729), so two DB runs at once break each other. Take the
     worktree's lock around any `pnpm dev:db:reset` or `pnpm test:backend:db`
     and drop it straight after:
     `until mkdir "$(git rev-parse --git-dir)/draft-test.lock" 2>/dev/null; do sleep 5; done; <command>; rmdir "$(git rev-parse --git-dir)/draft-test.lock"`.
     Vitest and svelte-check don't need it. Commit under the same lock too:
     the gitleaks pre-commit hook stashes unstaged changes while it runs, so
     another agent's edit in that window can be lost.
   - **One path-scoped commit**:
     `git commit -m "fix(<area>): <what>" -- <paths>`. No `Co-Authored-By` or
     generated-by trailer. **Never push.** If git reports `index.lock`, wait
     and retry.
   - Don't edit the PR body file; report back the cause, the fix, the commit
     hash, the files and the commands run, or why it stopped.
   - If the fix needs a product decision (anything `docs/design.md` §
     Open questions leaves open), counsel, or an operator action, stop and
     report rather than guess.
3. **Run agents in parallel when their issues touch different areas**; when
   two would edit the same files, queue the second until the first reports.
   Tell the operator in one line what was dispatched, then take the next
   issue.
4. **When an agent reports (main session):** check its commit is on the branch
   (`git -C <worktree> log --oneline main..HEAD`) and its diff is what was
   asked. Add one bullet under Changes in the `.pr.md` body file (only the
   main session edits it, so updates don't race). Then tell the operator in
   two or three lines: the cause, the fix, the commit. Relay a stop or a
   question as it is.

If an issue turns out too large or risky for this branch (a migration that
reshapes money tables, a scoring-policy question), say so and offer a separate
GitHub issue rather than folding it in (confirm before creating one). Don't let
it drop (CLAUDE.md § Fix the root cause).

## Ready

Only when the operator says so:

1. Wait for every dispatched agent to report, then merge `main` if the branch
   fell behind.
2. `pnpm check && pnpm test`, plus `pnpm test:backend:db` if the branch touched
   SQL, and `pnpm build:web` if it touched `apps/web` (the site is
   prerendered; a build failure is a real defect).
3. `/check` over the whole branch (`git diff main...HEAD`). Apply the findings
   you agree with; say why for the rest in the PR body file.
4. Pick a title that names what the fixes are about, as a conventional commit
   (`fix(<scope>): <subject>`, lowercase, no trailing period; CI's
   `.github/workflows/pr-title-lint.yml`). No scope when the fixes span areas.
5. Report the list of fixes, anything the operator needs to decide, and the
   commands to publish (push, then `gh pr create` with the final title and
   `--body-file`, or `gh pr edit` + `gh pr ready` if they already opened the
   draft). Don't merge; that's the operator's call.
