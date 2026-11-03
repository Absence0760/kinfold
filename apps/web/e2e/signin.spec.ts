import { expect, test } from '@playwright/test';
import { gotoHydrated } from './helpers.ts';

// Runs in both projects (desktop and phone). The stack-dependent sign-in flow
// (the form, the session check) still needs the local Supabase stack and stays
// out of the default suite by the earlier e2e entry — but the page ENTRY works
// without a stack: with no key configured the page must explain that, not show
// a dead form or crash through the SPA fallback.

test('signin page serves its title and heading from the fallback', async ({ page }) => {
	// /signin is never prerendered (`ssr = false, prerender = false`), so this
	// pins the adapter's 200.html fallback actually putting the page on the wire.
	await gotoHydrated(page, '/signin');
	await expect(page).toHaveTitle('Sign in · Kinfold');
	await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sign in');
});

test('no stack means a notice, not a dead form', async ({ page }) => {
	await gotoHydrated(page, '/signin');
	// The e2e build has no configured key, so `configured` is false: exactly one
	// notice (the preview runtime sets `dev` true, so it carries the dev
	// wording with the start-it command; a production runtime would carry the
	// public one), and the form is not offered at all.
	await expect(page.locator('.notice')).toHaveCount(1);
	await expect(page.locator('.notice')).toContainText(/Supabase key|Signing in isn.t available/);
	await expect(page.locator('form')).toHaveCount(0);
});