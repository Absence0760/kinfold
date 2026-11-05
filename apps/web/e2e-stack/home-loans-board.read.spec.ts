import { expect, test } from '@playwright/test';
import { formatCents } from '../src/lib/dashboard/format.ts';
import { requests, signIn } from './helpers.ts';

// What a member checks most once they're in: their home, their loans and the
// board. Read-only, so it runs on desktop and phone. The figures are the
// seed's own (seed.sql): b3's loan is sam's 700.00 to maria, 7 installments.

const LOAN_CENTS = 70000;
const B2_SUMMARY = 'Rear bumper and trunk after being rear-ended; uninsured driver.';

test('the home lists the member’s own requests and links each to its page', async ({ page }) => {
	await signIn(page, 'maria');
	const mine = page.getByRole('region', { name: 'Your requests' });
	for (const title of ['Roof leak over the kitchen', 'Deductible after a hailstorm', 'Scraped in a parking garage']) {
		await expect(mine.getByRole('link', { name: title })).toBeVisible();
	}
	// Another member's request never shows on this home.
	await expect(mine.getByText('Burst pipe under the bathroom')).toHaveCount(0);

	await mine.getByRole('link', { name: 'Deductible after a hailstorm' }).click();
	await expect(page).toHaveURL(new RegExp(`/app/requests/${requests.b3}$`));
	await expect(page.getByRole('heading', { level: 1, name: 'Deductible after a hailstorm' })).toBeVisible();
});

test('a borrower and a lender each see the same 0% loan from their side', async ({ page }) => {
	const amount = formatCents(LOAN_CENTS);
	await signIn(page, 'maria');
	await page.getByRole('navigation', { name: 'Member area' }).getByRole('link', { name: 'Loans' }).click();
	await expect(page.getByRole('heading', { level: 1, name: 'Your loans' })).toBeVisible();
	const borrowed = page.getByRole('link', { name: new RegExp(`You borrowed ${amount.replace('$', '\\$')} from your brother`) });
	await expect(borrowed).toBeVisible();
	await borrowed.click();
	// The schedule's own caption: it has to add up to exactly the amount lent,
	// never more (no interest, no fees: docs/STACK.md "Domain rules").
	await expect(
		page.getByText(`7 payments adding up to ${amount}, exactly the amount lent`).filter({ visible: true })
	).toBeVisible();

	await page.getByRole('button', { name: 'Sign out' }).click();
	await expect(page).toHaveURL(/\/signin$/);
	await signIn(page, 'sam');
	await page.goto('/app/loans');
	await expect(page.getByRole('link', { name: new RegExp(`You lent ${amount.replace('$', '\\$')}`) })).toBeVisible();
});

test('the board shows the redacted summary of an open request and no one’s name', async ({ page }) => {
	await signIn(page, 'maria');
	await page.getByRole('navigation', { name: 'Member area' }).getByRole('link', { name: 'Board' }).click();
	await expect(page.getByRole('heading', { level: 1, name: 'Request board' })).toBeVisible();
	const board = page.locator('ul.board');
	await expect(board.getByRole('heading', { name: B2_SUMMARY })).toBeVisible();
	// The board names a state and a month, never a person (design.md, the
	// board's privacy rule). Every seeded member's name is checked.
	for (const name of ['Maria', 'Sam', 'James', 'Priya']) {
		await expect(board).not.toContainText(name);
	}
});
