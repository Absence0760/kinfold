import { redirect } from '@sveltejs/kit';
import { reviewAccess } from '#lib/review/labels.ts';
import type { PageLoad } from './$types';

// The console is for reviewers and the appeal panel. The database enforces the
// same thing on every read and decision; this only keeps everyone else from a
// page of empty lists.
export const load: PageLoad = async ({ parent }) => {
	const { viewer } = await parent();
	const access = reviewAccess(viewer.roles);
	if (!access.reviewer && !access.panel) redirect(307, '/app');
	return { access };
};
