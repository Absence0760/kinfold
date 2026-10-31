import { describe, expect, it } from 'vitest';
import {
	amountText,
	filterItems,
	formatCents,
	fundLabel,
	kindLabel,
	kindsPresent,
	monthLabel,
	parseDollars,
	payeeLabel,
	pledgeAmountProblem,
	progress,
	quickAmounts,
	scoreBandLabel,
	sortItems,
	toItems,
	type BoardItem,
	type BoardRow
} from './board.ts';

function item(over: Partial<BoardItem> = {}): BoardItem {
	return {
		id: 'r1',
		kind: 'car_damage',
		summary: 'Rear bumper after being rear-ended.',
		status: 'open',
		amountCents: 185_000,
		bandMinCents: 100_000,
		bandMaxCents: 250_000,
		scoreBand: 80,
		area: 'Pacific',
		monthOf: '2026-10-01',
		raisedCents: 0,
		own: false,
		...over
	};
}

const row = (over: Partial<BoardRow> = {}): BoardRow => ({
	id: 'b2',
	kind: 'car_damage',
	public_summary: 'Rear bumper and trunk.',
	status: 'open',
	amount_cents: 185_000,
	amount_band_min_cents: 100_000,
	amount_band_max_cents: 250_000,
	score_band: 80,
	area: 'Pacific',
	month_of: '2026-10-01',
	...over
});

describe('toItems', () => {
	it('maps view rows, marks the viewer’s own and attaches progress', () => {
		const [i] = toItems([row()], new Set(['b2']), new Map([['b2', 5_000]]));
		expect(i).toMatchObject({ id: 'b2', own: true, raisedCents: 5_000, summary: 'Rear bumper and trunk.' });
	});

	it('leaves progress null when the backend did not share it', () => {
		const [i] = toItems([row({ status: 'paid', amount_cents: null })], new Set(), new Map());
		expect(i.raisedCents).toBeNull();
		expect(i.own).toBe(false);
	});

	it('drops rows without a summary or id', () => {
		expect(toItems([row({ public_summary: null }), row({ id: null })], new Set(), new Map())).toEqual([]);
	});

	it('carries only what the view exposes', () => {
		const [i] = toItems([row()], new Set(), new Map());
		expect(Object.keys(i).sort()).toEqual(
			['amountCents', 'area', 'bandMaxCents', 'bandMinCents', 'id', 'kind', 'monthOf', 'own',
				'raisedCents', 'scoreBand', 'status', 'summary'].sort()
		);
	});
});

describe('labels', () => {
	it('names every kind in plain words and pays a payee, never the member', () => {
		const kinds = ['car_damage', 'car_deductible', 'home_repair', 'down_payment', 'mortgage_gap', 'loan_payoff'] as const;
		for (const k of kinds) {
			expect(kindLabel(k)).toMatch(/^[A-Z][a-z ]+$/);
			expect(payeeLabel(k)).not.toMatch(/member|you/i);
		}
		expect(payeeLabel('car_damage')).toContain('repair shop');
		expect(payeeLabel('mortgage_gap')).toContain('lender');
	});

	it('names the pooled fund the way fund_for_kind maps it', () => {
		expect(fundLabel('car_damage')).toBe('the community repair fund');
		expect(fundLabel('car_deductible')).toBe('the community repair fund');
		expect(fundLabel('home_repair')).toBe('the Community Home Fund');
		expect(fundLabel('loan_payoff')).toBe('the Community Home Fund');
	});

	it('shows score bands as ranges, the top one to 100', () => {
		expect(scoreBandLabel(80)).toBe('80 to 89');
		expect(scoreBandLabel(90)).toBe('90 to 100');
	});

	it('reads the month as a calendar date, whatever the time zone', () => {
		expect(monthLabel('2026-10-01')).toBe('October 2026');
		expect(monthLabel('2026-01-01')).toBe('January 2026');
		expect(monthLabel(null)).toBe('Month not shown');
		expect(monthLabel('nonsense')).toBe('Month not shown');
	});

	it('formats cents, showing cents only when present', () => {
		expect(formatCents(185_000)).toBe('$1,850');
		expect(formatCents(185_050)).toBe('$1,850.50');
	});

	it('shows the exact ask while open, else the band', () => {
		expect(amountText(item())).toBe('$1,850');
		expect(amountText(item({ amountCents: null }))).toBe('$1,000 to $2,500');
		expect(amountText(item({ amountCents: null, bandMinCents: 10_000_000, bandMaxCents: null }))).toBe(
			'$100,000 or more'
		);
	});
});

describe('progress', () => {
	it('says raised and still-needed in words', () => {
		const p = progress(item({ raisedCents: 50_000 }))!;
		expect(p).toMatchObject({ raisedCents: 50_000, leftCents: 135_000, percent: 27 });
		expect(p.text).toBe('$500 raised of $1,850, $1,350 still needed');
	});

	it('rounds down so 100% means fully pledged', () => {
		expect(progress(item({ amountCents: 1_000, raisedCents: 999 }))!.percent).toBe(99);
		const full = progress(item({ amountCents: 1_000, raisedCents: 1_000 }))!;
		expect(full.percent).toBe(100);
		expect(full.text).toContain('fully pledged');
	});

	it('is null when there is no exact ask or no figure', () => {
		expect(progress(item({ amountCents: null }))).toBeNull();
		expect(progress(item({ raisedCents: null }))).toBeNull();
	});
});

describe('filter and sort', () => {
	const a = item({ id: 'a', kind: 'car_damage', monthOf: '2026-08-01', scoreBand: 90, raisedCents: 0 });
	const b = item({ id: 'b', kind: 'home_repair', monthOf: '2026-10-01', scoreBand: 70, raisedCents: 150_000 });
	const c = item({ id: 'c', kind: 'car_damage', monthOf: '2026-09-01', scoreBand: 80, status: 'paid', amountCents: null, raisedCents: null });

	it('filters by kind and by open', () => {
		expect(filterItems([a, b, c], 'car_damage', 'all').map((i) => i.id)).toEqual(['a', 'c']);
		expect(filterItems([a, b, c], 'all', 'open').map((i) => i.id)).toEqual(['a', 'b']);
	});

	it('sorts newest first', () => {
		expect(sortItems([a, b, c], 'newest').map((i) => i.id)).toEqual(['b', 'c', 'a']);
	});

	it('sorts closest to funded, requests without progress last', () => {
		expect(sortItems([c, a, b], 'closest').map((i) => i.id)).toEqual(['b', 'a', 'c']);
	});

	it('sorts by score band, the order the repair fund fills', () => {
		expect(sortItems([b, c, a], 'evidence').map((i) => i.id)).toEqual(['a', 'c', 'b']);
	});

	it('does not mutate and breaks ties stably by id', () => {
		const x = item({ id: 'x' });
		const y = item({ id: 'y' });
		const input = [y, x];
		expect(sortItems(input, 'newest').map((i) => i.id)).toEqual(['x', 'y']);
		expect(input.map((i) => i.id)).toEqual(['y', 'x']);
	});

	it('never orders by whether the request is the viewer’s own', () => {
		const mine = item({ id: 'm', own: true });
		const theirs = item({ id: 'n', own: false });
		for (const order of ['newest', 'closest', 'evidence'] as const) {
			expect(sortItems([theirs, mine], order).map((i) => i.id)).toEqual(['m', 'n']);
			expect(sortItems([mine, theirs], order).map((i) => i.id)).toEqual(['m', 'n']);
		}
	});

	it('lists the kinds present in product order', () => {
		expect(kindsPresent([b, a, c])).toEqual(['car_damage', 'home_repair']);
	});
});

describe('pledge amounts', () => {
	it('parses dollars into integer cents', () => {
		expect(parseDollars('50')).toBe(5_000);
		expect(parseDollars(' $1,250.5 ')).toBe(125_050);
		expect(parseDollars('12.34')).toBe(1_234);
	});

	it('rejects what is not a positive amount with at most two decimals', () => {
		for (const bad of ['', '0', '-5', '1.234', 'abc', '1e3', '.5']) expect(parseDollars(bad)).toBeNull();
	});

	it('explains amounts that cannot be pledged', () => {
		expect(pledgeAmountProblem(null, 10_000)).toMatch(/Enter an amount/);
		expect(pledgeAmountProblem(10_001, 10_000)).toBe('This request needs $100 more, so pledge up to that.');
		expect(pledgeAmountProblem(10_000, 10_000)).toBeNull();
	});

	it('offers quick amounts that fit, ending with the rest', () => {
		expect(quickAmounts(185_000)).toEqual([2_500, 5_000, 10_000, 185_000]);
		expect(quickAmounts(4_000)).toEqual([2_500, 4_000]);
		expect(quickAmounts(0)).toEqual([]);
	});
});
