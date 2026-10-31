import { isInviteToken } from '#lib/invites/invites.ts';

// The token stays in the browser: nothing is read or accepted until the
// invitee presses "Accept", so opening the link alone never uses it up.
export async function load({ params, parent }) {
	const { viewer } = await parent();
	return {
		token: params.token,
		wellFormed: isInviteToken(params.token),
		viewerId: viewer.session.user.id,
		verified: viewer.member?.status === 'active',
		hasMember: viewer.member != null
	};
}
