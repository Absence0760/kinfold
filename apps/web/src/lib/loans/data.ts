import { fromNew, rpcNew } from '#lib/supabase/client.ts';
import type { Db } from '#lib/supabase/client.ts';
import type { DefaultPlan } from '#lib/dashboard/labels.ts';
import { sortLoans, summarizeLoan, type LoanSummary, type MissedRow } from '#lib/dashboard/loans.ts';
import type { ForgivenessDetailRow, InstallmentRow, LoanDetailRow, PauseDetailRow } from './loan.ts';

type Result<T> = { data: T | null; error: { message: string; code?: string } | null };

function must<T>(r: Result<T>, what: string): T {
	if (r.error) throw new Error(`Couldn't load ${what}: ${r.error.message}`);
	return r.data as T;
}

const none = Promise.resolve({ data: [], error: null });

export interface LoanListItem extends LoanSummary {
	requestTitle: string | null;
	/** How the borrower named the lender on their invite ("brother"), shown only to the borrower. */
	lenderRelationship: string | null;
}

/**
 * The viewer's loans, both sides, read as the signed-in member (RLS lets only
 * the borrower and the lender see a loan). Never pass a service-role client.
 */
export async function loadLoans(db: Db, uid: string, today: string): Promise<LoanListItem[]> {
	const loans = must(
		await db
			.from('family_loans')
			.select(
				'id, request_id, borrower_id, lender_id, principal_cents, status, payment_day, pause_months_per_year, default_plan, secured, created_at'
			)
			.or(`borrower_id.eq.${uid},lender_id.eq.${uid}`)
			.order('created_at', { ascending: false }),
		'your loans'
	);
	if (loans.length === 0) return [];
	const ids = loans.map((l) => l.id);
	const requestIds = [...new Set(loans.map((l) => l.request_id).filter((id): id is string => id !== null))];

	const [inst, pauses, forg, missed, titles, supporters] = await Promise.all([
		db.from('loan_installments').select('*').in('loan_id', ids),
		db.from('loan_pauses').select('loan_id, months, started_on').in('loan_id', ids),
		db.from('loan_forgiveness').select('loan_id, amount_cents').in('loan_id', ids),
		db.from('loan_missed_installments').select('*').in('loan_id', ids),
		requestIds.length ? db.from('requests').select('id, title').in('id', requestIds) : none,
		requestIds.length
			? db.from('request_supporters').select('request_id, member_id, relationship').in('request_id', requestIds)
			: none
	]);
	const inputs = {
		installments: must(inst, 'loan schedules'),
		pauses: must(pauses, 'loan pauses'),
		forgiveness: must(forg, 'loan forgiveness'),
		missed: must(missed, 'missed installments')
	};
	const titleOf = new Map(must(titles, 'loan requests').map((t) => [t.id, t.title]));
	const people = must(supporters, 'supporters');

	return sortLoans(loans.map((l) => summarizeLoan(l, uid, inputs, today))).map((s) => ({
		...s,
		requestTitle: s.loan.request_id ? (titleOf.get(s.loan.request_id) ?? null) : null,
		lenderRelationship:
			s.role === 'borrower'
				? (people.find((p) => p.request_id === s.loan.request_id && p.member_id === s.loan.lender_id)?.relationship ??
					null)
				: null
	}));
}

export interface LoanDetail {
	loan: LoanDetailRow;
	installments: InstallmentRow[];
	pauses: PauseDetailRow[];
	/** Restructures on this loan, oldest first (the pending one is last open). */
	readonly restructures: RestructureRow[];
	/** The agreement the loan servicing wrote down, null until it has. */
	agreementText: string | null;
	agreementFinalizedAt: string | null;
	forgiveness: ForgivenessDetailRow[];
	/** What the `loan_missed_installments` view lists for this loan. */
	missed: MissedRow[];
	requestTitle: string | null;
	lenderRelationship: string | null;
}

/** One loan with everything about it, or null when the viewer can't see it. */
export async function loadLoan(db: Db, uid: string, id: string): Promise<LoanDetail | null> {
	// A malformed id is "not found", not a server error.
	if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
	const loanRes = await db.from('family_loans').select('*').eq('id', id).maybeSingle();
	if (loanRes.error) throw new Error(`Couldn't load the loan: ${loanRes.error.message}`);
	const loan: LoanDetailRow | null = loanRes.data;
	if (!loan) return null;

	const [inst, pauses, forg, missed, restructures, agreement, title, supporter] = await Promise.all([
		db.from('loan_installments').select('*').eq('loan_id', id).order('seq'),
		db.from('loan_pauses').select('*').eq('loan_id', id).order('started_on'),
		db.from('loan_forgiveness').select('*').eq('loan_id', id).order('created_at'),
		db.from('loan_missed_installments').select('*').eq('loan_id', id),
		// The table has no created_at: a restructure is dated by its staging.
		db
			.from('loan_restructures')
			.select('loan_id, months, first_due, stager_signed_at, other_signed_at, created_by')
			.eq('loan_id', id)
			.order('stager_signed_at'),
		fromNew(db, 'family_loans')
			.select('agreement_text, agreement_finalized_at')
			.eq('id', id)
			.maybeSingle(),
		loan.request_id ? db.from('requests').select('title').eq('id', loan.request_id).maybeSingle() : Promise.resolve({ data: null, error: null }),
		loan.request_id && loan.borrower_id === uid
			? db
					.from('request_supporters')
					.select('relationship')
					.eq('request_id', loan.request_id)
					.eq('member_id', loan.lender_id)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null })
	]);

	const agreementRow = must(agreement, 'the written agreement');
	const titleRow = must(title, 'the request');
	const supporterRow = must(supporter, 'the lender');
	return {
		loan,
		installments: must(inst, 'the schedule'),
		pauses: must(pauses, 'pauses'),
		forgiveness: must(forg, 'forgiveness'),
		missed: must(missed, 'missed installments'),
		restructures: must(restructures, 'restructures'),
		agreementText: agreementRow?.agreement_text ?? null,
		agreementFinalizedAt: agreementRow?.agreement_finalized_at ?? null,
		requestTitle: titleRow?.title ?? null,
		lenderRelationship: supporterRow?.relationship ?? null
	};
}

// --- writes: every one is an RPC that checks who you are and the loan's state ---

async function call<T>(p: PromiseLike<{ data: T | null; error: { message: string; code?: string } | null }>): Promise<T | null> {
	const { data, error } = await p;
	if (error) throw error;
	return data;
}

export const setLoanTerms = (db: Db, loan: string, paymentDay: number, pauseMonths: number, plan: DefaultPlan) =>
	call(
		db.rpc('set_loan_terms', {
			p_loan: loan,
			p_payment_day: paymentDay,
			p_pause_months_per_year: pauseMonths,
			p_default_plan: plan
		})
	);

export const setLoanSchedule = (db: Db, loan: string, months: number, firstDue: string) =>
	call(db.rpc('set_loan_schedule', { p_loan: loan, p_months: months, p_first_due: firstDue }));

export const signLoan = (db: Db, loan: string) => call(db.rpc('sign_loan', { p_loan: loan }));

export const pauseLoan = (db: Db, loan: string, months: number, reason: string | null) =>
	call(db.rpc('pause_loan', reason ? { p_loan: loan, p_months: months, p_reason: reason } : { p_loan: loan, p_months: months }));

export const resumeLoan = (db: Db, loan: string) => call(db.rpc('resume_loan', { p_loan: loan }));

export const forgiveLoan = (db: Db, loan: string, cents: number, taxYear: number) =>
	call(db.rpc('forgive_loan', { p_loan: loan, p_amount_cents: cents, p_tax_year: taxYear }));

/** A restructure the borrower staged, waiting for the lender to sign it. */
export interface RestructureRow {
	loan_id: string;
	months: number;
	first_due: string;
	stager_signed_at: string;
	other_signed_at: string | null;
	created_by: string;
}

/** Restructures on the viewer's loans waiting for the other side to sign. */
export async function loadPendingRestructures(db: Db, loanIds: string[]): Promise<RestructureRow[]> {
	if (loanIds.length === 0) return [];
	const { data, error } = await db
		.from('loan_restructures')
		.select('loan_id, months, first_due, stager_signed_at, other_signed_at, created_by')
		.in('loan_id', loanIds);
	if (error) throw new Error(`Couldn't load pending restructures: ${error.message}`);
	return (data ?? []) as RestructureRow[];
}

/** Stage a new schedule; the other side has to sign it before money re-spreads. */
export async function restructureLoan(db: Db, loan: string, months: number, firstDue: string) {
	const { error } = await rpcNew(db, 'restructure_loan', { p_loan: loan, p_months: months, p_first_due: firstDue });
	if (error) throw error;
}

/** The other side signs a staged restructure: both sides have agreed. */
export async function signLoanRestructure(db: Db, loan: string) {
	const { error } = await rpcNew(db, 'sign_loan_restructure', { p_loan: loan });
	if (error) throw error;
}
