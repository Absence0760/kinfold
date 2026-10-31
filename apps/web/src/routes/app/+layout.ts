import { redirect } from '@sveltejs/kit';
import { loadViewer } from '#lib/auth/session.ts';
import { isConfigured } from '#lib/supabase/client.ts';

// The member area runs in the browser only (session in local storage, data
// behind RLS), served by the adapter's SPA fallback.
export const ssr = false;
export const prerender = false;

export async function load() {
	if (!isConfigured()) redirect(307, '/signin');
	const viewer = await loadViewer();
	if (!viewer) redirect(307, '/signin');
	return { viewer };
}
