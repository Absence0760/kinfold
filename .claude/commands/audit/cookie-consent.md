---
description: Verify every third-party script / fetch / cookie on the web app is either strictly necessary or gated on consent, and that the prerendered marketing site stays free of trackers
---

Audit the web app's cookie and third-party-script posture.

## Goal

`apps/web` is a prerendered SvelteKit marketing / preview site with no backend calls and no env vars (`docs/STACK.md`). The cleanest posture — and the one that matches "Kinfold never sells member data" (`docs/design.md` § Sustainability) — is **no non-essential third-party loads at all**, so no consent banner is needed. This audit confirms that stays true, and lists what would need gating if that changes.

Regimes: US state privacy laws treat cross-context behavioural advertising and many analytics SDKs as "sharing", requiring an opt-out (and honouring Global Privacy Control signals). If non-US visitors are targeted, ePrivacy Art 5(3) + GDPR require prior consent for non-essential cookies and scripts, with "Reject all" as prominent as "Accept all".

## What to check

1. **Page-load chain.** Walk `apps/web/src/app.html`, `apps/web/src/routes/+layout.svelte`, `apps/web/src/routes/+layout.ts`, every `+page.svelte` / `+page.ts`, and every component in `apps/web/src/lib/landing/`. List anything that loads from a third-party origin on page load: fonts (Google Fonts etc.), analytics, tag managers, embeds (video, maps, social), error monitors, chat widgets.
2. **Self-hosted vs third-party assets.** Fonts and images should be served from `apps/web/static/` or the build output, not a third-party CDN that logs visitor IPs.
3. **Error monitoring.** If an error monitor is added, it initialises only after consent (where required) and session replay is off.
4. **Storage APIs.** Grep `apps/web/src/` for `localStorage`, `sessionStorage`, `indexedDB`, `document.cookie`. Remembering a UI preference (e.g. the savings calculator's last input) is fine; a persistent visitor id is not.
5. **Cookies.** The static site should set none. Once the member app exists, Supabase Auth's session storage is strictly necessary; anything else needs a reason.
6. **Global Privacy Control.** If any analytics is ever added, it honours `navigator.globalPrivacyControl`.
7. **Disclosure.** Whatever loads is disclosed in the privacy notice (`/audit/gdpr`).

## Report

- **Critical** — an analytics, replay or ad SDK that captures personal data fires on page load with no consent / opt-out.
- **High** — a non-essential third-party load on the marketing site.
- **Medium** — a third-party font or asset CDN that could be self-hosted; a persistent identifier in browser storage.
- **Low** — a strictly necessary load not yet disclosed in a notice.

For each: the file:line that fires the load, what data it carries, and how to remove or gate it.

End with a **clean** section listing loads confirmed first-party or user-initiated.

## Delegate to

Use the `compliance-auditor` agent: `"Audit the web app's cookie and third-party-script posture; confirm the marketing site loads no non-essential third parties."`

Read-only. Findings only.
