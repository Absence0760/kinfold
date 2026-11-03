import { supabase } from '#lib/supabase/client.ts';
import { loadLoan } from '#lib/loans/data.ts';
import { loadCertifiedCounsel } from '#lib/transparency/data.ts';

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
	// The certified counselor is public data, read beside the loan's relief step;
	// its failure is the page's to explain, not the loan's to lose.
	return { uid, detail: loadLoan(supabase(), uid, params.id), counsel: loadCertifiedCounsel(supabase()) };
}
