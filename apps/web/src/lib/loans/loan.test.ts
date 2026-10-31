import { describe, expect, it } from 'vitest';
import {
	forgiveProblem,
	forgivenInYear,
	formatBps,
	installmentState,
	loanActions,
	pauseMonthsLeft,
	pauseMonthsUsed,
	pauseProblem,
	pushBack,
	signatures,
	sideOf
} from './loan.ts';

const row = (over: Partial<{ amount_cents: number; paid_cents: number; due_on: string }> = {}) => ({
	amount_cents: 10000,
	paid_cents: 0,
	due_on: '2026-11-15',
	...over
});

describe('installmentState', () => {
	it('reads paid, part paid, due and upcoming', () => {
		expect(installmentState(row({ paid_cents: 10000 }), 'active', false, '2026-12-01')).toBe('paid');
		expect(installmentState(row({ paid_cents: 4000 }), 'active', false, '2026-12-01')).toBe('part_paid');
		expect(installmentState(row(), 'active', false, '2026-11-15')).toBe('due');
		expect(installmentState(row(), 'active', false, '2026-11-14')).toBe('upcoming');
	});

	it('marks missed only when the view lists it', () => {
		expect(installmentState(row(), 'active', true, '2026-12-01')).toBe('missed');
		expect(installmentState(row({ paid_cents: 10000 }), 'active', true, '2026-12-01')).toBe('paid');
	});

	it('stops calling anything due once the loan stopped collecting', () => {
		for (const status of ['forgiven', 'defaulted', 'cancelled', 'repaid'] as const) {
			expect(installmentState(row(), status, false, '2027-01-01')).toBe('not_collected');
		}
	});
});

describe('pauses', () => {
	it('counts only the rolling 12 months, like pause_loan', () => {
		const pauses = [
			{ months: 2, started_on: '2025-10-31' },
			{ months: 1, started_on: '2025-11-01' },
			{ months: 1, started_on: '2026-06-01' }
		];
		expect(pauseMonthsUsed(pauses, '2026-10-31')).toBe(2);
	});

	it('caps what is left at the allowance and at 12 a pause', () => {
		expect(pauseMonthsLeft(3, 1)).toBe(2);
		expect(pauseMonthsLeft(3, 5)).toBe(0);
		expect(pauseMonthsLeft(12, 0)).toBe(12);
	});

	it('explains a pause that would be refused', () => {
		expect(pauseProblem(1, 0)).toMatch(/used up/);
		expect(pauseProblem(0, 3)).toMatch(/at least one/);
		expect(pauseProblem(4, 3)).toMatch(/up to 3 months/);
		expect(pauseProblem(2, 1)).toMatch(/up to 1 month right/);
		expect(pauseProblem(3, 3)).toBeNull();
	});

	it('pushes back only what is unpaid and keeps the total owed', () => {
		const inst = [
			{ seq: 1, due_on: '2026-11-15', amount_cents: 10000, paid_cents: 10000 },
			{ seq: 2, due_on: '2026-12-15', amount_cents: 10000, paid_cents: 2500 },
			{ seq: 3, due_on: '2027-01-15', amount_cents: 10000, paid_cents: 0 }
		];
		const moved = pushBack(inst, 2);
		expect(moved).toEqual([
			{ seq: 2, from: '2026-12-15', to: '2027-02-15', amountCents: 7500 },
			{ seq: 3, from: '2027-01-15', to: '2027-03-15', amountCents: 10000 }
		]);
		expect(moved.reduce((a, m) => a + m.amountCents, 0)).toBe(17500);
	});

	it('clamps month ends the way Postgres does', () => {
		expect(pushBack([{ seq: 1, due_on: '2027-01-31', amount_cents: 1, paid_cents: 0 }], 1)[0].to).toBe('2027-02-28');
	});
});

describe('forgiveness', () => {
	it('refuses nothing left, nonsense and more than is owed', () => {
		expect(forgiveProblem(100, 0)).toMatch(/Nothing is left/);
		expect(forgiveProblem(null, 500)).toMatch(/Enter an amount/);
		expect(forgiveProblem(0, 500)).toMatch(/Enter an amount/);
		expect(forgiveProblem(501, 500)).toMatch(/more than is left/);
		expect(forgiveProblem(500, 500)).toBeNull();
	});

	it('adds up one tax year', () => {
		const rows = [
			{ tax_year: 2026, amount_cents: 500 },
			{ tax_year: 2025, amount_cents: 700 },
			{ tax_year: 2026, amount_cents: 250 }
		];
		expect(forgivenInYear(rows, 2026)).toBe(750);
	});
});

describe('sides and signatures', () => {
	it('works out the viewer’s side and whose signature is whose', () => {
		const loan = { borrower_id: 'maria', borrower_signed_at: 'b', lender_signed_at: null };
		expect(sideOf(loan, 'maria')).toBe('borrower');
		expect(sideOf(loan, 'sam')).toBe('lender');
		expect(signatures(loan, 'borrower')).toEqual({ you: 'b', them: null });
		expect(signatures(loan, 'lender')).toEqual({ you: null, them: 'b' });
	});

	it('formats the minimum rate', () => {
		expect(formatBps(412)).toBe('4.12%');
		expect(formatBps(0)).toBe('0.00%');
	});
});

describe('loanActions mirrors who each function lets in', () => {
	const base = {
		status: 'proposed' as const,
		side: 'lender' as const,
		youSigned: false,
		scheduleMatchesPrincipal: true,
		pauseMonthsLeft: 3,
		outstandingCents: 70000
	};

	it('lets either side set terms, set the schedule and sign while proposed', () => {
		expect(loanActions(base)).toEqual(['set_terms', 'set_schedule', 'sign']);
		expect(loanActions({ ...base, side: 'borrower' })).toEqual(['set_terms', 'set_schedule', 'sign']);
	});

	it('offers signing only with a full schedule and once', () => {
		expect(loanActions({ ...base, scheduleMatchesPrincipal: false })).not.toContain('sign');
		expect(loanActions({ ...base, youSigned: true })).not.toContain('sign');
	});

	it('offers nothing on a signed loan that has not been paid out', () => {
		expect(loanActions({ ...base, status: 'signed' })).toEqual([]);
		expect(loanActions({ ...base, status: 'signed', side: 'borrower' })).toEqual([]);
	});

	it('lets the borrower pause and resume, and the lender forgive, while collecting', () => {
		expect(loanActions({ ...base, status: 'active', side: 'borrower' })).toEqual(['pause']);
		expect(loanActions({ ...base, status: 'paused', side: 'borrower' })).toEqual(['pause', 'resume']);
		expect(loanActions({ ...base, status: 'paused', side: 'borrower', pauseMonthsLeft: 0 })).toEqual(['resume']);
		expect(loanActions({ ...base, status: 'active' })).toEqual(['forgive']);
		expect(loanActions({ ...base, status: 'active', outstandingCents: 0 })).toEqual([]);
	});

	it('offers nothing once a loan is closed', () => {
		for (const status of ['repaid', 'forgiven', 'defaulted', 'cancelled'] as const) {
			expect(loanActions({ ...base, status })).toEqual([]);
			expect(loanActions({ ...base, status, side: 'borrower' })).toEqual([]);
		}
	});
});
