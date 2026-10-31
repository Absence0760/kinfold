import { describe, expect, it } from 'vitest';
import { EVIDENCE_LOCKED, NOT_EDITABLE, explainRequestError } from './errors';

const FALLBACK = /^The server refused this/;

describe('explainRequestError', () => {
	it('explains the submit refusals', () => {
		expect(explainRequestError({ message: 'verify your identity before submitting a request' })).toMatch(
			/Verify your identity/
		);
		expect(explainRequestError({ message: 'name who should be paid (a shop, lender or seller)' })).toMatch(
			/never to you/
		);
		expect(explainRequestError({ message: 'add at least one piece of evidence' })).toMatch(/photo or an estimate/);
		expect(
			explainRequestError({ message: 'check and confirm the redacted copy of every piece of evidence' })
		).toMatch(/redacted copy/);
		expect(
			explainRequestError({ message: 'only drafts and requests needing evidence can be submitted' })
		).toMatch(/already been sent/);
	});

	it('fills in the pool rules from the message', () => {
		expect(explainRequestError({ message: 'the community pool does not cover loan_payoff requests yet' })).toBe(
			'The community pool doesn’t cover loan payoff requests yet. Ask family and friends instead.'
		);
		expect(explainRequestError({ message: 'the pool pays at most 1000000 cents per request' })).toMatch(
			/at most \$10,000 per request/
		);
		expect(
			explainRequestError({
				message: 'pool cover starts 60 days after your first payment; ask your people instead'
			})
		).toMatch(/starts 60 days after your first dues payment/);
		expect(
			explainRequestError({ message: 'the vehicle must be registered with Kinfold 60 days before the incident' })
		).toMatch(/at least 60 days/);
	});

	it('explains appeals: one per refusal', () => {
		expect(explainRequestError({ code: '23505', message: 'this refusal has already been appealed' })).toMatch(
			/appealed once/
		);
		expect(explainRequestError({ message: 'only a refused request of yours can be appealed' })).toMatch(
			/isn’t declined now/
		);
		expect(
			explainRequestError({
				code: '23514',
				message: 'new row for relation "appeals" violates check constraint "appeals_reason_check"'
			})
		).toMatch(/10 to 2,000/);
	});

	it('explains the table checks on a draft', () => {
		const check = (c: string) => `new row for relation "requests" violates check constraint "${c}"`;
		expect(explainRequestError({ message: check('requests_title_check') })).toMatch(/1 to 120/);
		expect(explainRequestError({ message: check('requests_description_check') })).toMatch(/5,000/);
		expect(explainRequestError({ message: check('requests_amount_cents_check') })).toMatch(/more than \$0/);
		expect(explainRequestError({ message: check('requests_check') })).toMatch(/day you started/);
		expect(
			explainRequestError({
				message: 'insert or update on table "requests" violates foreign key constraint "requests_payee_id_fkey"'
			})
		).toMatch(/Choose again/);
	});

	it('explains the row-level security refusals by table', () => {
		expect(
			explainRequestError({ code: '42501', message: 'new row violates row-level security policy for table "evidence"' })
		).toMatch(/draft or needs more evidence/);
		expect(
			explainRequestError({ message: 'new row violates row-level security policy for table "objects"' })
		).toMatch(/draft or needs more evidence/);
		expect(
			explainRequestError({ message: 'new row violates row-level security policy for table "requests"' })
		).toMatch(/Only drafts can be changed/);
	});

	it('explains the data layer’s own refusals', () => {
		expect(explainRequestError({ message: NOT_EDITABLE })).toMatch(/isn’t a draft any more/);
		expect(explainRequestError({ message: EVIDENCE_LOCKED })).toMatch(/can be removed only/);
	});

	it('explains network and session failures', () => {
		expect(explainRequestError({ message: 'TypeError: Failed to fetch' })).toMatch(/Can’t reach/);
		expect(explainRequestError({ code: 'PGRST301', message: 'JWT expired' })).toMatch(/Sign in again/);
	});

	it('passes an unknown refusal through rather than hiding it', () => {
		expect(explainRequestError({ message: 'some new rule' })).toBe('The server refused this: “some new rule”');
		expect(explainRequestError(null)).toMatch(/nothing was saved/);
	});
});

// Guard: every refusal the member's request functions can raise has a plain
// explanation. Reads the latest definition of each from the migrations, so a
// new `raise exception` there fails this until it is mapped.
describe('explainRequestError covers the request functions', () => {
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
		// Definitions only: grants and revokes also say "function public.<name>(".
		const re = new RegExp(`create (?:or replace )?function public\\.${name}\\(`, 'g');
		let last = -1;
		for (const m of sql.matchAll(re)) last = m.index ?? last;
		expect(last, `${name} not found in migrations`).toBeGreaterThan(-1);
		const start = sql.indexOf('$$', last);
		const end = sql.indexOf('$$', start + 2);
		return sql.slice(start, end);
	}

	for (const fn of ['submit_request', 'withdraw_request', 'confirm_redaction', 'confirm_public_summary', 'file_appeal']) {
		it(`maps every refusal in ${fn}`, () => {
			const messages = [...latestBody(fn).matchAll(/raise exception '((?:[^']|'')*)'/g)].map((m) =>
				// '%' is filled in at runtime: with a kind, a cents amount or a day count.
				m[1].replaceAll("''", "'").replaceAll('%', '60')
			);
			expect(messages.length).toBeGreaterThan(0);
			for (const message of messages) {
				expect(explainRequestError({ message }), message).not.toMatch(FALLBACK);
			}
		});
	}
});
