---
description: Polish the UI/UX of a single page or component in apps/web to Kinfold's quality bar — clear hierarchy, plain-language money and terms (every term fits on one screen), mobile-first stacking, the design tokens in src/app.css in light and dark. `/polish-ui review <target>` reports without editing. Delegates to the `ui-polisher` agent.
argument-hint: <page-route or component path>
---

Polish the UI/UX of `$ARGUMENTS` using the `ui-polisher` agent (`.claude/agents/design/ui-polisher.md`). If `$ARGUMENTS` starts with `review`, run the agent in review mode: it reports findings and edits nothing (this is also how `/check` calls it on a UI diff).

## When to use this command

**Right fit:**

- A page where the hierarchy is muddled — the most important thing isn't at the top, or chrome / boilerplate competes with content for the first viewport.
- A page whose archetype doesn't match its data — flat prose where a `<dl>` would surface structure (a request's amount, payee, score and reasons), a 3-column grid for two items, a long unstructured policy doc.
- A page that doesn't collapse cleanly on mobile (members post requests in a stressful moment, often from a phone — two-column desktop layouts must stack, touch targets must be ≥44px).
- A page leaking raw ISO dates, raw cents or unformatted amounts (money goes through `apps/web/src/lib/core/format.ts`), arbitrary hex colors that should be tokens from `apps/web/src/app.css`, or a colour that only works in one of the light / dark schemes.
- A component used in multiple places (`SiteNav`, `SiteFooter`, the request cards in `RequestBoard`) where consistency across surfaces matters.

**Wrong fit — tell the user and stop:**

- A purely-functional admin / settings / dev page with no real-estate or scanability problem.
- Money or scoring logic dressed as a UI change — the loan maths behind `SavingsCalculator.svelte` (`src/lib/finance/`), the pool allocation behind `RequestBoard.svelte` (`src/lib/requests/allocation.ts`), how a score or its reasons are computed. Those need `/safe-edit` (with `money-path-reviewer` / `scoring-fairness-reviewer`), not polish. Polishing how an amount or score is *shown* is in scope; changing what it *is* is not.
- A request that's really a feature, not a polish — "add an FAQ section to the home page" needs a content plan, not the polish agent. Copy that makes a promise ("we'll pay your claim", any mention of interest, returns or guarantees) is a legal question first (`docs/design.md` § Legal reality) — route it to `legal-researcher`, don't polish it in.
- An asks-for-everything sweep ("polish all the pages"). Pick one and tell the user to invoke this command again for the next.

## Resolving the target

`$ARGUMENTS` can be:

- A **route slug** — resolves to `apps/web/src/routes/<slug>/+page.svelte`. The home page (today the only route) is `apps/web/src/routes/+page.svelte`; the shell is `apps/web/src/routes/+layout.svelte`. Every route is prerendered (`adapter-static`), so nothing in a page may depend on a request-time server.
- A **file path** (`apps/web/src/lib/landing/Hero.svelte`) — used as-is.
- A **component name** (`Hero`, `RequestBoard`, `SavingsCalculator`) — resolve via `find apps/web/src/lib -name "<name>.svelte"`.

If the argument is empty or "audit", list the candidate pages with a one-line "why this one matters most right now" and ask the user to pick. Don't blanket-sweep.

## The flow

1. **Pre-flight:**
   - Confirm the target file exists. If not, stop and report.
   - Confirm `pnpm check` passes on the working tree before you start — if it's already failing, something else is broken; fix that first.
   - The repo convention is "don't run the dev server to visually verify UI/frontend changes" (per `CLAUDE.md`). The agent does not take screenshots; the operator reviews the page in their own browser session. No pre-flight check on a running dev server.

2. **Resolve target → invoke the agent:**

   Spawn the `ui-polisher` agent with a prompt like:

   > "Polish the UI/UX of `<resolved file path>`. The user's stated intent was: `<the original argument string>`. Follow your agent spec: audit, plan, edit, verify (`pnpm check`, `pnpm test`), report. Do not commit. Do not change the finance or allocation logic a component renders."

   For `review`, prompt: "review: `<resolved file path>`" — the agent reports and edits nothing.

   The agent's spec covers the design language and the type-check. Trust it.

3. **Relay the agent's report.** When it returns, surface:

   - The list of files changed (run `git diff --stat` to confirm matches).
   - Any test the agent added or changed (Vitest beside the module) so the user can sanity-check it.
   - The "Notes for the human" section verbatim — including the agent's request that the user run `pnpm dev:run:web` (http://localhost:7790) and review the page visually in both light and dark schemes.

4. **Wait for the user's call on the commit.** Do not pre-stage or pre-commit. When the user says yes:

   - Commit path-scoped: `git commit -m "…" -- <changed files>` (the scope guard blocks `git add -A` and bare `git commit`; other sessions share this checkout). Never push.
   - Commit message follows the conventional-commit style in `git log --oneline` (e.g. `feat(web): …` / `style(web): …`). **No `Co-Authored-By` / "Generated with Claude Code" / robot-emoji footers** — the user-level rule in `~/.claude/CLAUDE.md` wins.
   - Example: `git commit -m "style(web): <one-liner>" -m "<3–5 line body explaining what archetype + which patterns applied + why>" -- <paths>`.

## Cost reality

This command costs more than a normal edit — a full type-check, the unit tests, an agent context. Don't burn it on a 5-pixel padding tweak — for that, the user edits directly. The command earns its cost on archetype-level or hierarchy-level changes (a flat request list that should be a card grid, a run-on paragraph of loan terms that should be a `<dl>`, a score shown without its reasons, a disclosure that must be conspicuous, etc.).

## What this command does NOT replace

- `/check` for a pre-commit gate (code-review + test-gap + doc-hygiene).
- `/safe-edit` for money, scoring or data-protection changes (`src/lib/finance/`, `src/lib/requests/allocation.ts`, evidence redaction, anything in `docs/STACK.md` § Domain rules).
- `/audit/*` for periodic broad sweeps (secrets, XSS, deps, accessibility, …).
- Visual verification. The operator runs `pnpm dev:run:web` and reviews the page themselves — that's the repo convention.

## Tone

Don't narrate the agent's internal steps. The user sees:

- A one-sentence "Resolving target → `<path>`. Spawning the polisher."
- The agent's structured report (audit findings + changes + verification + notes), relayed.
- A "Want me to commit?" question with the suggested commit message.
