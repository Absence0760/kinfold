import { formatCents } from '#lib/dashboard/format.ts';

export type AmountResult = { ok: true; cents: number } | { ok: false; problem: string };

const EMPTY = 'Enter how much you need, in dollars.';
const COMMA_DECIMAL = 'Use a dot for cents, like 12.50. A comma only separates thousands, like 1,250.50.';
const BAD_GROUPS = 'Put commas only between thousands, like 1,250.50, or leave them out: 1250.50.';
const NOT_AN_AMOUNT = 'Enter the amount in dollars and cents, like 1200 or 1,250.50.';

/**
 * Parse a request amount as typed into integer cents. The money on a request
 * pays a shop or a lender, so nothing ambiguous is guessed at:
 *
 * - `1250`, `$1,250`, `1,250.5` and `1250.50` are read the US way;
 * - a comma followed by one or two digits (`12,50`, `1.200,00`) is a comma
 *   decimal, which this form doesn't take: it is refused with a plain fix,
 *   never read as $1,250;
 * - commas anywhere other than between groups of three (`1,25,000`) are refused;
 * - more than two decimals, zero, negatives and anything else are refused.
 */
export function parseAmount(input: string): AmountResult {
	const s = input.trim().replace(/^\$\s*/, '');
	if (s === '') return { ok: false, problem: EMPTY };

	let digits: string;
	if (s.includes(',')) {
		// A comma decimal: "12,50", "1.200,00", "0,5".
		if (/^[\d.]*,\d{1,2}$/.test(s)) return { ok: false, problem: COMMA_DECIMAL };
		if (!/^\d{1,3}(,\d{3})+(\.\d{1,2})?$/.test(s)) return { ok: false, problem: BAD_GROUPS };
		digits = s.replace(/,/g, '');
	} else {
		digits = s;
	}

	if (!/^\d+(\.\d{1,2})?$/.test(digits)) return { ok: false, problem: NOT_AN_AMOUNT };
	const [whole, frac = ''] = digits.split('.');
	const cents = Number(whole) * 100 + Number(frac.padEnd(2, '0'));
	if (!Number.isSafeInteger(cents)) return { ok: false, problem: NOT_AN_AMOUNT };
	if (cents <= 0) return { ok: false, problem: 'Enter an amount above zero.' };
	return { ok: true, cents };
}

/** Cents, or null when the text isn't a usable amount. */
export const amountCents = (input: string): number | null => {
	const r = parseAmount(input);
	return r.ok ? r.cents : null;
};

/**
 * What the form understood, shown under the field so a misread amount is
 * caught before it is saved. Null while the field is empty or not an amount.
 */
export function amountEcho(input: string): string | null {
	const r = parseAmount(input);
	return r.ok ? `That’s ${formatCents(r.cents)}.` : null;
}
