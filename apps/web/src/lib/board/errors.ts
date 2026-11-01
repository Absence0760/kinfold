/** The parts of a PostgrestError (or any thrown error) this needs. */
export interface DbError {
	code?: string;
	message?: string;
}

/**
 * Why the board didn't load, in plain words, with what to do next. Reading the
 * board is a plain select under RLS, so the causes are few: an ended session,
 * an account that isn't allowed to see the board (yet), or no connection.
 * Unlike a refusal on an action, a failed read has nothing a member can act on
 * in the database's own wording, so nothing raw is ever shown here; the
 * original error stays on the thrown value for debugging.
 */
export function explainBoardError(error: DbError | null | undefined): string {
	const message = error?.message ?? '';
	const code = error?.code ?? '';

	if (code === 'PGRST301' || code === 'PGRST303' || /jwt expired/i.test(message))
		return 'Your session has ended. Sign in again to see the board.';
	if (code === '42501' || /permission denied/i.test(message))
		return 'Your account can’t see the board right now. Only verified members can, so check that your identity check is done, then try again.';
	if (/failed to fetch|networkerror|fetch failed|load failed|network request failed/i.test(message))
		return 'Can’t reach Kinfold. Check your connection and try again.';

	return 'Something went wrong on our side while reading the board. Try again in a moment.';
}

/** An error that keeps the database's code, so `explainBoardError` can read it. */
export class BoardLoadError extends Error {
	code?: string;
	constructor(error: DbError) {
		super(error.message ?? 'board load failed');
		this.name = 'BoardLoadError';
		this.code = error.code;
	}
}
