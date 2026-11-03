import { expect, test } from '@playwright/test';
import { gotoHydrated } from './helpers.ts';

// Runs in both projects (desktop and phone). The published books need the
// stack, which the e2e build never has, so every section shows its problem
// line — this spec pins that the page renders its structure and says so.

test('transparency page renders its title and heading', async ({ page }) => {
	await page.goto('/transparency');
	await expect(page).toHaveTitle('Open books · what the cooperative paid, month by month');
	await expect(page.getByRole('heading', { level: 1 })).toHaveText('Open books');
});

test('every section is present and the unconfigured notice is visible', async ({ page }) => {
	await gotoHydrated(page, '/transparency');
	for (const id of ['quarters', 'formula', 'grants']) {
		await expect(page.locator(`#${id}`)).toBeVisible();
	}
	// With no stack configured, `load()` returns the problem line for books,
	// formulas and grants — one `p.problem` and two `p.empty` with the same
	// wording, and the quarters section's own empty line. No crash, no blank.
	const notices = page.locator('p.problem, p.empty');
	await expect(notices).toHaveCount(4);
	await expect(notices.nth(0)).toContainText('need the database to be configured');
});