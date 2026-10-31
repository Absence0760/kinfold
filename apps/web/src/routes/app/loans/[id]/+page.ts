import { supabase } from '#lib/supabase/client.ts';
import { loadLoan } from '#lib/loans/data.ts';

/**
 * One loan, from either side. Read as the signed-in member: RLS returns the
 * loan only to its borrower and lender, so anyone else gets "not found". The
 * promise is returned unawaited so the page can keep showing the loan while
 * it reloads after an action (`invalidate('app:loan')`).
 */
export async function load({ parent, params, depends }) {
	depends('app:loan');
	const { viewer } = await parent();
	const uid = viewer.session.user.id;
	return { uid, detail: loadLoan(supabase(), uid, params.id) };
}
