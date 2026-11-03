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
	for (const id of ['quarters', 'formula', 'share', 'counsel', 'grants', 'reach']) {
		await expect(page.locator(`#${id}`)).toBeVisible();
	}

	const notices = page.locator('p.problem, p.empty');
	await expect(notices).toHaveCount(7);
	// The six sections (books, weights, share rule, the counselor, grants, fairness
	// share) each show their line: one `p.problem` for the books plus six `p.empty`s.
	await expect(notices.nth(0)).toContainText('need the database to be configured');
});
test('the share-rule section reads like a share rule, not like the books', async ({ page }) => {
	await gotoHydrated(page, '/transparency');
	// Without the stack the page shows no figures, but the section still says
	// what it would publish: part of a repair a member carries themselves.
	await expect(page.locator('#share')).toBeVisible();
	const headings = page.getByRole('heading', { level: 2 });
	await expect(headings.nth(2)).toHaveText('The share rule: what a member carries themselves');
	// The intro names all three published figures so a reader knows where the
	// share rule sits on the page.
	await expect(page.locator('p', { hasText: 'The share rule says' })).toBeVisible();
	// The share section's own line, not the books': it answers about the rule.
	const shareNote = page.locator('#share ~ p');
	await expect(shareNote.first()).toContainText('need the database to be configured');
});

test('the counselor section names nobody the schema did not publish', async ({ page }) => {
	await gotoHydrated(page, '/transparency');
	await expect(page.locator('#counsel')).toBeVisible();
	const headings = page.getByRole('heading', { level: 2 });
	await expect(headings.nth(3)).toHaveText('The certified housing counselor');
	// With no stack no agency can stand, so the section says so rather than
	// naming anyone: the certification stays on the published row's paper.
	const notice = page.locator('#counsel + p');
	await expect(notice).toHaveCount(1);
	await expect(notice.first()).toContainText('need the database to be configured');
	// The agency block - its name, its credential, its contact link - stays
	// out of a stack-less build: the page invents no agency beside a request.
	await expect(page.locator('#counsel + ul')).toHaveCount(0);
	await expect(page.locator('#counsel + a')).toHaveCount(0);
});

test('a failed read never shows money as zero', async ({ page }) => {
	 await gotoHydrated(page, '/transparency');
	 // Every published figure needs the stack, so in this build none of it
	 // renders: the page must not print a stand-in $0 or an empty money cell.
	 const content = await page.content();
	 expect(/\$[\d,]+/.test(content)).toBe(false);
	 expect(/USD|per month|monthly payment/.test(content)).toBe(false);
	 // The counselor section keeps its heading and its one notice line, so a
	 // reader sees the gap explained rather than a blank figure column.
	 const notices = page.locator('#counsel + p');
	 await expect(notices).toHaveCount(1);
	 // The other figures answer for themselves too: six more lines.
	 const allNotices = page.locator('p.empty, p.problem');
	 await expect(allNotices).toHaveCount(7);
	 // Nothing here names a counselor: the Fund's agency only arrives on a row.
	 await expect(page.locator('#counsel + a')).toHaveCount(0);
});
