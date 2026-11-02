import { formatCents } from '#lib/dashboard/format.ts';

/** The parts of a PostgrestError (or any thrown error) this needs. */
export interface DbError {
	code?: string;
	message?: string;
}

/**
 * A refusal from `create_invite`, `accept_invite` or `pledge` in plain words:
 * what happened and what to do next. Anything unrecognised is passed through,
 * so a new rule is still visible rather than hidden behind "something went
 * wrong".
 */
export function explainInviteError(error: DbError | null | undefined): string {
	const message = error?.message ?? '';
	const code = error?.code ?? '';

	// accept_invite
	if (/invite not found, used or expired/i.test(message))
		return 'This invite link has already been used or has expired (links last 30 days and work once). If you accepted it before, the request is under Invites. Otherwise, ask the person who sent it for a new link.';
	if (/accept an invite to your own request/i.test(message))
		return 'This is an invite to your own request. Send the link to the person you want to invite instead.';
	if (code === '23503' && /request_supporters/i.test(message))
		return 'Your member profile isn’t set up yet, so you can’t accept invites. Membership is by invitation for now: ask the member who invited you to contact the Kinfold team, who will finish setting up your profile. Then sign in again and open this link.';

	// accept_invite, in its new readable form rather than a foreign-key crash.
	if (/finish setting up your account/i.test(message))
		return 'Your member profile isn’t set up yet, so you can’t accept invites. Membership is by invitation for now: ask the member who sent you this link to contact the Kinfold team, who will finish setting up your profile. Then sign in again and open the link.';

	// invite_preview, and the preview of a link that was cancelled or used up.
	if (/^invite not found$/i.test(message))
		// Same answer as a used or expired link: cancelling stays invisible to others.
		return 'This invite link can’t be found, was already used, has expired, or was cancelled by the member who sent it. Ask them for a new link.';

	// revoke_invite
	if (/the link was already used or cancelled/i.test(message))
		return 'That link was already used or cancelled. Nothing more to do; make a new link if you still want to invite someone.';

	// create_invite
	
		return 'Say who this person is to you in 1 to 40 characters.';

	// pledge
	if (/cannot pledge to your own request/i.test(message))
		return 'This is your own request, so you can’t pledge to it. Invite family and friends instead.';
	if (/not taking pledges/i.test(message))
		return 'This request isn’t taking pledges right now: it may be fully pledged, still being checked, or closed. Refresh to see where it stands.';
	if (/ask the member for an invite/i.test(message))
		return 'You need to accept an invite to this request before you can give to it.';
	if (/only invited, verified family and friends can lend/i.test(message))
		return 'Only verified members can lend. Finish verifying your identity first, or give instead: a gift needs no verification.';
	if (/pledges open once the request'?s payee is verified/i.test(message))
		return 'Pledges open once the shop or lender being paid has been verified. Try again in a day or two.';
	const left = /pledge must be between 1 and (-?\d+) cents/i.exec(message)?.[1];
	if (left != null) {
		const n = Number(left);
		return n > 0
			? `Someone pledged while you were deciding: this request now needs ${formatCents(n)}. Pledge up to that.`
			: 'Someone pledged while you were deciding, and the request is now fully pledged. Nothing was taken from you.';
	}
	if (/pool money is allocated by the pool run/i.test(message))
		return 'Money from the pool isn’t pledged here: the pool shares out what it holds across the requests waiting, at each of its runs.';

	// shared by create_invite and pledge
	if (/^request not found$/i.test(message))
		return 'This request can’t be found, or it has closed. Refresh the page.';

	if (code === 'PGRST301' || /jwt expired/i.test(message))
		return 'Your session has ended. Sign in again, then retry.';
	if (/failed to fetch|networkerror|fetch failed|load failed/i.test(message))
		return 'Can’t reach the server. Check your connection and try again.';

	return message
		? `The server refused this: “${message}”`
		: 'Something went wrong and nothing was saved. Try again.';
}
