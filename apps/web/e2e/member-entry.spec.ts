import { expect, test } from '@playwright/test';

// The member area's DATA still needs the local Supabase stack (see the
// "End-to-end tests" entry in docs/STACK.md), but its ENTRY needs none: with
// no key configured, `app/+layout.ts` sends the visitor to /signin. Pinning
// that is what keeps a preview build from serving a half-empty member area or
// crashing through the SPA fallback. Runs on both viewports.

const memberRoutes = ['/app', '/app/board', '/app/cover', '/app/invite',
	'/app/loans', '/app/requests/new', '/app/review'];

for (const route of memberRoutes) {
	test(`${route} sends an unconfigured visitor to sign-in`, async ({ page }) => {
		// The redirect is client-side (Kit's router, in the layout's load), so the
		// URL only changes once the app has hydrated. Waiting on the notice -
		// which only exists on /signin - is what makes the test deterministic.
		await page.goto(route);
		const notice = page.locator('.notice');
		await expect(notice).toHaveCount(1);
		// The member's intended page is kept as the return path, never dropped.
		// For /app itself that is a bare /signin; for the rest, a `?next=`.
		await expect(page).toHaveURL(/\/signin(\?next=%2Fapp.*)?$/);
		await expect(page).toHaveTitle('Sign in · Kinfold');
		// No dead form either: the same no-stack rule the /signin entry pins.
		await expect(page.locator('form')).toHaveCount(0);
	});
}
