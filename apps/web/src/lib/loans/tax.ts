import { formatCents } from '#lib/dashboard/format.ts';

// PENDING COUNSEL: every sentence in this file is tax wording. design.md
// (Product 1, "Tax note") says document templates and tax copy need a tax
// attorney's review before launch. Until then the wording stays factual and
// conservative: it says what may apply and points to a tax adviser, and never
// tells anyone they owe or don't owe tax.

// --- the annual gift-tax exclusion ----------------------------------------------

/**
 * The annual gift-tax exclusion per recipient, by tax year, in cents. Above it
 * in one year, the giver files a gift-tax return (IRS Form 709); tax is rarely
 * due (design.md, Product 1). Add each year's figure when the IRS publishes it
 * (usually October or November of the year before):
 *  - 2025: $19,000 (Rev. Proc. 2024-40)
 *  - 2026: $19,000 (Rev. Proc. 2025-32; the figure design.md uses)
 */
export const GIFT_EXCLUSION_CENTS_BY_YEAR: Readonly<Record<number, number>> = Object.freeze({
	2025: 1_900_000,
	2026: 1_900_000
});

export interface GiftLimit {
	cents: number;
	/** The tax year this figure is for. */
	year: number;
	/** False when the asked-for year isn't in the table and a nearby year's figure stands in. */
	exact: boolean;
}

/**
 * The yearly gift limit for `year`. A year missing from the table never goes
 * silent: it gets the latest known figure at or before it (or the earliest one,
 * for a year before the table starts), labelled with the year it's really for.
 */
export function giftExclusion(year: number, table: Readonly<Record<number, number>> = GIFT_EXCLUSION_CENTS_BY_YEAR): GiftLimit {
	const years = Object.keys(table)
		.map(Number)
		.sort((a, b) => a - b);
	if (years.length === 0) throw new RangeError('the gift-exclusion table is empty');
	if (table[year] != null) return { cents: table[year], year, exact: true };
	const before = years.filter((y) => y < year);
	const use = before.length ? before[before.length - 1] : years[0];
	return { cents: table[use], year: use, exact: false };
}

/** "$19,000 (the 2026 limit)", or, for a year not in the table, says the figure may have changed. */
export function giftLimitText(forYear: number, table?: Readonly<Record<number, number>>): string {
	const limit = giftExclusion(forYear, table);
	return limit.exact
		? `${formatCents(limit.cents)} (the ${limit.year} limit)`
		: `${formatCents(limit.cents)} (the ${limit.year} limit, the latest Kinfold has; the ${forYear} limit may be different)`;
}

export interface TaxNote {
	/** True when the total is over the yearly limit, so the note is a warning. */
	over: boolean;
	text: string;
}

/**
 * The gift-tax line on the forgive screen. `yearTotalCents` is everything
 * forgiven on this loan in `taxYear`, including this amount.
 */
export function forgiveTaxNote(yearTotalCents: number, taxYear: number, table?: Readonly<Record<number, number>>): TaxNote {
	const limit = giftExclusion(taxYear, table);
	const limitText = giftLimitText(taxYear, table);
	const total = formatCents(yearTotalCents);
	if (yearTotalCents > limit.cents) {
		return {
			over: true,
			text: `With this, you’ll have forgiven ${total} on this loan in ${taxYear}, over the yearly limit per person of ${limitText}. That ${limit.exact ? 'means' : 'may mean'} filing a gift-tax return (IRS Form 709). Tax is rarely due, but check with a tax adviser.`
		};
	}
	return {
		over: false,
		text: `Gifts to one person of up to ${limitText} a year need no gift-tax return. You’ll have forgiven ${total} on this loan in ${taxYear}; other gifts you give the same person that year add up too.`
	};
}

/**
 * The gift-tax line on a pledge's confirm step. It can only see this one
 * pledge, so it says so: other gifts to the same person that year add up.
 */
export function pledgeGiftTaxNote(cents: number, year: number, table?: Readonly<Record<number, number>>): TaxNote {
	const limit = giftExclusion(year, table);
	const limitText = giftLimitText(year, table);
	const scope = `This counts this pledge only: other gifts you give the same person in ${year} add up.`;
	if (cents > limit.cents) {
		return {
			over: true,
			text: `This gift alone is over the yearly limit per person of ${limitText}, so it ${limit.exact ? 'means' : 'may mean'} filing a gift-tax return (IRS Form 709). Tax is rarely due, but check with a tax adviser. ${scope}`
		};
	}
	return {
		over: false,
		text: `Giving one person more than ${limitText} in a year means filing a gift-tax return (IRS Form 709); tax is rarely due. ${scope}`
	};
}

/** The one-line affordability and tax note on a board gift. */
export function boardGiftNote(year: number, table?: Readonly<Record<number, number>>): string {
	return `Give only what you can spare. Gifts to one person over ${giftLimitText(year, table)} in a year may need a gift-tax form (IRS Form 709).`;
}

// --- the IRS minimum rate (AFR) --------------------------------------------------

export type AfrNote =
	| { worked: false; text: string }
	| { worked: true; lenderTax: string };

/**
 * What the loan page says about the IRS minimum rate. Nothing writes
 * `imputed_rate_bps` yet (design.md, Product 1, "Tax note"), so null and 0
 * both mean "not worked out", never "checked and nothing to report". Once the
 * backend computes it, 0 may come to mean "checked: doesn't apply"; that needs
 * its own state in the schema, not a guess here.
 */
export function afrNote(imputedRateBps: number | null): AfrNote {
	if (imputedRateBps == null || imputedRateBps <= 0) {
		return {
			worked: false,
			text: 'Kinfold hasn’t worked out the IRS minimum-rate check for this loan yet. No interest is ever charged: the loan stays at 0% either way.'
		};
	}
	return {
		worked: true,
		lenderTax:
			'The lender may owe income tax on that interest not charged, even though it’s never paid. For loans of $100,000 or less this can be smaller or nothing. A tax adviser should confirm what applies.'
	};
}
