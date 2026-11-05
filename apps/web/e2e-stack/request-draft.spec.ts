import { expect, test, type Page } from '@playwright/test';
import { formatCents } from '../src/lib/dashboard/format.ts';
import { signIn } from './helpers.ts';

// A member asking for help: start a draft from home, fix what the form
// refuses, save, edit, and withdraw it. Each run makes its own new request, so
// it touches no seeded row another spec reads. Desktop only (it writes).

const TITLE = 'Furnace stopped working';
const EDITED = 'Furnace stopped working in the cold snap';

function isoDaysAgo(days: number): string {
	const d = new Date();
	d.setDate(d.getDate() - days);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

async function startDraft(page: Page) {
	await signIn(page, 'maria');
	await page.getByRole('region', { name: 'Your requests' }).getByRole('link', { name: 'Ask for help' }).click();
	await expect(page).toHaveURL(/\/app\/requests\/new$/);
	await expect(page.getByRole('heading', { level: 1, name: 'Ask for help' })).toBeVisible();
}

test('an empty draft is refused field by field, and nothing is saved', async ({ page }) => {
	await startDraft(page);
	await page.getByRole('button', { name: 'Save draft' }).click();
	await expect(page.getByText('Choose what the help is for.')).toBeVisible();
	await expect(page.getByText('Give your request a short title, like “Rear bumper after a crash”.')).toBeVisible();
	await expect(page.getByText('Enter the date it happened (or the bill arrived).')).toBeVisible();
	await expect(page).toHaveURL(/\/app\/requests\/new$/);
});

test('a member drafts a request, edits it, then withdraws it', async ({ page }) => {
	await startDraft(page);
	await page.getByRole('radio', { name: /^Home repair/ }).check();
	await page.getByLabel('Title').fill(TITLE);
	await page.getByLabel(/What happened/).fill('The furnace quit overnight; the repair company has quoted the part.');
	await page.getByLabel('How much you need').fill('450');
	await page.getByLabel('When it happened').fill(isoDaysAgo(2));
	await page.getByRole('button', { name: 'Save draft' }).click();

	// Saved: the request's own page, with what was typed read back from the database.
	await expect(page).toHaveURL(/\/app\/requests\/[0-9a-f-]{36}\?saved=1$/);
	await expect(page.getByRole('heading', { level: 1, name: TITLE })).toBeVisible();
	await expect(page.getByRole('status').filter({ hasText: 'Draft saved.' })).toHaveText(
		'Draft saved. Add your evidence next, then submit it.'
	);
	const facts = page.locator('dl.facts');
	await expect(facts).toContainText(formatCents(45000));
	await expect(facts).toContainText('Home repair');
	await expect(page.locator('.title-row')).toContainText('Draft');

	// Edit the draft in place.
	await page.getByRole('button', { name: 'Edit draft' }).click();
	await expect(page.getByRole('heading', { name: 'Edit your draft' })).toBeVisible();
	await page.getByLabel('Title').fill(EDITED);
	await page.getByRole('button', { name: 'Save changes' }).click();
	await expect(page.getByRole('status').filter({ hasText: 'Changes saved.' })).toBeVisible();
	await expect(page.getByRole('heading', { level: 1, name: EDITED })).toBeVisible();

	// It is on the member's home under its new title.
	const url = page.url().replace(/\?.*$/, '');
	await page.goto('/app');
	await expect(page.getByRole('region', { name: 'Your requests' }).getByRole('link', { name: EDITED })).toBeVisible();

	// Withdraw asks first, then closes it for good.
	await page.goto(url);
	await page.getByRole('button', { name: 'Withdraw' }).click();
	await page.getByRole('button', { name: 'Yes, withdraw it' }).click();
	await expect(page.getByRole('status').filter({ hasText: 'Withdrawn.' })).toHaveText(
		'Withdrawn. Any pledges were released.'
	);
	await expect(page.locator('.title-row')).toContainText('Withdrawn');
	await expect(page.getByRole('button', { name: 'Edit draft' })).toHaveCount(0);
});
