import { supabase } from '#lib/supabase/client.ts';
import { loadFormContext } from '#lib/requests/data.ts';

// Not awaited, so the page shows a loading state; `depends` lets the error
// state retry with invalidate('app:request-form').
export async function load({ parent, depends }) {
	depends('app:request-form');
	const { viewer } = await parent();
	return { ctx: loadFormContext(supabase(), viewer.session.user.id) };
}
