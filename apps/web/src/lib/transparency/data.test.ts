import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { loadOpenBooks } from './data.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

/** Stand-in for the Supabase client (same shape as the other data tests). */
function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'or', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown) => Promise.resolve(result).then(ok);
		return chain;
	};
	const db = { from: query } as unknown as Db;
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
