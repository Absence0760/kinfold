import { statusLabel, type RequestStatus } from './labels.ts';

/** The parts of a PostgrestError (or any thrown error) this needs. */
export interface DbError {
	code?: string;
	message?: string;
}

/**
 * A database refusal in plain words. The review functions raise readable
 * messages for each rule (same region, own request, already decided); this
 * turns each into what happened and what to do next. Anything unrecognised is
 * passed through, so a new rule is still visible rather than hidden behind a
 * generic "something went wrong".
 */
export function explainDbError(error: DbError | null | undefined): string {
	const message = error?.message ?? '';
	const code = error?.code ?? '';

	if (/outside the member'?s region/i.test(message))
		return 'This request is from your own state, and requests are reviewed by someone outside it. Leave it for a reviewer from another state.';
	if (/cannot review your own request/i.test(message))
		return 'This is your own request. Another reviewer decides it.';
	if (/^reviewers only$/i.test(message))
		return 'Your account doesn’t have an active reviewer role, so the decision wasn’t saved.';

	const status = /not reviewable in status (\w+)/i.exec(message)?.[1];
	if (status === 'refused')
		return 'This request has already been refused. Only an upheld appeal can reopen it.';
	if (status)
		return `This request is now “${statusLabel(status as RequestStatus)}”, so it can’t be reviewed. Refresh the queue.`;

	if (/reviews_reason_check|appeals_reason_check/i.test(message))
		return 'The reason must be 10 to 2,000 characters.';

	if (/^appeal panel only$/i.test(message))
		return 'Your account doesn’t have an active appeal panel role, so the decision wasn’t saved.';
	if (/cannot decide your own appeal/i.test(message))
		return 'This is your own appeal. Another panel member decides it.';
	if (/you reviewed this request/i.test(message))
		return 'You reviewed this request, so another panel member decides the appeal.';
	if (/appeal not found or already decided/i.test(message))
		return 'This appeal has already been decided. Refresh the list.';

	if (code === 'PGRST301' || /jwt expired/i.test(message))
		return 'Your session has ended. Sign in again, then retry.';
	if (/failed to fetch|networkerror|fetch failed|load failed/i.test(message))
		return 'Can’t reach the server. Check your connection and try again.';

	return message
		? `The server refused this: “${message}”`
		: 'Something went wrong and nothing was saved. Try again.';
}
