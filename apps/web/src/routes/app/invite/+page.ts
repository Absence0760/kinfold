export async function load({ parent }) {
	const { viewer } = await parent();
	return {
		viewerId: viewer.session.user.id,
		verified: viewer.member?.status === 'active'
	};
}
