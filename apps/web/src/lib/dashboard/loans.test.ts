import { describe, expect, it } from 'vitest';
import { sortLoans, summarizeLoan, type InstallmentRow, type LoanInputs, type LoanRow } from './loans.ts';

const MARIA = 'maria';
const SAM = 'sam';

const loan = (over: Partial<LoanRow> = {}): LoanRow => ({
	id: 'l1',
	request_id: 'r1',
	borrower_id: MARIA,
	lender_id: SAM,
	principal_cents: 70000,
	status: 'active',
	payment_day: 15,
	pause_months_per_year: 3,
	default_plan: 'forgive',
	secured: false,
	created_at: '2026-10-01T00:00:00Z',
	...over
});

/** Seven $100 installments on the 15th from Nov 2026, like the seed. */
const schedule = (paid: number[] = []): InstallmentRow[] =>
	Array.from({ length: 7 }, (_, i) => ({
		loan_id: 'l1',
		seq: i + 1,
		due_on: `${2026 + Math.floor((10 + i) / 12)}-${String(((10 + i) % 12) + 1).padStart(2, '0')}-15`,
		amount_cents: 10000,
		paid_cents: paid[i] ?? 0,
		paused: false
	}));

const inputs = (over: Partial<LoanInputs> = {}): LoanInputs => ({
	installments: schedule(),
	pauses: [],
	forgiveness: [],
	missed: [],
	...over
});

describe('summarizeLoan', () => {
	it('shows a fresh loan the same way to borrower and lender, apart from the role', () => {
		const b = summarizeLoan(loan({ status: 'signed' }), MARIA, inputs(), '2026-10-31');
		const l = summarizeLoan(loan({ status: 'signed' }), SAM, inputs(), '2026-10-31');
		expect(b.role).toBe('borrower');
		expect(l.role).toBe('lender');
		const { role: _r1, ...bRest } = b;
		const { role: _r2, ...lRest } = l;
		expect(bRest).toEqual(lRest);
		expect(b).toMatchObject({
			remainingCents: 70000,
			installmentCount: 7,
			installmentsPaid: 0,
			next: { seq: 1, dueOn: '2026-11-15', owedCents: 10000, paused: false },
			behindCents: 0,
			pauseMonthsLeft: 3,
			collecting: false
		});
	});

	it('never shows more remaining than the principal, and none below zero', () => {
		const s = summarizeLoan(loan(), MARIA, inputs({ installments: schedule([10000, 10000, 10000, 10000, 10000, 10000, 10000]) }), '2027-06-01');
		expect(s.remainingCents).toBe(0);
		expect(s.next).toBeNull();
		expect(s.installmentsPaid).toBe(7);
	});

	it('takes part-payments and forgiveness off what remains', () => {
		const s = summarizeLoan(
			loan(),
			MARIA,
			inputs({ installments: schedule([10000, 4000]), forgiveness: [{ loan_id: 'l1', amount_cents: 20000 }] }),
			'2026-12-20'
		);
		expect(s.paidCents).toBe(14000);
		expect(s.forgivenCents).toBe(20000);
		expect(s.remainingCents).toBe(36000);
		expect(s.next).toEqual({ seq: 2, dueOn: '2026-12-15', owedCents: 6000, paused: false });
	});

	it('reports missed installments as an amount behind, only while collecting', () => {
		const missed = [
			{ loan_id: 'l1', seq: 1, due_on: '2026-11-15', owed_cents: 10000 },
			{ loan_id: 'l1', seq: 2, due_on: '2026-12-15', owed_cents: 10000 },
			{ loan_id: 'other', seq: 1, due_on: '2026-11-15', owed_cents: 99900 }
		];
		expect(summarizeLoan(loan(), SAM, inputs({ missed }), '2027-01-01').behindCents).toBe(20000);
		expect(summarizeLoan(loan({ status: 'forgiven' }), SAM, inputs({ missed }), '2027-01-01').behindCents).toBe(0);
	});

	it('counts pause months used in the last 12 months, as pause_loan does', () => {
		const pauses = [
			{ loan_id: 'l1', months: 2, started_on: '2026-12-01' },
			{ loan_id: 'l1', months: 1, started_on: '2025-11-30' } // more than 12 months before today
		];
		const s = summarizeLoan(loan({ status: 'paused' }), MARIA, inputs({ pauses }), '2027-01-10');
		expect(s.pauseMonthsLeft).toBe(1);
		expect(s.pausedUntil).toBe('2027-02-01');
	});

	it('never goes below zero pause months left', () => {
		const pauses = [{ loan_id: 'l1', months: 5, started_on: '2026-12-01' }];
		expect(summarizeLoan(loan(), MARIA, inputs({ pauses }), '2027-01-10').pauseMonthsLeft).toBe(0);
	});

	it('shows no next installment on a closed loan', () => {
		for (const status of ['repaid', 'forgiven', 'defaulted', 'cancelled'] as const) {
			expect(summarizeLoan(loan({ status }), MARIA, inputs(), '2026-10-31').next).toBeNull();
		}
	});
});

describe('sortLoans', () => {
	it('puts a loan that is behind first, then collecting ones by next due date, then closed', () => {
		const behind = summarizeLoan(loan({ id: 'l1' }), MARIA, inputs({ missed: [{ loan_id: 'l1', seq: 1, due_on: '2026-11-15', owed_cents: 100 }] }), '2027-01-01');
		const later = { ...summarizeLoan(loan(), MARIA, inputs(), '2026-10-31'), next: { seq: 1, dueOn: '2027-03-15', owedCents: 1, paused: false } };
		const sooner = { ...later, next: { ...later.next, dueOn: '2026-11-15' } };
		const closed = summarizeLoan(loan({ status: 'repaid' }), MARIA, inputs(), '2026-10-31');
		expect(sortLoans([closed, later, behind, sooner])).toEqual([behind, sooner, later, closed]);
	});
});
