import { describe, expect, it } from 'vitest';
import {
	afrNote,
	boardGiftNote,
	forgiveTaxNote,
	GIFT_EXCLUSION_CENTS_BY_YEAR,
	giftExclusion,
	giftLimitText,
	pledgeGiftTaxNote
} from './tax.ts';

const table = { 2025: 1_900_000, 2026: 1_900_000, 2027: 2_000_000 };

describe('giftExclusion', () => {
	it('has the 2026 figure design.md uses', () => {
		expect(GIFT_EXCLUSION_CENTS_BY_YEAR[2026]).toBe(1_900_000);
		expect(giftExclusion(2026)).toEqual({ cents: 1_900_000, year: 2026, exact: true });
	});

	it('uses the latest known figure for a later year, labelled with its own year', () => {
		expect(giftExclusion(2031, table)).toEqual({ cents: 2_000_000, year: 2027, exact: false });
		expect(giftExclusion(2030)).toEqual({ cents: 1_900_000, year: 2026, exact: false });
	});

	it('uses the nearest earlier year inside a gap, and the earliest before the table starts', () => {
		expect(giftExclusion(2027, { 2025: 1_900_000, 2029: 2_100_000 })).toMatchObject({ year: 2025, exact: false });
		expect(giftExclusion(2020, table)).toEqual({ cents: 1_900_000, year: 2025, exact: false });
	});

	it('refuses an empty table rather than going silent', () => {
		expect(() => giftExclusion(2026, {})).toThrow(RangeError);
	});
});

describe('giftLimitText', () => {
	it('names the year of the figure', () => {
		expect(giftLimitText(2026)).toBe('$19,000 (the 2026 limit)');
		expect(giftLimitText(2028)).toBe('$19,000 (the 2026 limit, the latest Kinfold has; the 2028 limit may be different)');
	});
});

describe('forgiveTaxNote', () => {
	it('warns over the limit in a known year', () => {
		const n = forgiveTaxNote(2_000_000, 2026);
		expect(n.over).toBe(true);
		expect(n.text).toMatch(/\$20,000 on this loan in 2026/);
		expect(n.text).toMatch(/means filing a gift-tax return \(IRS Form 709\)/);
	});

	it('still warns in a year after the table, using the latest figure and saying which year it is', () => {
		const n = forgiveTaxNote(3_000_000, 2029);
		expect(n.over).toBe(true);
		expect(n.text).toMatch(/the 2026 limit, the latest Kinfold has; the 2029 limit may be different/);
		expect(n.text).toMatch(/may mean filing/);
	});

	it('at or under the limit, says no return is needed and that other gifts add up', () => {
		const n = forgiveTaxNote(1_900_000, 2026);
		expect(n.over).toBe(false);
		expect(n.text).toMatch(/up to \$19,000 \(the 2026 limit\) a year need no gift-tax return/);
		expect(n.text).toMatch(/other gifts you give the same person that year add up/);
	});
});

describe('pledgeGiftTaxNote', () => {
	it('says it counts this pledge only, both under and over the limit', () => {
		for (const cents of [5_000, 2_500_000]) {
			expect(pledgeGiftTaxNote(cents, 2026).text).toMatch(/This counts this pledge only: other gifts you give the same person in 2026 add up\./);
		}
	});

	it('warns when this pledge alone is over the limit', () => {
		expect(pledgeGiftTaxNote(1_900_001, 2026).over).toBe(true);
		expect(pledgeGiftTaxNote(1_900_000, 2026).over).toBe(false);
	});
});

describe('boardGiftNote', () => {
	it('is one affordability and tax line', () => {
		expect(boardGiftNote(2026)).toBe(
			'Give only what you can spare. Gifts to one person over $19,000 (the 2026 limit) in a year may need a gift-tax form (IRS Form 709).'
		);
	});
});

describe('afrNote', () => {
	it('never says "nothing needs reporting" for a rate nobody worked out', () => {
		for (const bps of [null, 0]) {
			const n = afrNote(bps);
			expect(n.worked).toBe(false);
			if (!n.worked) {
				expect(n.text).toMatch(/hasn’t worked out/);
				expect(n.text).toMatch(/No interest is ever charged/);
				expect(n.text).not.toMatch(/nothing needs reporting/i);
			}
		}
	});

	it('above 0, says the lender may owe tax and a tax adviser should confirm', () => {
		const n = afrNote(412);
		expect(n.worked).toBe(true);
		if (n.worked) {
			expect(n.lenderTax).toMatch(/lender may owe income tax/);
			expect(n.lenderTax).toMatch(/tax adviser should confirm/);
		}
	});
});
