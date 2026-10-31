import { describe, expect, it } from 'vitest';
import { explainDbError } from './errors';

const FALLBACK = /^The server refused this/;

describe('explainDbError', () => {
	it('explains the same-region block', () => {
		const msg = explainDbError({
			code: '42501',
			message: "requests are reviewed by someone outside the member's region"
		});
		expect(msg).toMatch(/your own state/);
	});

	it('explains self-review and missing roles', () => {
		expect(explainDbError({ message: 'you cannot review your own request' })).toMatch(/your own request/);
		expect(explainDbError({ message: 'reviewers only' })).toMatch(/reviewer role/);
		expect(explainDbError({ message: 'appeal panel only' })).toMatch(/appeal panel role/);
	});

	it('says only an appeal reopens a refused request', () => {
		expect(explainDbError({ message: 'request is not reviewable in status refused' })).toMatch(
			/Only an upheld appeal/
		);
	});

	it('names any other unreviewable status in plain words', () => {
		expect(explainDbError({ message: 'request is not reviewable in status paid' })).toBe(
			'This request is now “Paid”, so it can’t be reviewed. Refresh the queue.'
		);
	});

	it('explains the reason length check', () => {
		expect(
			explainDbError({
				code: '23514',
				message: 'new row for relation "reviews" violates check constraint "reviews_reason_check"'
			})
		).toBe('The reason must be 10 to 2,000 characters.');
	});

	it('explains the appeal blocks', () => {
		expect(explainDbError({ message: 'you cannot decide your own appeal' })).toMatch(/own appeal/);
		expect(
			explainDbError({ message: 'you reviewed this request; another panel member decides the appeal' })
		).toMatch(/another panel member/);
		expect(explainDbError({ code: 'P0002', message: 'appeal not found or already decided' })).toMatch(
			/already been decided/
		);
	});

	it('explains network and session failures', () => {
		expect(explainDbError({ message: 'TypeError: Failed to fetch' })).toMatch(/Can’t reach/);
		expect(explainDbError({ code: 'PGRST301', message: 'JWT expired' })).toMatch(/Sign in again/);
	});

	it('passes an unknown refusal through rather than hiding it', () => {
		expect(explainDbError({ message: 'some new rule' })).toBe('The server refused this: “some new rule”');
		expect(explainDbError(null)).toMatch(/nothing was saved/);
		expect(explainDbError({})).toMatch(/nothing was saved/);
	});
});

// Guard: every refusal record_review and decide_appeal can raise has a plain
// explanation. Reads the latest definition of each from the migrations, so a
// new `raise exception` there fails this until it is mapped.
describe('explainDbError covers the review functions', () => {
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
		const re = new RegExp(`function public\\.${name}\\(`, 'g');
		let last = -1;
		for (const m of sql.matchAll(re)) last = m.index ?? last;
		expect(last, `${name} not found in migrations`).toBeGreaterThan(-1);
		const start = sql.indexOf('$$', last);
		const end = sql.indexOf('$$', start + 2);
		return sql.slice(start, end);
	}

	for (const fn of ['record_review', 'decide_appeal']) {
		it(`maps every refusal in ${fn}`, () => {
			const messages = [...latestBody(fn).matchAll(/raise exception '((?:[^']|'')*)'/g)].map((m) =>
				m[1].replaceAll("''", "'").replaceAll('%', 'refused')
			);
			expect(messages.length).toBeGreaterThan(0);
			for (const message of messages) {
				expect(explainDbError({ message }), message).not.toMatch(FALLBACK);
			}
		});
	}
});
