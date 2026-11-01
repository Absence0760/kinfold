/**
 * Failures from Supabase (auth and data reads) in plain words.
 *
 * Pure: no client, no DOM. The sign-in page, the member-area layout, the home
 * page and the error pages turn whatever they caught into one of these, so a
 * dropped connection, an ended session and a server refusal never share one
 * vague message.
 */

/** The parts of an AuthError, PostgrestError or thrown Error this reads. */
interface ErrorLike {
	name?: string;
	code?: string;
	status?: number;
	message?: string;
}

function asErrorLike(e: unknown): ErrorLike {
	return typeof e === 'object' && e !== null ? (e as ErrorLike) : { message: String(e ?? '') };
}

/** `fetch` itself failed: offline, DNS, CORS, or the server is down. Browser wording varies. */
const NETWORK_MESSAGE = /failed to fetch|networkerror|fetch failed|load failed|network request failed/i;

/**
 * A data read (a PostgREST select or RPC) that came back with an error. Keeps
 * the PostgREST `code` and the HTTP `status` (0 when the request never got an
 * answer), which the caller needs to tell a dropped connection from an ended
 * session from a refusal.
 */
export class LoadError extends Error {
	/** What was being read, in the member's words ("your loans"). */
	readonly what: string;
	readonly code: string;
	readonly status: number | null;
	/** The server's own message, for the "details" line. */
	readonly detail: string;

	constructor(what: string, error: { message?: string; code?: string }, status?: number | null) {
		const detail = error.message ?? '';
		super(`Couldn't load ${what}: ${detail || 'unknown error'}`);
		this.name = 'LoadError';
		this.what = what;
		this.code = error.code ?? '';
		this.status = status ?? null;
		this.detail = detail;
	}
}

export type LoadFailure = 'session' | 'network' | 'server';

/**
 * Why a read failed:
 * - `session`: the sign-in is no longer valid (expired or rejected JWT, no
 *   session). Retrying can't help; the member has to sign in again.
 * - `network`: no answer, or a gateway error. Retrying may help.
 * - `server`: the server answered and refused (a policy, a bug). Shown with its reason.
 */
export function classifyLoadError(e: unknown): LoadFailure {
	const { name = '', code = '', status, message = '' } = asErrorLike(e);
	if (
		status === 401 ||
		/^PGRST30[123]$/.test(code) ||
		/jwt/i.test(message) ||
		name === 'AuthSessionMissingError' ||
		name === 'AuthInvalidJwtError' ||
		name === 'AuthInvalidTokenResponseError'
	)
		return 'session';
	if (
		status === 0 ||
		(status !== undefined && status !== null && status >= 502 && status <= 504) ||
		name === 'AuthRetryableFetchError' ||
		NETWORK_MESSAGE.test(message)
	)
		return 'network';
	return 'server';
}

export interface LoadProblem {
	kind: LoadFailure;
	/** Short heading. */
	title: string;
	/** What happened and what to do, in plain words. */
	body: string;
	/** The server's own message, when it gave one (shown small, for support). */
	detail: string | null;
}

/**
 * A failed load as a heading, a plain sentence and the server's detail.
 * `subject` is what didn't load ("your home", "your account").
 */
export function loadProblem(e: unknown, subject: string): LoadProblem {
	const kind = classifyLoadError(e);
	const err = asErrorLike(e);
	const what = e instanceof LoadError ? e.what : null;
	const detail = (e instanceof LoadError ? e.detail : err.message) || null;
	if (kind === 'session')
		return {
			kind,
			title: 'Your session has ended',
			body: `Sign in again to see ${subject}. Nothing on your account has changed.`,
			detail: null
		};
	if (kind === 'network')
		return {
			kind,
			title: 'Can’t reach Kinfold',
			body: `${capitalize(subject)} didn’t load because the connection dropped or Kinfold isn’t answering. Nothing was lost. Check your signal and try again.`,
			detail: null
		};
	return {
		kind,
		title: `We couldn’t load ${subject}`,
		body: `${what ? `Kinfold refused to load ${what}` : 'Kinfold refused the request'}. Nothing on your account has changed. Try again in a minute; if it keeps happening, the problem is on our side.`,
		detail
	};
}

function capitalize(s: string): string {
	return s.charAt(0).toUpperCase() + s.slice(1);
}

export type SignInFailure =
	| 'invalid-credentials'
	| 'rate-limited'
	| 'unconfirmed'
	| 'banned'
	| 'network'
	| 'server'
	| 'unknown';

/** Which sign-in failure this is, from Supabase Auth's error `code`, then `status`, then the message. */
export function classifySignInError(e: unknown): SignInFailure {
	const { name = '', code = '', status, message = '' } = asErrorLike(e);
	if (code === 'invalid_credentials' || /invalid login credentials/i.test(message)) return 'invalid-credentials';
	if (code === 'over_request_rate_limit' || status === 429 || /rate limit|too many/i.test(message))
		return 'rate-limited';
	if (code === 'email_not_confirmed' || /email not confirmed/i.test(message)) return 'unconfirmed';
	if (code === 'user_banned') return 'banned';
	if (name === 'AuthRetryableFetchError' && status !== undefined && status >= 500) return 'server';
	if (status === 0 || name === 'AuthRetryableFetchError' || NETWORK_MESSAGE.test(message)) return 'network';
	if (status !== undefined && status >= 500) return 'server';
	return 'unknown';
}

/** A message for the page: text, plus a shell command to show as code (dev builds only). */
export interface Notice {
	text: string;
	command?: string;
}

/**
 * The sign-in error to show. Developer instructions (`pnpm ...`) appear only
 * when `dev` is true; a production member gets plain words.
 */
export function signInNotice(e: unknown, dev: boolean): Notice {
	switch (classifySignInError(e)) {
		case 'invalid-credentials':
			return { text: 'That email and password don’t match an account. Check both and try again.' };
		case 'rate-limited':
			return { text: 'Too many sign-in attempts. Wait a minute, then try again.' };
		case 'unconfirmed':
			return {
				text: 'This email address hasn’t been confirmed yet. Open the confirmation link in the email we sent you, then sign in.'
			};
		case 'banned':
			return {
				text: 'This account can’t sign in right now. Ask the member who invited you to contact the Kinfold team.'
			};
		case 'network':
			return dev
				? { text: 'Can’t reach the local backend. Start it with', command: 'pnpm dev:db:up' }
				: { text: 'Can’t reach Kinfold. Check your connection and try again.' };
		case 'server':
			return dev
				? { text: 'The local backend answered with a server error. Check it with', command: 'pnpm dev:db:status' }
				: { text: 'Kinfold isn’t responding right now. Nothing was changed. Try again in a few minutes.' };
		default: {
			const message = asErrorLike(e).message;
			return {
				text: message
					? `Sign-in didn’t work: “${message}”. Try again in a minute.`
					: 'Sign-in didn’t work. Try again in a minute.'
			};
		}
	}
}

/** The notice when the build has no Supabase key. */
export function notConfiguredNotice(dev: boolean): Notice {
	return dev
		? {
				text: 'The member area has no Supabase key. Start it with the command below, which reads the key from the running local stack:',
				command: 'pnpm dev:run:web'
			}
		: { text: 'Signing in isn’t available right now. Please try again later.' };
}

export interface ErrorPageCopy {
	title: string;
	body: string;
	/** Worth offering "Try again" (not for a page that doesn't exist). */
	retry: boolean;
}

/** SvelteKit's own placeholder messages, which say nothing to a member. */
const GENERIC_KIT_MESSAGE = /^(internal error|error: \d+|not found)$/i;

/**
 * Words for the error page from SvelteKit's status and message. A message the
 * app set with `error(status, message)` is already plain and is shown; Kit's
 * placeholders ("Internal Error") are replaced.
 */
export function errorPageCopy(status: number, message: string | null | undefined): ErrorPageCopy {
	const own = message && !GENERIC_KIT_MESSAGE.test(message.trim()) ? message : null;
	if (status === 404)
		return {
			title: 'We can’t find that page',
			body: 'The link may be old or mistyped.',
			retry: false
		};
	if (status === 503)
		return {
			title: 'Can’t reach Kinfold',
			body: own ?? 'The connection dropped or Kinfold isn’t answering. Nothing was lost. Check your signal and try again.',
			retry: true
		};
	return {
		title: 'Something went wrong',
		body: own ?? 'This page didn’t load. Nothing on your account has changed. Try again in a minute.',
		retry: true
	};
}
