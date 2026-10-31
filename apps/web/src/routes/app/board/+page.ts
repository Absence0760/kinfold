import { loadBoard } from '#lib/board/data.ts';

// The board promise isn't awaited: the page shows a loading state while it
// reads, and can retry on error without a full navigation.
export async function load({ parent }) {
	const { viewer } = await parent();
	const viewerId = viewer.session.user.id;
	const active = viewer.member?.status === 'active';
	return {
		active,
		viewerId,
		board: active ? loadBoard(viewerId) : Promise.resolve([])
	};
}
