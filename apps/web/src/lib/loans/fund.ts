// Loans the lending Fund has taken out with you (roadmap 3a). Same no-interest
// promise as family loans, but the lender is the Fund itself: no invitation pair
// and no agreement page — the Fund signs at once, and only the partner's
// disbursement starts collection. Money still moves with the partner, never
// through Kinfold.

import { fromNew, rpcNew } from '#lib/supabase/client.ts';
import type { Db } from '#lib/supabase/client.ts';
import type { Tone } from '#lib/dashboard/labels.ts';
import { addMonths } from '#lib/dashboard/format.ts';

interface FundLoanRow {
	id: string;
	principal_cents: number;
	// loan_status: the Fund's loans share the family-loan ladder.
	status: string;
	// monthly or income; income schedules size each payment from live income.
	schedule: string;
	income_share_bps: number;
	lien_bps: number;
	fund_signed_at: string | null;
	borrower_signed_at: string | null;
	created_at: string;
}

interface FundInstallmentRow {
	loan_id: string;
	due_on: string;
	amount_cents: number;
	paid_cents: number;
}

interface FundPauseRow {
	loan_id: string;
	months: number;
	started_on: string;
}

interface FundRestructureRow {
	loan_id: string;
	months: number;
	first_due: string;
	applied_at: string | null;
}

/** Fund loans read in the borrower's own frame: the Fund signed at once. */
export function fundLoanStatusText(status: string): { label: string; tone: Tone } {
	if (status === 'proposed') return { label: 'Waiting for you to sign', tone: 'action' };
	if (status === 'signed') return { label: 'Signed', tone: 'progress' };
	if (status === 'active') return { label: 'Being repaid', tone: 'progress' };
	if (status === 'paused') return { label: 'Paused', tone: 'progress' };
	if (status === 'repaid') return { label: 'Repaid in full', tone: 'done' };
	if (status === 'forgiven') return { label: 'Forgiven', tone: 'done' };
	if (status === 'defaulted') return { label: 'Closed under the agreed plan', tone: 'closed' };
	return { label: 'Cancelled', tone: 'closed' };
}

export interface FundLoanSummary {
	loan: FundLoanRow;
	/** Outstanding as the schema computes it, never a client-side guess. */
	outstandingCents: number;
	/** This month's cap on an income schedule; 0 for monthly ones. */
	shareCents: number;
	/** Earliest unpaid installment (monthly schedules only). */
	readonly next: { dueOn: string; owedCents: number } | null;
	/** While paused: the day the latest pause runs out (date maths only). */
	pausedUntil: string | null;
	/** A restructure the borrower staged, waiting for the partner's event. */
	restructureWaiting: boolean;
}

function cents(r: { data?: unknown; error: { message: string } | null }, what: string): number {
	if (r.error) throw new Error(`Couldn't load ${what}: ${r.error.message}`);
	return (r.data as number | null) ?? 0;
}

/** The day the latest pause on this loan runs out, or null with no pauses. */
function pauseEnd(rows: FundPauseRow[], loanId: string): string | null {
	let ends: string | null = null;
	for (const p of rows) {
		if (p.loan_id !== loanId) continue;
		const end = addMonths(p.started_on, p.months);
		if (ends === null || end > ends) ends = end;
	}
	return ends;
}

/**
 * The viewer's Fund loans, read as the signed-in member: RLS returns a loan
 * only to its borrower. Outstanding and income caps come from the schema's own
 * functions so the page never re-derives money.
 */
export async function loadFundLoans(db: Db, uid: string): Promise<FundLoanSummary[]> {
	const rows = await fromNew(db, 'fund_loans')
		.select('id, principal_cents, status, schedule, income_share_bps, lien_bps, fund_signed_at, borrower_signed_at, created_at')
		.eq('borrower_id', uid)
		.order('created_at', { ascending: false });
	if (rows.error) throw new Error(`Couldn't load the Fund loans: ${rows.error.message}`);
	const loans = (rows.data ?? []) as FundLoanRow[];
	if (loans.length === 0) return [];
	const ids = loans.map((l) => l.id);

	const [inst, pauses, restructures, outstanding, share] = await Promise.all([
		fromNew(db, 'fund_loan_installments').select('loan_id, due_on, amount_cents, paid_cents').in('loan_id', ids).order('due_on'),
		fromNew(db, 'fund_loan_pauses').select('loan_id, months, started_on').in('loan_id', ids),
		fromNew(db, 'fund_loan_restructures')
			.select('loan_id, months, first_due, applied_at')
			.in('loan_id', ids),
		Promise.all(ids.map((id) => rpcNew(db, 'fund_loan_outstanding_cents', { p_loan: id }))),
		Promise.all(ids.map((id) => rpcNew(db, 'fund_loan_income_due_cents', { p_loan: id })))
	]);
	if (inst.error) throw new Error(`Couldn't load the Fund loan schedules: ${inst.error.message}`);
	for (const r of [pauses, restructures])
		if (r.error) throw new Error(`Couldn't load the Fund loan history: ${r.error.message}`);
	const pauseRows = (pauses.data ?? []) as FundPauseRow[];
	const restructureRows = (restructures.data ?? []) as FundRestructureRow[];
	const unpaid = ((inst.data ?? []) as FundInstallmentRow[]).filter((i) => i.paid_cents < i.amount_cents);

	return loans.map((loan, i) => {
		const mine = unpaid.filter((p) => p.loan_id === loan.id);
		const n = mine.length ? mine.reduce((a, b) => (b.due_on < a.due_on ? b : a)) : null;
		return {
			loan,
			outstandingCents: cents(outstanding[i], 'the Fund loan balance'),
			shareCents: loan.schedule === 'income' ? cents(share[i], "this month's share") : 0,
			next: n ? { dueOn: n.due_on, owedCents: n.amount_cents - n.paid_cents } : null,
			pausedUntil: pauseEnd(pauseRows, loan.id),
			restructureWaiting: restructureRows.some((r) => r.loan_id === loan.id && r.applied_at === null)
		};
	});
}
