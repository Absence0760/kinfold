import { expect, test } from '@playwright/test';
import { compareSavings, type SavingsInput } from '../src/lib/finance/amortization.ts';
import { formatUsd } from '../src/lib/core/format.ts';
import { navSections } from '../src/lib/landing/sections.ts';
import { counselorAsks } from '../src/lib/requests/public-help.ts';
import { gotoHydrated } from './helpers.ts';

// Runs in both projects (desktop and phone).

// The figures the calculator starts with (SavingsCalculator.svelte).
const start: SavingsInput = { loanAmount: 400_000, annualRatePct: 6.5, years: 30, zeroInterestAmount: 30_000 };
const saved = (input: SavingsInput) => formatUsd(compareSavings(input).interestSaved);

test('landing page renders its headline and title', async ({ page }) => {
	await page.goto('/');
	await expect(page).toHaveTitle('Kinfold · Help paid by people, not profit');
	await expect(page.getByRole('heading', { level: 1 })).toHaveText(
		'When life goes wrong, ask the people around you, not a profit margin.'
	);
});

test('first Tab focuses the skip link and Enter moves focus to main', async ({ page }) => {
	await page.goto('/');
	await page.keyboard.press('Tab');
	const skip = page.getByRole('link', { name: 'Skip to content' });
	await expect(skip).toBeFocused();
	await expect(skip).toBeInViewport();
	await page.keyboard.press('Enter');
	await expect(page).toHaveURL(/#main$/);
	await expect(page.locator('#main')).toBeFocused();
});

test.describe('savings calculator', () => {
	test('moving a slider updates the result', async ({ page }) => {
		await gotoHydrated(page, '/#calculator');
		const calc = page.locator('#calculator');
		const figure = calc.locator('.big');
		const family = calc.getByRole('slider', { name: /From family or friends/ });
		const loan = calc.getByRole('slider', { name: /Home loan needed/ });

		await expect(figure).toHaveText(saved(start));

		await family.press('ArrowRight'); // step $1,000
		await expect(family).toHaveValue('31000');
		await expect(calc).toContainText('From family or friends, at 0% $31,000');
		await expect(figure).toHaveText(saved({ ...start, zeroInterestAmount: 31_000 }));

		await family.press('ArrowLeft');
		await family.press('ArrowLeft');
		await expect(figure).toHaveText(saved({ ...start, zeroInterestAmount: 29_000 }));

		await loan.press('ArrowRight'); // step $5,000
		await expect(calc).toContainText('Home loan needed $405,000');
		await expect(figure).toHaveText(saved({ ...start, loanAmount: 405_000, zeroInterestAmount: 29_000 }));
	});

	test('a zero family share shows the prompt to add one', async ({ page }) => {
		await gotoHydrated(page, '/#calculator');
		const calc = page.locator('#calculator');
		const note = calc.locator('.note');
		const family = calc.getByRole('slider', { name: /From family or friends/ });

		await expect(note).not.toContainText('Add a family or friends share');
		await family.press('Home');
		await expect(family).toHaveValue('0');
		await expect(calc.locator('.big')).toHaveText('$0');
		await expect(note).toContainText('Add a family or friends share to see the difference.');
	});
});

test('the mortgage copy asks for the two things a counselor can ask a bank for', async ({ page }) => {
	// The landing page is prerendered, so this copy is static - and it shares its
	// wording with the counselor line the member panels generate from the row.
	await gotoHydrated(page, '/#repay');
	await expect(page.locator('#repay .mortgage ul')).toContainText(
		`Connect you to a HUD-approved housing counselor to ask your bank for ${counselorAsks}`
	);
	await expect(page.getByRole('link', { name: /housing counselor/i })).toHaveCount(0);
});

test.describe('without JavaScript', () => {
	test.use({ javaScriptEnabled: false });

	test('the prerendered page still shows its content', async ({ page }) => {
		await page.goto('/');
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
		for (const { id } of navSections) {
			await expect(page.locator(`#${id} h2`)).toBeVisible();
		}
		await expect(page.locator('#calculator .big')).toHaveText(saved(start));
		// Proves the context really ran without JS: nothing hydrated.
		await expect(page.locator('html')).not.toHaveAttribute('data-hydrated');
	});
});
