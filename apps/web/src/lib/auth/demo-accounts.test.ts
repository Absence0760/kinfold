import { describe, expect, it } from 'vitest';
import { DEMO_ACCOUNTS, demoSignInAllowed } from './demo-accounts';

describe('demoSignInAllowed', () => {
	it('allows a dev build against the local stack', () => {
		expect(demoSignInAllowed(true, 'http://127.0.0.1:54721')).toBe(true);
		expect(demoSignInAllowed(true, 'http://localhost:54721')).toBe(true);
		expect(demoSignInAllowed(true, 'http://[::1]:54721')).toBe(true);
	});

	it('never allows a production build', () => {
		expect(demoSignInAllowed(false, 'http://127.0.0.1:54721')).toBe(false);
	});

	it('refuses a dev build pointed at a real project', () => {
		expect(demoSignInAllowed(true, 'https://abc.supabase.co')).toBe(false);
		expect(demoSignInAllowed(true, 'https://127.0.0.1.evil.example')).toBe(false);
	});

	it('refuses a malformed URL', () => {
		expect(demoSignInAllowed(true, '')).toBe(false);
		expect(demoSignInAllowed(true, 'not a url')).toBe(false);
	});
});

// This workspace has no Node types, so read the seed through Node's own loader.
type Fs = { readFileSync: (path: URL, encoding: 'utf8') => string };
const fs = (globalThis as unknown as { process: { getBuiltinModule: (id: string) => Fs } }).process.getBuiltinModule(
	'node:fs'
);
const seed = fs.readFileSync(new URL('../../../../backend/supabase/seed.sql', import.meta.url), 'utf8');

describe('DEMO_ACCOUNTS', () => {
	it('lists the seven demo people once each', () => {
		const emails = DEMO_ACCOUNTS.map((a) => a.email);
		expect(new Set(emails).size).toBe(7);
		expect(emails).toEqual([
			'maria@test.com',
			'sam@test.com',
			'james@test.com',
			'priya@test.com',
			'kofi@test.com',
			'ben@test.com',
			'nora@test.com'
		]);
	});

	it('offers only people the seed creates, each named in its demo-login header', () => {
		const header = seed.slice(0, seed.indexOf('-- --- people'));
		for (const { email } of DEMO_ACCOUNTS) {
			expect(seed, `${email} is created by seed.sql`).toContain(`'${email}'`);
			expect(header, `${email} is in seed.sql's demo-login list`).toContain(email);
		}
	});
});
