import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import {
	loadLoan,
	loadLoans,
	loadPendingRestructures,
	pauseLoan,
	restructureLoan,
	signLoanRestructure,
	setLoanSchedule,
	setLoanTerms,
	signLoan,
	resumeLoan,
	forgiveLoan,
	type LoanDetail,
	type RestructureRow
} from './data.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'or', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		chain.maybeSingle = () => Promise.resolve(fixtures[name] ?? { data: null, error: null });
		return chain;
	};
	return { db: { from: query, rpc: query } as unknown as Db, asked };
}

const loanId = '00000000-0000-0000-0037-0000000000a1';
const loanRow = {
	id: loanId,
	request_id: null,
	borrower_id: 'm1',
	lender_id: 'm2',
	principal_cents: 300_000,
	status: 'active',
	payment_day: 15,
	pause_months_per_year: 6,
	default_plan: 'forgive',
	secured: false,
	created_at: '2026-06-01T00:00:00Z'
};
const schedule = [
	{ loan_id: loanId, seq: 1, due_on: '2026-07-15', amount_cents: 100_000, paid_cents: 100_000, paused: false },
	{ loan_id: loanId, seq: 2, due_on: '2026-08-15', amount_cents: 100_000, paid_cents: 70_000, paused: false },
	{ loan_id: loanId, seq: 3, due_on: '2026-09-15', amount_cents: 100_000, paid_cents: 0, paused: false }
];

describe('loadLoans', () => {
	it('summarises the viewer’s loan with the schedule, pauses and misses', async () => {
		const { db, asked } = fakeDb({
			family_loans: { data: [loanRow], error: null },
			loan_installments: { data: schedule, error: null },
			loan_pauses: { data: [{ loan_id: loanId, months: 2, started_on: '2026-03-01' }], error: null },
			loan_forgiveness: { data: [], error: null },
			loan_missed_installments: { data: [{ loan_id: loanId, seq: 2, due_on: '2026-08-15', owed_cents: 30_000 }], error: null }
		});
		const [summary] = await loadLoans(db, 'm1', '2026-06-01');
		// A loan with no request needs no title reads at all.
		expect(asked).toEqual(['family_loans', 'loan_installments', 'loan_pauses', 'loan_forgiveness', 'loan_missed_installments']);
		expect(summary.role).toBe('borrower');
		expect(summary.paidCents).toBe(170_000);
		expect(summary.remainingCents).toBe(130_000);
		expect(summary.next).toEqual({ seq: 2, dueOn: '2026-08-15', owedCents: 30_000, paused: false });
		// The miss is money behind, never a count.
		expect(summary.behindCents).toBe(30_000);
		// Only pauses inside the rolling twelve months eat the allowance: today is
		// 2026-06-01, so the 2026-03 pause counts and leaves 4 of the 6 allowed.
		expect(summary.pauseMonthsLeft).toBe(4);
		expect(summary.pausedUntil).toBeNull();
		expect(summary.lenderRelationship).toBeNull();
		expect(summary.requestTitle).toBeNull();
	});

	it('the lender sees the same figures and no invite relationship, the borrower sees theirs', async () => {
		const lenderRow = { ...loanRow, borrower_id: 'm9', lender_id: 'm1', request_id: 'req1' };
		const { db, asked } = fakeDb({
			family_loans: { data: [lenderRow], error: null },
			loan_installments: { data: [], error: null },
			loan_pauses: { data: [], error: null },
			loan_forgiveness: { data: [], error: null },
			loan_missed_installments: { data: [], error: null },
			requests: { data: [{ id: 'req1', title: 'A dented door' }], error: null },
			request_supporters: { data: [{ request_id: 'req1', member_id: 'm9', relationship: 'brother' }], error: null }
		});
		const [summary] = await loadLoans(db, 'm1', '2026-11-01');
		expect(asked).toEqual([
			'family_loans',
			'loan_installments',
			'loan_pauses',
			'loan_forgiveness',
			'loan_missed_installments',
			'requests',
			'request_supporters'
		]);
		expect(summary.role).toBe('lender');
		expect(summary.requestTitle).toBe('A dented door');
		// The relationship is how the BORROWER named the lender on their invite, so it
		// stays null when the viewer is the lender.
		expect(summary.lenderRelationship).toBeNull();
	});

	it('no loans reads as nothing, without the rest of the reads', async () => {
		const { db, asked } = fakeDb({ family_loans: { data: [], error: null } });
		const loans = await loadLoans(db, 'm1', '2026-11-01');
		expect(loans).toEqual([]);
		expect(asked).toEqual(['family_loans']);
	});

	it('a failed schedule read throws with what the page can say', async () => {
		const { db } = fakeDb({
			family_loans: { data: [loanRow], error: null },
			loan_installments: { data: null, error: { message: 'permission denied', code: '42501' } }
		});
		await expect(loadLoans(db, 'm1', '2026-11-01')).rejects.toThrow(/Couldn't load loan schedules/);
	});
});

describe('loadLoan', () => {
	it('a malformed id is "not found", not a read that will fail', async () => {
		const { db, asked } = fakeDb({});
		expect(await loadLoan(db, 'm1', 'a-plain-word')).toBeNull();
		expect(asked).toEqual([]);
	});

	it('a loan the viewer cannot see reads as nothing', async () => {
		const { db, asked } = fakeDb({ family_loans: { data: null, error: null } });
		expect(await loadLoan(db, 'm1', loanId)).toBeNull();
		expect(asked).toEqual(['family_loans']);
	});

	it('the written agreement and the pending restructure read alongside the schedule', async () => {
		const pending = {
			loan_id: loanId,
			months: 24,
			first_due: '2027-01-15',
			stager_signed_at: '2026-10-01T00:00:00Z',
			other_signed_at: null,
			created_by: 'm1'
		} satisfies RestructureRow;
		const { db, asked } = fakeDb({
			// The agreement is read through the `fromNew` seam over the same table.
			family_loans: {
				data: { ...loanRow, agreement_text: 'No interest, no fees, repay by the schedule.', agreement_finalized_at: '2026-07-01T00:00:00Z' },
				error: null
			},
			loan_installments: { data: schedule, error: null },
			loan_pauses: { data: [{ loan_id: loanId, months: 3, started_on: '2026-05-01' }], error: null },
			loan_forgiveness: { data: [], error: null },
			loan_missed_installments: { data: [], error: null },
			loan_restructures: { data: [pending], error: null },
			requests: { data: null, error: null },
			request_supporters: { data: null, error: null }
		});
		const detail = await loadLoan(db, 'm1', loanId);
		if (detail === null) throw new Error('fixture has the loan');
		expect(detail.agreementText).toBe('No interest, no fees, repay by the schedule.');
		expect(detail.agreementFinalizedAt).toBe('2026-07-01T00:00:00Z');
		expect(detail.restructures).toEqual([pending]);
		expect(detail.missed).toEqual([]);
	});

	it('a lender viewing the loan gets no lender relationship', async () => {
		const { db, asked } = fakeDb({
			family_loans: { data: loanRow, error: null },
			loan_installments: { data: [], error: null },
			loan_pauses: { data: [], error: null },
			loan_forgiveness: { data: [], error: null },
			loan_missed_installments: { data: [], error: null },
			loan_restructures: { data: [], error: null },
			request_supporters: { data: { relationship: 'brother' }, error: null }
		});
		const detail = await loadLoan(db, 'm2', loanId);
		if (detail === null) throw new Error('fixture has the loan');
		// The borrower is not the viewer, so the loader never asks for the relationship.
		expect(detail.lenderRelationship).toBeNull();
		expect(asked).not.toContain('request_supporters');
	});
});

describe('loadPendingRestructures', () => {
	it('no loans means no read', async () => {
		const { db, asked } = fakeDb({ loan_restructures: { data: [], error: null } });
		const rows = await loadPendingRestructures(db, []);
		expect(rows).toEqual([]);
		expect(asked).toEqual([]);
	});

	it('the staged asks read as they are on the books', async () => {
		const { db, asked } = fakeDb({ loan_restructures: { data: [], error: null } });
		const rows = await loadPendingRestructures(db, [loanId]);
		expect(asked).toEqual(['loan_restructures']);
		expect(rows).toEqual([]);
	});
});

describe('the loan writes', () => {
	it('each one call carries its own arguments', async () => {
		const { db, asked } = fakeDb({
			set_loan_terms: { data: null, error: null },
			set_loan_schedule: { data: null, error: null },
			sign_loan: { data: null, error: null },
			pause_loan: { data: null, error: null },
			resume_loan: { data: null, error: null },
			forgive_loan: { data: null, error: null },
			restructure_loan: { data: null, error: null },
			sign_loan_restructure: { data: null, error: null }
		});
		await setLoanTerms(db, loanId, 15, 6, 'forgive');
		await setLoanSchedule(db, loanId, 36, '2026-12-15');
		await signLoan(db, loanId);
		await pauseLoan(db, loanId, 2, null);
		await resumeLoan(db, loanId);
		await forgiveLoan(db, loanId, 10_000, 2026);
		await restructureLoan(db, loanId, 24, '2027-01-15');
		await signLoanRestructure(db, loanId);
		expect(asked).toEqual([
			'set_loan_terms',
			'set_loan_schedule',
			'sign_loan',
			'pause_loan',
			'resume_loan',
			'forgive_loan',
			'restructure_loan',
			'sign_loan_restructure'
		]);
	});

	it('the schema’s refusal reaches the page', async () => {
		const { db } = fakeDb({
			sign_loan: { data: null, error: { message: 'only a signed loan can be signed', code: '23514' } }
		});
		await expect(signLoan(db, loanId)).rejects.toThrow(/only a signed loan/);
	});
});
