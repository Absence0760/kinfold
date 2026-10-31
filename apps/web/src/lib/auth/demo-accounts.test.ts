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

describe('DEMO_ACCOUNTS', () => {
	it('lists the four seeded people once each', () => {
		const emails = DEMO_ACCOUNTS.map((a) => a.email);
		expect(new Set(emails).size).toBe(4);
		expect(emails).toEqual(['maria@test.com', 'sam@test.com', 'james@test.com', 'priya@test.com']);
	});
});
