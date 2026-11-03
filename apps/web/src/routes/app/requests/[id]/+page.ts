import { supabase } from '#lib/supabase/client.ts';
import { loadFormContext, loadRequest } from '#lib/requests/data.ts';
import { loadCertifiedCounsel } from '#lib/transparency/data.ts';
import { classifyLoadError } from '#lib/auth/errors.ts';

const COUNSEL_PROBLEM: Record<string, string> = {
	session: 'The certified counselor could not be read: the local stack is not reachable.',
	network: 'The certified counselor could not be reached: no connection.',
	server: 'The certified counselor could not be read: the server said no.'
};

// Both reads run as the member under RLS: the request is found only if it is
// theirs. Not awaited, so the page can show loading and keep the old view on
// screen while an action re-reads it (invalidate('app:request')).
export async function load({ params, parent, depends }) {
	depends('app:request');
	const { viewer } = await parent();
	return {
		id: params.id,
		detail: loadRequest(supabase(), params.id),
		ctx: loadFormContext(supabase(), viewer.session.user.id),
		// The Fund's certified counselor, public data read beside a mortgage gap's
		// help. A failure is the panel's to explain - the request never depends on
		// it - so the read stays unawaited and carries its own problem line.
		counsel: loadCertifiedCounsel(supabase()).then(
			(counsel) => ({ counsel, counselProblem: null }),
			(e) => ({ counsel: null, counselProblem: COUNSEL_PROBLEM[classifyLoadError(e)] })
		)
	};
}
