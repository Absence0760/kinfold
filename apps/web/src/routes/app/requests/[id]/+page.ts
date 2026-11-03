import { supabase } from '#lib/supabase/client.ts';
import { loadFormContext, loadRequest } from '#lib/requests/data.ts';

// Both reads run as the member under RLS: the request is found only if it is
// theirs. Not awaited, so the page can show loading and keep the old view on
// screen while an action re-reads it (invalidate('app:request')).
export async function load({ params, parent, depends }) {
	depends('app:request');
	const { viewer } = await parent();
	return {
		id: params.id,
		detail: loadRequest(supabase(), params.id),
		ctx: loadFormContext(supabase(), viewer.session.user.id)
	};
}
