import { error, redirect } from '@sveltejs/kit';
import { loadProblem } from '#lib/auth/errors.ts';
import { clearLocalSession, loadViewer, type Viewer } from '#lib/auth/session.ts';
import { isConfigured } from '#lib/supabase/client.ts';
import { signinUrl } from '#lib/auth/next.ts';

// The member area runs in the browser only (session in local storage, data
// behind RLS), served by the adapter's SPA fallback.
export const ssr = false;
export const prerender = false;

export async function load({ url }) {
	if (!isConfigured()) redirect(307, signinUrl(url));
	let viewer: Viewer | null;
	try {
		viewer = await loadViewer();
	} catch (e) {
		// A failed read is never "no profile": an ended session goes back to
		// sign-in (dropping the rejected session first, or /signin would bounce
		// straight back here); anything else shows routes/+error.svelte with a retry.
		const problem = loadProblem(e, 'your account');
		if (problem.kind === 'session') {
			await clearLocalSession();
			redirect(307, signinUrl(url));
		}
		error(problem.kind === 'network' ? 503 : 500, problem.body);
	}
	if (!viewer) redirect(307, signinUrl(url));
	return { viewer };
}
