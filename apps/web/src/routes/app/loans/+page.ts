import { supabase } from '#lib/supabase/client.ts';
import { localToday } from '#lib/dashboard/format.ts';
import { loadLoans } from '#lib/loans/data.ts';
import { loadFundLoans } from '#lib/loans/fund.ts';
import type { LoanListItem } from '#lib/loans/data.ts';
import type { FundLoanSummary } from '#lib/loans/fund.ts';

/**
 * The viewer's loans, as borrower and as lender. Read as the signed-in member,
 * so RLS decides what comes back. The promise is returned unawaited so the
 * page can show a loading state; `depends` lets the error state retry. Fund
 * loans (roadmap 3a) ride along in the same slot, index 1 of the pair.
 */
export async function load({ parent, depends }) {
	depends('app:loans');
	const { viewer } = await parent();
	const uid = viewer.session.user.id;
	return { loans: loadBoth(uid) };
}

/**
 * Both loan lists in one tuple: a reload and a retry then cover the whole
 * page. Both requests start together; the awaits only order the results.
 */
async function loadBoth(uid: string): Promise<[LoanListItem[], FundLoanSummary[]]> {
	const family = loadLoans(supabase(), uid, localToday());
	const fund = loadFundLoans(supabase(), uid);
	return [await family, await fund];
}
