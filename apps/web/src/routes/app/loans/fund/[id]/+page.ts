import { supabase } from '#lib/supabase/client.ts';
import { loadFundLoan } from '#lib/loans/fund.ts';

/**
 * One Fund loan, from the borrower's side. RLS returns the loan only to its
 * borrower, so anyone else gets "not found". The promise is returned unawaited
 * so the page can keep showing the loan while it reloads after an action
 * (`invalidate('app:fund-loan')`).
 */
export async function load({ params, depends }) {
	depends('app:fund-loan');
	return { detail: loadFundLoan(supabase(), params.id) };
}
