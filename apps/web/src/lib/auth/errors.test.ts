import { describe, expect, it } from 'vitest';
import {
	classifyLoadError,
	classifySignInError,
	errorPageCopy,
	loadProblem,
	LoadError,
	notConfiguredNotice,
	signInNotice
} from './errors.ts';

/** Shaped like supabase-js's AuthApiError / AuthRetryableFetchError. */
function authError(name: string, message: string, status: number, code?: string) {
	return Object.assign(new Error(message), { name, status, code });
}

describe('classifySignInError', () => {
	it('reads Supabase Auth error codes', () => {
		expect(classifySignInError(authError('AuthApiError', 'Invalid login credentials', 400, 'invalid_credentials'))).toBe(
			'invalid-credentials'
		);
		expect(classifySignInError(authError('AuthApiError', 'Request rate limit reached', 429, 'over_request_rate_limit'))).toBe(
			'rate-limited'
		);
		expect(classifySignInError(authError('AuthApiError', 'Email not confirmed', 400, 'email_not_confirmed'))).toBe(
			'unconfirmed'
		);
		expect(classifySignInError(authError('AuthApiError', 'User is banned', 400, 'user_banned'))).toBe('banned');
	});

	it('falls back to status and message when an older Auth server sends no code', () => {
		expect(classifySignInError(authError('AuthApiError', 'Invalid login credentials', 400))).toBe('invalid-credentials');
		expect(classifySignInError(authError('AuthApiError', 'Slow down', 429))).toBe('rate-limited');
		expect(classifySignInError(authError('AuthApiError', 'Email not confirmed', 400))).toBe('unconfirmed');
	});

	it('tells a dropped connection from a server that is down', () => {
		expect(classifySignInError(authError('AuthRetryableFetchError', 'Failed to fetch', 0))).toBe('network');
		expect(classifySignInError(new TypeError('NetworkError when attempting to fetch resource.'))).toBe('network');
		expect(classifySignInError(authError('AuthRetryableFetchError', 'Bad Gateway', 502))).toBe('server');
		expect(classifySignInError(authError('AuthApiError', 'boom', 500))).toBe('server');
	});

	it('leaves anything else as unknown', () => {
		expect(classifySignInError(authError('AuthApiError', 'Signups not allowed', 422, 'signup_disabled'))).toBe('unknown');
		expect(classifySignInError('weird')).toBe('unknown');
	});
});

describe('signInNotice', () => {
	const offline = authError('AuthRetryableFetchError', 'Failed to fetch', 0);

	it('never shows a pnpm command in a production build', () => {
		const cases = [
			offline,
			authError('AuthRetryableFetchError', 'Bad Gateway', 502),
			authError('AuthApiError', 'Invalid login credentials', 400, 'invalid_credentials'),
			authError('AuthApiError', 'x', 429, 'over_request_rate_limit'),
			authError('AuthApiError', 'x', 400, 'email_not_confirmed'),
			authError('AuthApiError', 'x', 400, 'user_banned'),
			new Error('something odd')
		];
		for (const e of cases) {
			const notice = signInNotice(e, false);
			expect(notice.command).toBeUndefined();
			expect(notice.text).not.toMatch(/pnpm|backend|supabase/i);
		}
		expect(notConfiguredNotice(false).command).toBeUndefined();
		expect(notConfiguredNotice(false).text).not.toMatch(/pnpm|supabase/i);
	});

	it('gives developers the command to fix the local stack', () => {
		expect(signInNotice(offline, true)).toEqual({
			text: 'Can’t reach the local backend. Start it with',
			command: 'pnpm dev:db:up'
		});
		expect(notConfiguredNotice(true).command).toBe('pnpm dev:run:web');
	});

	it('says what went wrong, not always "wrong password"', () => {
		expect(signInNotice(offline, false).text).toBe('Can’t reach Kinfold. Check your connection and try again.');
		expect(signInNotice(authError('AuthApiError', 'x', 429, 'over_request_rate_limit'), false).text).toMatch(
			/too many sign-in attempts/i
		);
		expect(signInNotice(authError('AuthApiError', 'x', 400, 'email_not_confirmed'), false).text).toMatch(
			/hasn’t been confirmed/
		);
		expect(signInNotice(authError('AuthApiError', 'x', 400, 'invalid_credentials'), false).text).toMatch(
			/don’t match an account/
		);
	});

	it('passes an unrecognised message through rather than hiding it', () => {
		expect(signInNotice(authError('AuthApiError', 'Signups not allowed', 422, 'signup_disabled'), false).text).toBe(
			'Sign-in didn’t work: “Signups not allowed”. Try again in a minute.'
		);
	});
});

describe('classifyLoadError', () => {
	it('reads an expired or rejected session', () => {
		expect(classifyLoadError(new LoadError('your home', { code: 'PGRST301', message: 'JWT expired' }, 401))).toBe('session');
		expect(classifyLoadError(new LoadError('your home', { code: 'PGRST303', message: 'JWT expired' }, 401))).toBe('session');
		expect(classifyLoadError(new LoadError('your home', { message: 'no auth' }, 401))).toBe('session');
		expect(classifyLoadError(authError('AuthSessionMissingError', 'Auth session missing!', 400))).toBe('session');
	});

	it('reads a request that never got an answer', () => {
		// postgrest-js reports a failed fetch as status 0 with an empty code.
		expect(classifyLoadError(new LoadError('your home', { code: '', message: 'TypeError: Failed to fetch' }, 0))).toBe(
			'network'
		);
		expect(classifyLoadError(new LoadError('your home', { message: 'Bad Gateway' }, 502))).toBe('network');
		expect(classifyLoadError(authError('AuthRetryableFetchError', 'Load failed', 0))).toBe('network');
	});

	it('treats anything else as a server refusal', () => {
		expect(
			classifyLoadError(new LoadError('your loans', { code: '42501', message: 'permission denied for table family_loans' }, 403))
		).toBe('server');
		expect(classifyLoadError(new Error('boom'))).toBe('server');
	});
});

describe('loadProblem', () => {
	it('asks for a new sign-in when the session ended, without a server message', () => {
		const p = loadProblem(new LoadError('your loans', { code: 'PGRST301', message: 'JWT expired' }, 401), 'your home');
		expect(p).toEqual({
			kind: 'session',
			title: 'Your session has ended',
			body: 'Sign in again to see your home. Nothing on your account has changed.',
			detail: null
		});
	});

	it('says the connection dropped and nothing was lost', () => {
		const p = loadProblem(new LoadError('your loans', { message: 'TypeError: Failed to fetch' }, 0), 'your account');
		expect(p.kind).toBe('network');
		expect(p.title).toBe('Can’t reach Kinfold');
		expect(p.body).toMatch(/^Your account didn’t load because the connection dropped/);
		expect(p.body).toMatch(/Nothing was lost/);
	});

	it('names what was refused and keeps the server detail', () => {
		const p = loadProblem(
			new LoadError('your loans', { code: '42501', message: 'permission denied for table family_loans' }, 403),
			'your home'
		);
		expect(p.kind).toBe('server');
		expect(p.title).toBe('We couldn’t load your home');
		expect(p.body).toMatch(/^Kinfold refused to load your loans\./);
		expect(p.detail).toBe('permission denied for table family_loans');
	});
});

describe('LoadError', () => {
	it('keeps the code, status and a readable message', () => {
		const e = new LoadError('your requests', { code: '42501', message: 'permission denied' }, 403);
		expect(e).toBeInstanceOf(Error);
		expect(e.message).toBe("Couldn't load your requests: permission denied");
		expect([e.code, e.status, e.what, e.detail]).toEqual(['42501', 403, 'your requests', 'permission denied']);
	});
});

describe('errorPageCopy', () => {
	it('shows the plain message the app set', () => {
		expect(errorPageCopy(503, 'Your account didn’t load because the connection dropped.')).toEqual({
			title: 'Can’t reach Kinfold',
			body: 'Your account didn’t load because the connection dropped.',
			retry: true
		});
	});

	it('replaces SvelteKit placeholders with plain words', () => {
		const copy = errorPageCopy(500, 'Internal Error');
		expect(copy.body).not.toMatch(/internal error/i);
		expect(copy.body).toMatch(/Nothing on your account has changed/);
		expect(copy.retry).toBe(true);
		expect(errorPageCopy(503, 'Error: 503').body).toMatch(/Check your signal/);
	});

	it('offers no retry for a page that does not exist', () => {
		expect(errorPageCopy(404, 'Not Found')).toEqual({
			title: 'We can’t find that page',
			body: 'The link may be old or mistyped.',
			retry: false
		});
	});
});
