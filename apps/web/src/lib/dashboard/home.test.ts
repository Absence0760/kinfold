import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { loadHome } from './home.ts';

type Fixture = { data: unknown; error: { message: string } | null };

/**
 * A stand-in for the Supabase client: every query on a table (or RPC) resolves
 * to its fixture, and the tables asked for are recorded. The real queries are
 * checked against the local stack under RLS; this pins the assembly.
 */
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

const giving = { data: [{ subscriptions_paid_cents: 100, gifts_given_cents: 0, lent_cents: 0, received_from_pool_cents: 0, received_from_people_cents: 0, requests_paid: 0 }], error: null };
const reliability = { data: [{ subscription_payments: 1, installments_paid_on_time: 0, installments_due: 0, requests_paid: 0, member_since: '2026-03-31' }], error: null };

const loanRow = {
	id: 'l1',
	request_id: 'r1',
	borrower_id: 'maria',
	lender_id: 'sam',
	principal_cents: 70000,
	status: 'signed',
	payment_day: 15,
	pause_months_per_year: 3,
	default_plan: 'forgive',
	secured: false,
	created_at: '2026-10-01T00:00:00Z'
};

describe('loadHome', () => {
	it('skips the per-request and per-loan reads for a member with none (james)', async () => {
		const { db, asked } = fakeDb({ my_giving_record: giving, my_reliability: reliability });
		const home = await loadHome(db, 'james', '2026-10-31');
		expect(home.requests).toEqual([]);
		expect(home.loans).toEqual([]);
		expect(home.giving.givenCents).toBe(100);
		expect(home.reliability?.subscription_payments).toBe(1);
		expect(asked.sort()).toEqual(['contributions', 'family_loans', 'my_giving_record', 'my_reliability', 'requests']);
	});

	it('names the lender’s relationship only to the borrower', async () => {
		const fixtures = {
			family_loans: { data: [loanRow], error: null },
			request_supporters: { data: [{ request_id: 'r1', member_id: 'sam', relationship: 'brother' }], error: null },
			my_giving_record: giving,
			my_reliability: reliability
		};
		const asBorrower = await loadHome(fakeDb(fixtures).db, 'maria', '2026-10-31');
		const asLender = await loadHome(fakeDb(fixtures).db, 'sam', '2026-10-31');
		expect(asBorrower.loans[0]).toMatchObject({ role: 'borrower', lenderRelationship: 'brother' });
		expect(asLender.loans[0]).toMatchObject({ role: 'lender', lenderRelationship: null });
	});

	it('fails loudly instead of showing a partial home when a read errors', async () => {
		const { db } = fakeDb({
			requests: { data: null, error: { message: 'permission denied for table requests' } },
			my_giving_record: giving,
			my_reliability: reliability
		});
		await expect(loadHome(db, 'maria', '2026-10-31')).rejects.toThrow(/your requests: permission denied/);
	});
});
