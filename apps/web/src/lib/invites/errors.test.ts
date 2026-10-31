import { describe, expect, it } from 'vitest';
import { explainInviteError } from './errors';

const FALLBACK = /^The server refused this/;

describe('explainInviteError', () => {
	it('explains a used or expired invite and where to look', () => {
		const msg = explainInviteError({ code: 'P0002', message: 'invite not found, used or expired' });
		expect(msg).toMatch(/already been used or has expired/);
		expect(msg).toMatch(/Invites/);
	});

	it('explains own-request refusals', () => {
		expect(explainInviteError({ message: 'you cannot accept an invite to your own request' })).toMatch(
			/your own request/
		);
		expect(explainInviteError({ message: 'you cannot pledge to your own request' })).toMatch(/your own request/);
	});

	it('explains that lending needs verification and offers giving', () => {
		expect(explainInviteError({ message: 'only invited, verified family and friends can lend' })).toMatch(
			/verified members can lend.*give instead/
		);
	});

	it('names what is still needed when someone pledged first', () => {
		expect(explainInviteError({ message: 'pledge must be between 1 and 25050 cents' })).toBe(
			'Someone pledged while you were deciding: this request now needs $250.50. Pledge up to that.'
		);
		expect(explainInviteError({ message: 'pledge must be between 1 and 0 cents' })).toMatch(/fully pledged/);
	});

	it('explains a missing member row on accept', () => {
		expect(
			explainInviteError({
				code: '23503',
				message: 'insert or update on table "request_supporters" violates foreign key constraint'
			})
		).toMatch(/Finish setting up/);
	});

	it('explains the relationship length check', () => {
		expect(
			explainInviteError({
				code: '23514',
				message: 'new row for relation "request_invites" violates check constraint "request_invites_relationship_check"'
			})
		).toMatch(/1 to 40 characters/);
	});

	it('explains network and session failures', () => {
		expect(explainInviteError({ message: 'TypeError: Failed to fetch' })).toMatch(/Can’t reach/);
		expect(explainInviteError({ code: 'PGRST301', message: 'JWT expired' })).toMatch(/Sign in again/);
	});

	it('passes an unknown refusal through rather than hiding it', () => {
		expect(explainInviteError({ message: 'some new rule' })).toBe('The server refused this: “some new rule”');
		expect(explainInviteError(null)).toMatch(/nothing was saved/);
	});
});

// Guard: every refusal create_invite, accept_invite and pledge can raise has a
// plain explanation. Reads the latest definition of each from the migrations,
// so a new `raise exception` there fails this until it is mapped.
describe('explainInviteError covers the invite and pledge functions', () => {
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

	for (const fn of ['create_invite', 'accept_invite', 'pledge']) {
		it(`maps every refusal in ${fn}`, () => {
			const messages = [...latestBody(fn).matchAll(/raise exception '((?:[^']|'')*)'/g)].map((m) =>
				m[1].replaceAll("''", "'").replaceAll('%', '500')
			);
			expect(messages.length).toBeGreaterThan(0);
			for (const message of messages) {
				expect(explainInviteError({ message }), message).not.toMatch(FALLBACK);
			}
		});
	}
});
