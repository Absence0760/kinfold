import { supabase } from '#lib/supabase/client.ts';
import { localToday } from '#lib/dashboard/format.ts';
import { loadHome } from '#lib/dashboard/home.ts';

/**
 * The member's home. Every read runs as the signed-in member, so RLS decides
 * what comes back; nothing here uses a service key. The promise is returned
 * unawaited so the page can show a loading state, and `depends` lets the
 * error state retry with `invalidate('app:home')`.
 */
export async function load({ parent, depends }) {
	depends('app:home');
	const { viewer } = await parent();
	return { home: loadHome(supabase(), viewer.session.user.id, localToday()) };
}
