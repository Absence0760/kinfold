---
description: WCAG 2.2 AA + ADA pass on the Kinfold web app (apps/web), light and dark schemes
---

Audit accessibility across every user-facing surface. Kinfold has one today: `apps/web`, the prerendered SvelteKit 5 marketing / preview site. The Flutter member app (`apps/mobile`) and the reviewer console are planned (`docs/STACK.md` § Clients); when they land, add their checks here (Semantics labels, dynamic type, 44×44 targets, reduced motion).

## Goal

ADA Title III case law, the DOJ's 2024 Title II rule and state laws converge on WCAG 2.2 AA. For Kinfold accessibility is also mission: members post requests in a crisis, often on a phone, sometimes with low vision, a screen reader, or limited English and financial literacy. Money terms must be understandable — "every term fits on one screen" (`docs/design.md` § Principles 6). Find every place the site misses the bar.

## What to check

1. **Semantic HTML.** `<button>` vs clickable `<div>`; links that navigate are `<a>`. Icon-only controls have an accessible name. Walk `apps/web/src/routes/` and `apps/web/src/lib/landing/`.
2. **Headings and landmarks.** One `<h1>` per page, no skipped levels; `<header>`, `<nav>` (`SiteNav.svelte`), `<main>`, `<footer>` (`SiteFooter.svelte`). A skip link at the top of `apps/web/src/routes/+layout.svelte`.
3. **Colour contrast.** ≥ 4.5:1 text, ≥ 3:1 UI components and focus indicators — in **both** light and dark schemes (tokens in `apps/web/src/app.css` switch on `prefers-color-scheme`). Score bands, status pills and chart colours on the request board must not rely on colour alone.
4. **Focus.** Visible `:focus-visible` on every focusable element; logical tab order; no focus traps.
5. **Keyboard.** Every interaction works without a pointer — the savings calculator (`SavingsCalculator.svelte`) inputs and sliders, the request board (`RequestBoard.svelte`) filters or tabs.
6. **Forms.** Every input has a `<label>`; units and formats are stated ("monthly amount in dollars"); errors are announced (`aria-live`) and tied to the field (`aria-describedby`).
7. **Dynamic results.** The calculator's computed savings and the board's allocation results update in an `aria-live="polite"` region so screen-reader users hear the result.
8. **Numbers and money.** Amounts formatted for reading (`apps/web/src/lib/core/format.ts`), not raw cents; percentages and scores have accessible text ("score 92 out of 100").
9. **Motion.** `prefers-reduced-motion` honoured for every transition and animation.
10. **Text resize and reflow.** Content usable at 200% zoom and 320 CSS px width with no horizontal scroll; touch targets ≥ 24×24 (2.5.8), ideally 44×44.
11. **Plain language.** Terms and disclosures readable without financial jargon; flag dense legalese as a usability finding (not a WCAG failure).
12. **Images.** Meaningful images have `alt`; decorative ones `alt=""`. The favicon / logo SVG (`apps/web/static/favicon.svg`) aside, inline SVG illustrations have `role="img"` + a title or are `aria-hidden`.

## Report

- **Critical** — a flow unreachable without sight or without a pointer.
- **High** — a clear WCAG 2.2 AA failure (contrast < 4.5:1, missing label, no keyboard path, result not announced).
- **Medium** — best-practice gap (no skip link, headings out of order, colour-only meaning).
- **Low** — polish (focus ring style, reduced-motion on a minor transition, jargon).

For each: file:line, the success criterion (e.g. WCAG 2.4.7 Focus Visible, 1.4.3 Contrast Minimum), and the fix.

End with a **clean** list of components you confirmed pass.

## Delegate to

Use the `compliance-auditor` agent: `"Audit accessibility of apps/web per WCAG 2.2 AA / ADA, in both light and dark schemes."` For fixing, `/a11y-hunt` lands the fixes.

Read-only. Findings only.
