import { describe, expect, it } from 'vitest';
import { explainLoanError } from './errors.ts';

const FALLBACK = /^The server refused this/;

describe('explainLoanError', () => {
	it('explains not-yours and fixed-after-signing', () => {
		expect(explainLoanError({ code: 'P0002', message: 'loan not found' })).toMatch(/isn’t yours/);
		expect(explainLoanError({ message: "a signed loan's terms can only change by agreement (restructure)" })).toMatch(
			/fixed/
		);
	});

	it('explains the pause allowance with its numbers', () => {
		expect(
			explainLoanError({ message: 'this loan allows 3 pause months a year (2 used); ask your lender to restructure' })
		).toBe('This loan allows 3 pause months a year and 2 are used. For more time, agree a new schedule with your lender.');
		expect(
			explainLoanError({ message: 'this loan allows 1 pause months a year (1 used); ask your lender to restructure' })
		).toMatch(/1 pause month a year and 1 is used/);
	});

	it('explains restructure refusals', () => {
		expect(
			explainLoanError({
				message: 'this loan owes nothing, so there is nothing to restructure',
				code: 'P0002'
			})
		).toMatch(/nothing to restructure/);
		expect(
			explainLoanError({
				message: 'too many installments for what is left to pay'
			})
		).toMatch(/more installments than there are cents/);
		expect(
			explainLoanError({
				message: 'a restructure the other side has not signed yet is already pending'
			})
		).toMatch(/waiting for your side to sign/);
		expect(
			explainLoanError({
				message: "the borrower’s pause runs until 2027-01-15"
			})
		).toMatch(/pause hasn’t ended yet/);
	});

	it('explains signing refusals', () => {
		expect(explainLoanError({ message: 'loan is already signed' })).toMatch(/already signed/);
		expect(explainLoanError({ message: 'loan is already active' })).toMatch(/past signing/);
		expect(explainLoanError({ message: 'set a repayment schedule that adds up to the amount lent' })).toMatch(
			/exactly the amount lent/
		);
	});

	it('explains forgiveness refusals and the no-interest total check', () => {
		expect(explainLoanError({ code: '42501', message: 'only the lender can forgive an active loan' })).toMatch(
			/Only the lender/
		);
		expect(explainLoanError({ message: 'payments and forgiveness exceed the principal' })).toMatch(/more than is left/);
		expect(
			explainLoanError({
				message: 'new row for relation "loan_forgiveness" violates check constraint "loan_forgiveness_amount_cents_check"'
			})
		).toMatch(/above zero/);
	});

	it('explains network, session and permission failures', () => {
		expect(explainLoanError({ message: 'TypeError: Failed to fetch' })).toMatch(/Can’t reach/);
		expect(explainLoanError({ code: 'PGRST301', message: 'JWT expired' })).toMatch(/Sign in again/);
		expect(explainLoanError({ code: '42501', message: 'permission denied for function apply_default_plan' })).toMatch(
			/isn’t allowed/
		);
	});

	it('passes an unknown refusal through rather than hiding it', () => {
		expect(explainLoanError({ message: 'some new rule' })).toBe('The server refused this: “some new rule”');
		expect(explainLoanError(null)).toMatch(/nothing was changed/);
	});
});

// Guard: every refusal the member-callable loan functions can raise has a
// plain explanation. Reads the latest definition of each from the migrations,
// so a new `raise exception` there fails this until it is mapped.
describe('explainLoanError covers the loan functions', () => {
	const files = import.meta.glob<string>('../../../../backend/supabase/migrations/*.sql', {
		query: '?raw',
		import: 'default',
		eager: true
	});
	const sql = Object.keys(files)
		.sort()
		.map((f) => files[f])
		.join('\n');

	function latestBody(name: string): string {
		const re = new RegExp(`function ${name.replace('.', '\\.')}\\(`, 'g');
		let last = -1;
		for (const m of sql.matchAll(re)) last = m.index ?? last;
		expect(last, `${name} not found in migrations`).toBeGreaterThan(-1);
		const start = sql.indexOf('$$', last);
		const end = sql.indexOf('$$', start + 2);
		return sql.slice(start, end);
	}

	const fns = [
		'public.set_loan_terms',
		'public.set_loan_schedule',
		'public.sign_loan',
		'public.forgive_loan',
		'public.pause_loan',
		'public.resume_loan',
		// The constraint trigger behind the schedule and forgiveness totals.
		'private.check_loan_totals'
	];
	for (const fn of fns) {
		it(`maps every refusal in ${fn}`, () => {
			const messages = [...latestBody(fn).matchAll(/raise exception '((?:[^']|'')*)'/g)].map((m) =>
				m[1].replaceAll("''", "'").replaceAll('%', '7')
			);
			expect(messages.length).toBeGreaterThan(0);
			for (const message of messages) {
				expect(explainLoanError({ message }), message).not.toMatch(FALLBACK);
			}
		});
	}

	it('maps the check constraints a member can hit', () => {
		for (const name of [
			'loan_pauses_months_check',
			'loan_pauses_reason_check',
			'loan_forgiveness_amount_cents_check',
			'loan_forgiveness_tax_year_check',
			'family_loans_repay_on_sale_needs_lien'
		]) {
			expect(explainLoanError({ message: `violates check constraint "${name}"` }), name).not.toMatch(FALLBACK);
		}
	});

	// The page explains the default plan instead of offering a button, because
	// members can't call apply_default_plan. If a migration ever grants it,
	// this fails so the page can be revisited.
	it('keeps apply_default_plan service-only', () => {
		const memberGrants = sql
			.replace(/--[^\n]*/g, '')
			.split(';')
			.filter((s) => /grant\s+execute\s+on\s+function/i.test(s) && /\bto\b[^;]*\bauthenticated\b/i.test(s));
		expect(memberGrants.length).toBeGreaterThan(0);
		expect(memberGrants.some((s) => s.includes('apply_default_plan'))).toBe(false);
	});
});

describe('Fund loan doors read in the Fund\u2019s words', () => {
	it('explains a Fund loan the borrower cannot change', () => {
		expect(explainLoanError({ message: 'fund loan not found' })).not.toMatch(FALLBACK);
		expect(explainLoanError({ message: 'fund loan is already repaid' })).not.toMatch(FALLBACK);
		expect(explainLoanError({ message: 'this loan allows 3 pause months a year (3 used); ask the lending Fund to restructure' }))
			.toMatch(/lending Fund/);
	});

	it('points at the Fund, not a lender member', () => {
		expect(explainLoanError({ message: 'income schedules are computed from income; nothing to reschedule' }))
			.not.toMatch(FALLBACK);
		expect(explainLoanError({ message: 'a restructure the partner has not answered yet is already pending' }))
			.not.toMatch(FALLBACK);
		expect(explainLoanError({ message: 'income due for this month is not owed' })).not.toMatch(FALLBACK);
	});

	it('explains the fair-lending self-test doors', () => {
		expect(explainLoanError({ message: 'this loan\u2019s self-test data is already recorded' })).not.toMatch(FALLBACK);
		expect(explainLoanError({ message: 'the self-test needs all four disclosures acknowledged' })).not.toMatch(FALLBACK);
		expect(explainLoanError({ message: 'fund loan secured by the home answers on the government monitoring form, not a self-test' })).not.toMatch(FALLBACK);
	});

	it('keeps the family-lender allowance message distinct', () => {
		expect(explainLoanError({ message: 'this loan allows 3 pause months a year (1 used)' })).toMatch(/your lender/);
	});
});
