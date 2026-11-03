import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { loadFundLoans, loadFundLoan, pauseFundLoan, resumeFundLoan, restructureFundLoan } from './fund.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

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
	return { db: { from: query, rpc: query } as unknown as Db, asked };
}

const monthly = {
	id: 'm1',
	principal_cents: 250000,
	status: 'active',
	schedule: 'monthly',
	income_share_bps: 0,
	lien_bps: 30000,
	fund_signed_at: '2026-10-01T00:00:00Z',
	borrower_signed_at: '2026-10-02T00:00:00Z',
	created_at: '2026-10-01T00:00:00Z',
};
const income = {
	id: 'i1',
	principal_cents: 120000,
	status: 'active',
	schedule: 'income',
	income_share_bps: 2500,
	lien_bps: 0,
	fund_signed_at: '2026-10-01T00:00:00Z',
	borrower_signed_at: '2026-10-02T00:00:00Z',
	created_at: '2026-10-02T00:00:00Z',
};

describe('loadFundLoans', () => {
	it('money figures come from the schema doors, not from client math', async () => {
		const { db, asked } = fakeDb({
			fund_loans: { data: [income, monthly], error: null },
			fund_loan_installments: {
				data: [
					{ loan_id: 'm1', due_on: '2026-03-01', amount_cents: 10000, paid_cents: 10000 },
					{ loan_id: 'm1', due_on: '2026-02-01', amount_cents: 8000, paid_cents: 3000 },
				],
				error: null,
			},
			fund_loan_outstanding_cents: { data: 137000, error: null },
			fund_loan_income_due_cents: { data: 31250, error: null },
			fund_loan_pauses: { data: [{ loan_id: 'm1', months: 2, started_on: '2026-01-10' }], error: null },
			fund_loan_restructures: { data: [{ loan_id: 'i1', months: 60, first_due: '2026-04-01', applied_at: null }], error: null },
		});
		const rows = await loadFundLoans(db, 'member-1');
		// Two loans, so the two money doors are each asked once per loan; the
		// fake answers every ask with the same fixture figure.
		expect(asked).toEqual([
			'fund_loans',
			'fund_loan_installments',
			'fund_loan_pauses',
			'fund_loan_restructures',
			'fund_loan_outstanding_cents',
			'fund_loan_outstanding_cents',
			'fund_loan_income_due_cents',
			'fund_loan_income_due_cents'
		]);
		expect(rows).toEqual([
			{ loan: income, outstandingCents: 137000, shareCents: 31250, next: null, pausedUntil: null, restructureWaiting: true },
			{ loan: monthly, outstandingCents: 137000, shareCents: 0, next: { dueOn: '2026-02-01', owedCents: 5000 }, pausedUntil: '2026-03-10', restructureWaiting: false },
		]);
	});

	it('a monthly schedule never borrows the income cap', async () => {
		const { db } = fakeDb({
			fund_loans: { data: [monthly], error: null },
			fund_loan_installments: { data: [], error: null },
			fund_loan_outstanding_cents: { data: 250000, error: null },
			fund_loan_income_due_cents: { data: 999999, error: null },
		});
		const rows = await loadFundLoans(db, 'member-1');
		expect(rows).toEqual([{ loan: monthly, outstandingCents: 250000, shareCents: 0, next: null, pausedUntil: null, restructureWaiting: false }]);
	});

		it('a refused read fails loudly rather than showing no loans', async () => {
		const { db } = fakeDb({ fund_loans: { data: null, error: { message: 'permission denied for table fund_loans' } } });
		await expect(loadFundLoans(db, 'member-1')).rejects.toThrow(/permission denied/);
	});
});

describe('loadFundLoan', () => {
	it('the console reads one loan with its schedule and history', async () => {
		const { db, asked } = fakeDb({
			fund_loans: { data: [monthly], error: null },
			fund_loan_installments: { data: [{ loan_id: 'm1', seq: 1, due_on: '2026-02-01', amount_cents: 5000, paid_cents: 0 }], error: null },
			fund_loan_pauses: { data: [{ loan_id: 'm1', months: 1, started_on: '2026-01-05' }], error: null },
			fund_loan_restructures: { data: [{ loan_id: 'm1', months: 24, first_due: '2026-03-01', applied_at: null }], error: null },
			fund_loan_outstanding_cents: { data: 5000, error: null }
		});
		const detail = await loadFundLoan(db, 'm1');
		expect(asked).toEqual([
			'fund_loans',
			'fund_loan_installments',
			'fund_loan_pauses',
			'fund_loan_restructures',
			'fund_loan_outstanding_cents'
		]);

		if (detail === null) throw new Error('fixture has the loan');
		expect(detail.loan).toEqual(monthly);
		expect(detail.outstandingCents).toBe(5000);
		expect(detail.restructure).toEqual({ loan_id: 'm1', months: 24, first_due: '2026-03-01', applied_at: null });
	});

	it('a loan the viewer is not the borrower of reads as null', async () => {
		const { db } = fakeDb({ fund_loans: { data: [], error: null } });
		const detail = await loadFundLoan(db, 'someone-else');
		expect(detail).toBeNull();
	});
});

describe('the Fund loan doors', () => {
	it('pause, resume and restructure each hit their own schema door', async () => {
		const { db, asked } = fakeDb({
			pause_fund_loan: { data: null, error: null },
			resume_fund_loan: { data: 'active', error: null },
			restructure_fund_loan: { data: null, error: null }
		});
		await pauseFundLoan(db, 'm1', 2);
		await resumeFundLoan(db, 'm1');
		await restructureFundLoan(db, 'm1', 24, '2026-03-01');
		expect(asked).toEqual(['pause_fund_loan', 'resume_fund_loan', 'restructure_fund_loan']);
	});

	it('a door refusal throws the schema\u2019s own message', async () => {
		const { db } = fakeDb({ pause_fund_loan: { data: null, error: { message: 'this loan allows 3 pause months a year (3 used); ask the lending Fund to restructure' } } });
		await expect(pauseFundLoan(db, 'm1', 4)).rejects.toThrow(/ask the lending Fund to restructure/);
	});
});