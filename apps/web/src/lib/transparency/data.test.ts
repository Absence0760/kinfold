import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import {
	loadGrantReport,
	loadNeedsFormulas,
	loadOpenBooks,
	quarterlySummaries,
	shareWord,
	type GrantRow,
	type QuarterlySummary
} from './data.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

/** Stand-in for the Supabase client (same shape as the other data tests). */
function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'or', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		return chain;
	};
	const db = { from: query, rpc: query } as unknown as Db;
	return { db, asked };
}

const rows = [
	{ fund: 'protection', month: '2026-10-01', requests_paid: 12, paid_out_cents: 500000, allocated_cents: 400000, reserve_cents: 100000, pool_runs: 4, pool_runs_short: 1 },
	{ fund: 'home_fund', month: '2026-09-01', requests_paid: 11, paid_out_cents: 300000, allocated_cents: 200000, reserve_cents: 50000, pool_runs: 3, pool_runs_short: 0 }
];

describe('loadOpenBooks', () => {
	it('labels funds and months and keeps the newest first', async () => {
		const { db, asked } = fakeDb({ open_books: { data: rows, error: null } });
		const books = await loadOpenBooks(db);
		expect(asked).toEqual(['open_books']);
		expect(books.map((b) => b.yearMonth)).toEqual(['October 2026', 'September 2026']);
		expect(books[0].fundLabel).toBe('Car help');
		expect(books[1].fundLabel).toBe('Home help');
		expect(books[1]).toEqual({
			fund: 'home_fund',
			fundLabel: 'Home help',
			month: '2026-09-01',
			yearMonth: 'September 2026',
			monthlyRequestsPaid: 11,
			paidOutCents: 300000,
			allocatedCents: 200000,
			reserveCents: 50000,
			monthlyPoolRuns: 3,
			monthlyPoolRunsShort: 0
		});
	});

	it('a failed read explains itself, never shows blank money as zero', async () => {
		const { db } = fakeDb({ open_books: { data: null, error: { message: 'no books published yet', code: 'PGRST11' }, status: 400 } });
		await expect(loadOpenBooks(db)).rejects.toThrow(/the open books/);
	});

	it('no books published yet is an empty list, not an error', async () => {
		const { db } = fakeDb({ open_books: { data: [], error: null } });
		const books = await loadOpenBooks(db);
		expect(books).toEqual([]);
	});
});

describe('quarterlySummaries', () => {
	const oct = { fund: 'protection', fundLabel: 'Car help', month: '2026-10-01', yearMonth: 'October 2026', monthlyRequestsPaid: 12, paidOutCents: 500000, allocatedCents: 400000, reserveCents: 100000, monthlyPoolRuns: 4, monthlyPoolRunsShort: 1 };
	const sep = { fund: 'protection', fundLabel: 'Car help', month: '2026-09-01', yearMonth: 'September 2026', monthlyRequestsPaid: 11, paidOutCents: 300000, allocatedCents: 200000, reserveCents: 50000, monthlyPoolRuns: 3, monthlyPoolRunsShort: 0 };

	it('a full quarter sums its three months', () => {
		const jul = { ...sep, month: '2026-07-01', yearMonth: 'July 2026', monthlyRequestsPaid: 13, paidOutCents: 100000, allocatedCents: 50000, reserveCents: 25000, monthlyPoolRuns: 2, monthlyPoolRunsShort: 0 };
		const aug = { ...sep, month: '2026-08-01', yearMonth: 'August 2026', monthlyRequestsPaid: 14, paidOutCents: 150000, allocatedCents: 100000, reserveCents: 50000, monthlyPoolRuns: 2, monthlyPoolRunsShort: 1 };
		const quarters: QuarterlySummary[] = quarterlySummaries([oct, sep, jul, aug]);
		expect(quarters.length).toBe(2);
		expect(quarters[0].quarter).toBe('Q4 2026');
		expect(quarters[0].months).toBe(1);
		expect(quarters[1].quarter).toBe('Q3 2026');
		expect(quarters[1].months).toBe(3);
		expect(quarters[1].paidOutCents).toBe(550000);
		expect(quarters[1].requestsPaid).toBe(38);
	});

	it('a partial quarter says how many months it covers', () => {
		const quarters: QuarterlySummary[] = quarterlySummaries([oct]);
		expect(quarters.length).toBe(1);
		expect(quarters[0].quarter).toBe('Q4 2026');
		expect(quarters[0].months).toBe(1);
	});

	it('no published months is no report, not empty money', () => {
		expect(quarterlySummaries([])).toEqual([]);
	});
});

describe('loadNeedsFormulas', () => {
	it('the published weights read newest version first', async () => {
		const { db, asked } = fakeDb({
			needs_formulas: {
				data: [
					{ version: 2, need_bps: 6000, readiness_bps: 3000, reliability_bps: 1000, effective_from: '2026-04-01' },
					{ version: 1, need_bps: 5000, readiness_bps: 2500, reliability_bps: 2500, effective_from: '2026-01-01' }
				],
				error: null
			}
		});
		const formulas = await loadNeedsFormulas(db);
		expect(asked).toEqual(['needs_formulas']);
		expect(formulas.map((f) => f.version)).toEqual([2, 1]);
		expect(formulas.map((f) => shareWord(f.needBps))).toEqual(['60%', '50%']);
		expect(formulas[0].effectiveFrom).toBe('2026-04-01');
		expect(shareWord(6000)).toBe('60%');
		expect(shareWord(3333)).toBe('33.3%');
	});

	it('a refused read fails loudly rather than hiding the formula', async () => {
		const { db } = fakeDb({ needs_formulas: { data: null, error: { message: 'permission denied for table needs_formulas' } } });
		await expect(loadNeedsFormulas(db)).rejects.toThrow(/permission denied/);
	});
});

describe('loadGrantReport', () => {
	it('the grant report reads fund-level aggregates with labels', async () => {
		const { db, asked } = fakeDb({
			grant_report: {
				data: [
					{ fund: 'home_fund', source: 'foundation', federal: false, amount_cents: 250000, grants: 1 },
					{ fund: 'home_fund', source: 'local_government', federal: true, amount_cents: 500000, grants: 1 }
				],
				error: null
			}
		});
		const grants: GrantRow[] = await loadGrantReport(db);
		expect(asked).toEqual(['grant_report']);
		expect(grants.map((g) => g.source)).toEqual(['Foundations', 'Local government']);
		expect(grants.map((g) => g.fundLabel)).toEqual(['Home help', 'Home help']);
		expect(grants[1].federal).toBe(true);
		expect(grants.map((g) => g.amountCents)).toEqual([250000, 500000]);
	});

	it('no grant money is an empty report, not zero money', async () => {
		const { db } = fakeDb({ grant_report: { data: [], error: null } });
		expect(await loadGrantReport(db)).toEqual([]);
	});

	it('a refused read fails loudly rather than hiding the funding', async () => {
		const { db } = fakeDb({ grant_report: { data: null, error: { message: 'permission denied for function grant_report' } } });
		await expect(loadGrantReport(db)).rejects.toThrow(/permission denied/);
	});
});
