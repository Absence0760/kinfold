import { redirect } from '@sveltejs/kit';
import { loadViewer } from '#lib/auth/session.ts';
import { isConfigured } from '#lib/supabase/client.ts';
import { signinUrl } from '#lib/auth/next.ts';

// The member area runs in the browser only (session in local storage, data
// behind RLS), served by the adapter's SPA fallback.
export const ssr = false;
export const prerender = false;

export async function load({ url }) {
	if (!isConfigured()) redirect(307, signinUrl(url));
	const viewer = await loadViewer();
	if (!viewer) redirect(307, signinUrl(url));
	return { viewer };
}
