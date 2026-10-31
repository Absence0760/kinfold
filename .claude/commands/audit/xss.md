---
description: Audit member-content rendering paths for XSS — Svelte `{@html}`, dynamic href/src attributes, request summaries and evidence on the members-only board, AI score reasons, SVG, email HTML
---

Find every place member-supplied text (or text derived from it, like AI score reasons) is rendered as HTML, and verify it's either escaped (Svelte's default) or sanitised.

## Goal

`apps/web` is a prerendered SvelteKit 5 site. Today its content is static (landing sections in `src/lib/landing/`, a demo request board with hard-coded sample data), so the live attack surface is small. The surface grows the moment the member app lands: request titles and descriptions, evidence captions, reviewer notes and refusal letters, the AI scorer's reasons (model output that echoes member input), and payee names all end up on a page — some of them on the members-only board (the `board_requests` view, `docs/backend.md`) that every verified member can read, and aggregate figures on the open marketing site. Most strings render as text via `{value}` and are safe by default. The risk surfaces are `{@html}`, markdown / rich-text renderers, dynamically constructed `href` / `src`, SVG, and HTML email.

## What to check

1. **Svelte `{@html}`.** Grep `apps/web/src/` for `{@html`. For every hit, trace the source of the string. Build-time constants are fine. Anything that originates with a member, a reviewer, a partner API, or the AI scorer must come out of a sanitiser first.

2. **Markdown / rich text.** If a renderer is introduced for request descriptions or reviewer notes (`marked`, `markdown-it`, a Svelte markdown component), confirm raw HTML is disabled or sanitised, and link marks reject `javascript:` / `data:` / `vbscript:` schemes.

3. **Dynamic `href` / `src`.** Grep `apps/web/src/` for `href={` and `src={`. For each member- or partner-controlled value (a shop's website, a share link, an evidence URL), confirm the scheme is validated. Evidence images should be served from signed Supabase Storage URLs the app generated (`evidence-url` edge function for originals), never a URL a member typed.

4. **AI scorer output.** Score reasons are model output conditioned on member-uploaded text and documents — treat them exactly like member input (prompt injection can make the model emit markup). Rendered as text only, never `{@html}`.

5. **SVG and uploaded files.** Evidence uploads may include SVG or HTML disguised as images. Confirm uploads are restricted to an allowlist of raster and PDF MIME types at the storage bucket (`apps/backend/supabase/config.toml` `[storage]` / bucket `allowed_mime_types`) and that evidence renders through `<img src>` (no script execution), never inline.

6. **Email HTML.** Once transactional email exists (local: Mailpit on port 54724; production provider not chosen), every interpolation of member-controlled text (display name, request title, a funder's message) goes through an escape helper. Supabase Auth email templates (configured in `config.toml`) interpolate only Supabase's own variables.

7. **Content-Security-Policy.** Once hosting lands (S3 + CloudFront, per `docs/STACK.md`), a CSP is the backstop. Note whether one is configured; absent is a Medium once member content renders.

## Report

- **High** — member, partner or model-generated text reaches the DOM as HTML without sanitisation. Give a payload that would prove it (e.g. a `public_summary` of `<img src=x onerror=alert(1)>` rendered on the members-only board).
- **Medium** — sanitisation exists but is bypassable, `href` validation accepts a borderline scheme, uploads accept SVG/HTML, or no CSP once member content renders.
- **Low** — escaping is correct but the code makes future XSS easy (a helper that returns HTML sometimes and text other times).

For each: file:line, the source of the untrusted text, the rendering site, the missing sanitiser. If a surface doesn't exist yet, say "not present yet" rather than inventing it.

## Useful starting points

- `apps/web/src/routes/+page.svelte`, `apps/web/src/routes/+layout.svelte`
- `apps/web/src/lib/landing/RequestBoard.svelte` — the demo of the board (what will one day render member requests)
- `docs/backend.md` — `requests.public_summary`, `evidence`, `scores` (reasons), the `evidence-original` / `evidence-redacted` buckets
- `apps/web/src/lib/core/format.ts` — formatting helpers
- `apps/backend/supabase/config.toml` — storage and auth email settings
- `docs/design.md` § "2. Upload evidence" and § "3. Legitimacy score"

## Delegate to

Use the `repo-security-auditor` agent: `"Audit member-content rendering paths for XSS — Svelte {@html}, markdown, dynamic href/src, AI score reasons, evidence uploads and SVG, email HTML."`

Read-only. Report findings; don't patch without confirmation.
