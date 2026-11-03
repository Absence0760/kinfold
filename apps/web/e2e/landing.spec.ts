import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';
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

// The board is the site's honesty promise in miniature: every card states
// money as "$X of $Y - A from friends - B from the fund". Those figures have
// to add up, and the bars beside them have to agree with the amounts. Checked
// on the printed DOM, so it audits whatever pool size the reader drags to.
async function boardArithmeticProblems(page: Page) {
	return await page.evaluate(() => {
		const found = [];
		const num = (s: string) => Number(s.replace(/[^0-9.]/g, ''));
		const board = document.querySelector('ul.board');
		if (!board) return ['the board is missing'];
		let fundFromCards = 0;
		for (const card of board.querySelectorAll(':scope > li')) {
			const meta = card.querySelector('p.meta');
			const titleEl = card.querySelector('p.title');
			const title = titleEl?.textContent || 'a card';
			if (!meta) {
				found.push(`${title} states no amounts to check`);
				continue;
			}
			const text = meta.textContent.replace(/\s+/g, ' ').trim();
			const totals = /^(\$[\d,]+) of (\$[\d,]+)/.exec(text);
			if (!totals) {
				found.push(`${title}: the meta line "${text}" states no amounts`);
				continue;
			}
			const raised = num(totals[1]);
			const amount = num(totals[2]);
			const friendsM = /from friends/.test(text) ? /\$([\d,]+) from friends/.exec(text) : null;
			const fundM = /from the fund/.test(text) ? /\$([\d,]+) from the fund/.exec(text) : null;
			const friends = friendsM ? num(friendsM[1]) : 0;
			const fund = fundM ? num(fundM[1]) : 0;
			fundFromCards += fund;
			if (friends + fund !== raised) {
				found.push(`${title} claims ${friends} + ${fund} = ${raised}, but that is ${friends + fund}`);
			}
			if (raised > amount) {
				found.push(`${title} claims ${raised} paid of an amount of ${amount}: more than was asked`);
			}
			const friendsBar = card.querySelector('.bar .friends');
			const fundBar = card.querySelector('.bar .pool-share');
			if (friendsBar && fundBar && amount > 0) {
				const pct = (el: Element) => Number((el as HTMLElement).style.width.replace('%', ''));
				const sum = pct(friendsBar) + pct(fundBar);
				const expected = (raised / amount) * 100;
					// The pool splits proportionally, so grants are fractional while
					// printed money is rounded to the dollar: each printed figure may
					// be off the exact allocation by under $1, so the bar may not
					// match the printed amounts closer than that drift. Accuse only
					// materially wrong bars.
					const tolerance = (2 / amount) * 100;
					if (Math.abs(sum - expected) > tolerance) {
						found.push(`${title}: the bars show ${sum.toFixed(1)}% but the amounts say ${expected.toFixed(1)}%`);
					}
			}
		}
		const poolInput = document.querySelector('label.pool input');
		const note = document.querySelector('p.note');
		if (poolInput && note) {
			const pool = num(poolInput.getAttribute('aria-valuetext') || '');
			const leftM = /Left in the fund: (\$[\d,]+)/.exec(note.textContent.replace(/\s+/g, ' '));
			const left = leftM ? num(leftM[1]) : NaN;
			// Every card's fund figure is printed rounded to the dollar, so the
			// printed total can be off the pool by under $1 per card; accuse only
			// a fund that is materially mis-tied.
			if (Math.abs(left + fundFromCards - pool) > 6) {
				found.push(`the fund promised ${pool}, but ${fundFromCards} went to cards and ${left} is left (${fundFromCards + left})`);
			}
		} else {
			found.push('the board has no fund slider/note to tie its money to');
		}
		return found;
	});
}

// The calculator is the public page's central promise. Two of its halves were
// unwatched: a sighted reader reads the printed <strong> label while a screen
// reader hears the slider's aria-valuetext, and the result figures were only
// pinned at one input. Now the audit reads the printed DOM at whatever stop the
// reader left the sliders and demands the printed label matches what the
// control announces, and every printed figure equals the app's own module.
async function calcMismatchProblems(page: Page) {
	const printed = await page.evaluate(() => {
		const read = (sel: string) => {
			const el = document.querySelector(sel);
			return el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
		};
		const strong = [];
		for (const s of document.querySelectorAll('#calculator .inputs label span strong')) strong.push(s.textContent || '');
		const aria = [];
		for (const i2 of document.querySelectorAll('#calculator .inputs label input')) aria.push(i2.getAttribute('aria-valuetext') || '');
		const values = [];
		for (const v of document.querySelectorAll('#calculator .compare .value')) values.push(v.textContent || '');
		const subs = [];
		for (const s of document.querySelectorAll('#calculator .compare .sub')) subs.push(s.textContent || '');
		return {
			strong: strong,
			aria: aria,
			big: read('#calculator .big'),
			values: values,
			subs: subs,
			note: read('#calculator .note')
		};
	});
	const found = [];
	const words = ['loan needed', 'interest rate', 'term', 'family share'];
	for (let i = 0; i < printed.aria.length; i += 1) {
		if (printed.aria[i] !== printed.strong[i]) {
			found.push('slider ' + words[i] + ' prints ' + printed.strong[i] + ' to a sighted reader but announces ' + printed.aria[i] + ' to a screen reader');
		}
	}
	const num = (s: string) => Number(s.replace(/[^0-9.]/g, ''));
	const input: SavingsInput = { loanAmount: num(printed.aria[0]), annualRatePct: num(printed.aria[1]), years: num(printed.aria[2]), zeroInterestAmount: num(printed.aria[3]) };
	const r = compareSavings(input);
	if (printed.big !== formatUsd(r.interestSaved)) {
		found.push('the headline figure prints ' + printed.big + ' but the module says ' + formatUsd(r.interestSaved) + ' for these inputs');
	}
	if (printed.values.length !== 2 || printed.values[0] !== formatUsd(r.bankOnly.monthly) + '/mo') {
		found.push('the bank-only payment prints ' + (printed.values[0] || 'nothing') + ' but the module says ' + formatUsd(r.bankOnly.monthly) + '/mo');
	}
	if (printed.values.length !== 2 || printed.values[1] !== formatUsd(r.withKinfold.monthly) + '/mo') {
		found.push('the Kinfold payment prints ' + (printed.values.length > 1 ? printed.values[1] : 'nothing') + ' but the module says ' + formatUsd(r.withKinfold.monthly) + '/mo');
	}
	if (printed.subs.length !== 2 || printed.subs[0] !== formatUsd(r.bankOnly.interest) + ' interest') {
		found.push('the bank-only interest line prints ' + (printed.subs[0] || 'nothing') + ' but the module says ' + formatUsd(r.bankOnly.interest));
	}
	if (printed.subs.length !== 2 || printed.subs[1] !== formatUsd(r.withKinfold.interest) + ' interest') {
		found.push('the Kinfold interest line prints ' + (printed.subs[1] || 'nothing') + ' but the module says ' + formatUsd(r.withKinfold.interest));
	}
	const perMonth = r.bankOnly.monthly - r.withKinfold.monthly;
	const expectedNote = perMonth > 0.5 ? formatUsd(perMonth) + ' less every month.' : 'Add a family or friends share to see the difference.';
	if (printed.note.indexOf(expectedNote) === -1) {
		found.push('the note does not state ' + expectedNote + ' for these inputs');
	}
	return found;
}

test('the calculator prints what its sliders announce and its own maths say, at any stop', async ({ page }) => {
	await gotoHydrated(page, '/#calculator');
	const names = [/Home loan needed/, /Bank interest rate/, /Term/, /From family or friends/];
	expect(await calcMismatchProblems(page)).toEqual([]);

	for (const stop of ['Home', 'End', 'Home']) {
		for (const name of names) {
			await page.getByRole('slider', { name: name }).press(stop);
		}
		expect(await calcMismatchProblems(page)).toEqual([]);
	}
});

// Screen-reader parity: the settled live summary a screen reader hears must
// state only money the sighted reader can see. A stale announcement reads a
// figure that is no longer on the page - the two halves of the audience then
// hear different money beside the same sliders.
async function liveMoneyProblems(page: Page, section: string) {
	const report = await page.evaluate((sel: string) => {
		const root = document.querySelector(sel);
		if (!root) return { live: '', printed: [] as string[], absent: true };
		const liveEl = root.querySelector('[aria-live]');
		const liveText = liveEl ? (liveEl.textContent || '').replace(/\s+/g, ' ').trim() : '';
		const full = root.textContent || '';
		// The live region is one contiguous run of the section text - drop it so
		// what is left is only what the sighted reader sees.
		const printedText = liveText ? full.replace(liveText, '') : full;
		const printed: string[] = [];
		for (const m of printedText.matchAll(/\$[\d,]+/g)) printed.push(m[0]);
		return { live: liveText, printed: printed, absent: false };
	}, section);
	const found: string[] = [];
	if (report.absent) return ['section ' + section + ' is not on the page: the audit read nothing'];
	if (report.live === '') {
		found.push('section ' + section + ' has no live summary text: a screen reader hears no summary at all');
		return found;
	}
	for (const m of report.live.matchAll(/\$[\d,]+/g)) {
		if (!report.printed.includes(m[0])) {
			found.push('the live summary announces ' + m[0] + ', but that figure is not printed in section ' + section + ': a screen reader hears money the sighted reader never sees');
		}
	}
	return found;
}

async function waitForSummary(page: Page, section: string) {
	const read = (sel: string) => {
		const el = document.querySelector(sel)?.querySelector('[aria-live]');
		return el ? (el.textContent || '') : '';
	};
	const before = await page.evaluate(read, section);
	await page.waitForFunction((args: { sel: string; prev: string }) => {
		const el = document.querySelector(args.sel)?.querySelector('[aria-live]');
		return (el ? (el.textContent || '') : '') !== args.prev;
	}, { sel: section, prev: before });
}

test.describe('screen-reader summaries', () => {
	test('the calculator summary settles to money the page shows', async ({ page }) => {
		await gotoHydrated(page, '/#calculator');
		expect(await liveMoneyProblems(page, '#calculator')).toEqual([]);
		await page.getByRole('slider', { name: /Home loan needed/ }).press('End');
		await waitForSummary(page, '#calculator');
		expect(await liveMoneyProblems(page, '#calculator')).toEqual([]);
	});

	test('the board summary settles to money the page shows', async ({ page }) => {
		await gotoHydrated(page, '/#board');
		expect(await liveMoneyProblems(page, '#board')).toEqual([]);
		await page.getByRole('slider', { name: /This month.s repair fund/ }).press('Home');
		await waitForSummary(page, '#board');
		expect(await liveMoneyProblems(page, '#board')).toEqual([]);
	});
});


test.describe('request board', () => {
	test('the board\'s figures add up at the default fund', async ({ page }) => {
		await gotoHydrated(page, '/#board');
		expect(await boardArithmeticProblems(page)).toEqual([]);
	});

	test('the board\'s figures still add up after dragging the fund', async ({ page }) => {
		await gotoHydrated(page, '/#board');
		const pool = page.getByRole('slider', { name: /This month's repair fund/ });
		await pool.press('Home');
		expect(await boardArithmeticProblems(page)).toEqual([]);
		await pool.press('ArrowRight');
		await pool.press('ArrowRight');
		expect(await boardArithmeticProblems(page)).toEqual([]);
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

test('a dead link answers the error page, not a blank shell', async ({ page }) => {
	// The static adapter answers unknown paths with 200.html, so the copy the
	// visitor reads - and the copy that tells them to stop, not to retry - is
	// what the fallback actually puts on the wire.
	await gotoHydrated(page, '/a-link-nobody-meant');
	await expect(page.getByRole('heading', { level: 1 })).toHaveText('We can\u2019t find that page');
	await expect(page.locator('body')).toContainText('The link may be old or mistyped.');
	// A 404 offers no retry: the copy's `retry: false` reaches the screen.
	await expect(page.getByRole('button', { name: /try again/i })).toHaveCount(0);
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
