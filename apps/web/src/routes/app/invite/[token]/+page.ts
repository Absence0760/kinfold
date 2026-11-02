import { isInviteToken } from '#lib/invites/invites.ts';
import { previewInvite } from '#lib/invites/data.ts';

// The token stays in the browser: nothing is read or accepted until the
// invitee presses "Accept", so opening the link alone never uses it up.
// The preview is the one read that happens on load: it shows what the
// invitee would be joining, and reads exactly as `accept_invite` does, so
// a used-up or cancelled link says so before anyone clicks.
export async function load({ params, parent }) {
	const { viewer } = await parent();
	const wellFormed = isInviteToken(params.token);
	let preview = null;
	let previewFailed = false;
	if (wellFormed) {
		try {
			preview = await previewInvite(params.token);
		} catch {
			// A network or server hiccup isn't a dead link: accepting will say.
			previewFailed = true;
		}
	}
	return {
		preview,
		previewFailed,
		token: params.token,
		wellFormed,
		viewerId: viewer.session.user.id,
		verified: viewer.member?.status === 'active',
		hasMember: viewer.member != null
	};
}
