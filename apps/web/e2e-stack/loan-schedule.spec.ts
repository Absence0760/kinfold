import { expect, test } from '@playwright/test';
import { formatCents } from '../src/lib/dashboard/format.ts';
import { signIn } from './helpers.ts';

// The schedule's printed payments, added up on the page, are exactly the
// principal: no code path may add interest or a fee (docs/STACK.md "Domain
// rules"). Desktop only - the phone shows the same rows as a list, and the
// caption check in home-loans-board.read.spec.ts already covers it there.

test('the printed payments add up to the amount lent, to the cent', async ({ page }) => {
	await signIn(page, 'maria');
	await page.goto('/app/loans');
	await page.getByRole('link', { name: /You borrowed/ }).first().click();
	const table = page.locator('table.wide');
	await expect(table).toBeVisible();
	const cells = table.locator('tbody tr td:nth-child(3)');
	await expect(cells).toHaveCount(7);
	let total = 0;
	for (const text of await cells.allInnerTexts()) {
		// The first line of the cell is the installment (a partial payment adds a second line).
		const amount = text.split('\n')[0].trim();
		const cents = Math.round(Number(amount.replace(/[$,]/g, '')) * 100);
		expect(Number.isInteger(cents) && cents > 0, `"${amount}" reads as money`).toBe(true);
		total += cents;
	}
	expect(formatCents(total)).toBe(formatCents(70000));
});
