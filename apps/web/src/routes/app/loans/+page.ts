import { supabase } from '#lib/supabase/client.ts';
import { localToday } from '#lib/dashboard/format.ts';
import { loadLoans } from '#lib/loans/data.ts';

/**
 * The viewer's loans, as borrower and as lender. Read as the signed-in member,
 * so RLS decides what comes back. The promise is returned unawaited so the
 * page can show a loading state; `depends` lets the error state retry.
 */
export async function load({ parent, depends }) {
	depends('app:loans');
	const { viewer } = await parent();
	return { loans: loadLoans(supabase(), viewer.session.user.id, localToday()) };
}
