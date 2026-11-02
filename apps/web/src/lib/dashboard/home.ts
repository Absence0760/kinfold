import { LoadError } from '#lib/auth/errors.ts';
import type { Db } from '#lib/supabase/client.ts';
import { fromNew } from '#lib/supabase/client.ts';
import { givingSummary, type GivingSummary, type ReliabilityRow } from './giving.ts';
import { sortLoans, summarizeLoan, type LoanSummary } from './loans.ts';
import { buildRequestCards, type RequestCard } from './requests.ts';
import { summarizeMembership, type MembershipSummary } from './membership.ts';

export interface LoanCard extends LoanSummary {
	/** Title of the request the loan paid toward (both parties can read it). */
	requestTitle: string | null;
	/** How the borrower named the lender on their invite ("brother"), shown only to the borrower. */
	lenderRelationship: string | null;
}

export interface HomeData {
	requests: RequestCard[];
	loans: LoanCard[];
	giving: GivingSummary;
	reliability: ReliabilityRow | null;

	membership: MembershipSummary;
}

type Result<T> = { data: T | null; error: { message: string; code?: string } | null; status?: number };

/** The data, or a `LoadError` keeping the code and HTTP status so the page can tell an ended session from a dropped connection. */
function must<T>(r: Result<T>, what: string): T {
	if (r.error) throw new LoadError(what, r.error, r.status);
	return r.data as T;
}

/**
 * The home page's heading. A member with no display name (or no member row
 * yet) is welcomed, not greeted with a bare "Hello".
 */
export function greeting(displayName: string | null | undefined): string {
	const name = displayName?.trim();
	return name ? `Hello, ${name}` : 'Welcome to Kinfold';
}

/**
 * Everything on the member's home, read as the signed-in member: plain selects
 * and self-only RPCs, so RLS decides what comes back. Never pass a
 * service-role client. `today` is the member's local date (`YYYY-MM-DD`).
 */
export async function loadHome(db: Db, uid: string, today: string): Promise<HomeData> {
	const [requestsRes, loansRes, mineRes, givingRes, reliabilityRes, subsRes, paysRes] = await Promise.all([
		db
			.from('requests')
			.select('id, title, kind, status, funding, amount_cents, created_at')
			.eq('member_id', uid)
			.order('created_at', { ascending: false }),
		db
			.from('family_loans')
			.select(
				'id, request_id, borrower_id, lender_id, principal_cents, status, payment_day, pause_months_per_year, default_plan, secured, created_at'
			)
			.or(`borrower_id.eq.${uid},lender_id.eq.${uid}`)
			.order('created_at', { ascending: false }),
		db.from('contributions').select('request_id, source, amount_cents, status').eq('contributor_id', uid),
		db.rpc('my_giving_record'),
			db.rpc('my_reliability'),
		db
			.from('subscriptions')
			.select('id, monthly_cents, formula_version, starts_on, ends_on')
			.eq('member_id', uid),
		db
			.from('subscription_payments')
			.select('period, amount_cents, status')
			.eq('member_id', uid),
		]);
	const requests = must(requestsRes, 'your requests');
	const loans = must(loansRes, 'your loans');
	const mine = must(mineRes, 'your pledges');
	const giving = must(givingRes, 'your giving record');
	const reliability = must(reliabilityRes, 'your reliability record');

	const requestIds = requests.map((r) => r.id);
	const loanIds = loans.map((l) => l.id);
	const loanRequestIds = [...new Set(loans.map((l) => l.request_id).filter((id): id is string => id !== null))];
	const none = Promise.resolve({ data: [], error: null, status: 200 });

	const [scoresRes, contribRes, instRes, pausesRes, forgRes, missedRes, titlesRes, supportersRes, claimsRes, assetsRes, prefsRes] = await Promise.all([
		requestIds.length
			? db.from('scores').select('request_id, score, reasons, model, model_version, created_at').in('request_id', requestIds)
			: none,
		requestIds.length
			? db.from('contributions').select('request_id, source, amount_cents, status').in('request_id', requestIds)
			: none,
		loanIds.length ? db.from('loan_installments').select('*').in('loan_id', loanIds) : none,
		loanIds.length ? db.from('loan_pauses').select('loan_id, months, started_on').in('loan_id', loanIds) : none,
		loanIds.length ? db.from('loan_forgiveness').select('loan_id, amount_cents').in('loan_id', loanIds) : none,
		loanIds.length ? db.from('loan_missed_installments').select('*').in('loan_id', loanIds) : none,
		loanRequestIds.length ? db.from('requests').select('id, title').in('id', loanRequestIds) : none,
		loanRequestIds.length
			? db.from('request_supporters').select('request_id, member_id, relationship').in('request_id', loanRequestIds)
			: none,
		requestIds.length
			// `claims` isn't in the committed generated types yet (`fromNew` seam).
			? fromNew(db, 'claims').select('request_id, gross_cents, member_share_cents, paid_cents, status').in('request_id', requestIds)
			: none,
		db.from('covered_assets').select('kind').eq('member_id', uid),
		db.from('allocation_preferences').select('target, weight_pct').eq('member_id', uid)
	]);

	const loanInputs = {
		installments: must(instRes, 'loan schedules'),
		pauses: must(pausesRes, 'loan pauses'),
		forgiveness: must(forgRes, 'loan forgiveness'),
		missed: must(missedRes, 'missed installments')
	};
	const titles = new Map(must(titlesRes, 'loan requests').map((t) => [t.id, t.title]));
	const supporters = must(supportersRes, 'supporters');
	const membership = summarizeMembership(
		must(subsRes, 'your dues'),
		must(paysRes, 'your dues charges'),
		must(claimsRes, 'your claims'),
		must(assetsRes, 'your covered vehicles'),
		must(prefsRes, 'your plan'),
		today
	);

	const loanCards: LoanCard[] = sortLoans(loans.map((l) => summarizeLoan(l, uid, loanInputs, today))).map((s) => ({
		...s,
		requestTitle: s.loan.request_id ? (titles.get(s.loan.request_id) ?? null) : null,
		lenderRelationship:
			s.role === 'borrower'
				? (supporters.find((x) => x.request_id === s.loan.request_id && x.member_id === s.loan.lender_id)
						?.relationship ?? null)
				: null
	}));

	return {
		membership,
		requests: buildRequestCards(requests, must(scoresRes, 'scores'), must(contribRes, 'contributions')),
		loans: loanCards,
		giving: givingSummary(giving[0] ?? null, mine),
		reliability: reliability[0] ?? null
	};
}
