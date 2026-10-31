import type { Database } from '../../../../backend/supabase/database.types.ts';
import { addMonths } from './format.ts';

type Public = Database['public'];
export type LoanRow = Pick<
	Public['Tables']['family_loans']['Row'],
	| 'id'
	| 'request_id'
	| 'borrower_id'
	| 'lender_id'
	| 'principal_cents'
	| 'status'
	| 'payment_day'
	| 'pause_months_per_year'
	| 'default_plan'
	| 'secured'
	| 'created_at'
>;
export type InstallmentRow = Public['Tables']['loan_installments']['Row'];
export type PauseRow = Pick<Public['Tables']['loan_pauses']['Row'], 'loan_id' | 'months' | 'started_on'>;
export type ForgivenessRow = Pick<Public['Tables']['loan_forgiveness']['Row'], 'loan_id' | 'amount_cents'>;
export type MissedRow = Public['Views']['loan_missed_installments']['Row'];

export interface NextInstallment {
	seq: number;
	dueOn: string;
	/** What's still owed on this installment (it may be part-paid). */
	owedCents: number;
	paused: boolean;
}

export interface LoanSummary {
	loan: LoanRow;
	role: 'borrower' | 'lender';
	paidCents: number;
	forgivenCents: number;
	/** Principal less payments and forgiveness; never negative. */
	remainingCents: number;
	installmentCount: number;
	installmentsPaid: number;
	/** The earliest unpaid installment, or null when nothing is left to pay. */
	next: NextInstallment | null;
	/** Owed on installments more than 10 days late (the `loan_missed_installments` view). */
	behindCents: number;
	/** Pause months still available in the rolling 12 months `pause_loan` checks. */
	pauseMonthsLeft: number;
	/** While paused: the day the latest pause runs out. */
	pausedUntil: string | null;
	/** Whether repayments are being collected (`active` or `paused`). */
	collecting: boolean;
}

export interface LoanInputs {
	installments: readonly InstallmentRow[];
	pauses: readonly PauseRow[];
	forgiveness: readonly ForgivenessRow[];
	missed: readonly MissedRow[];
}

/**
 * One loan as the borrower or the lender sees it. Both see the same figures,
 * worded the same: a missed installment shows as an amount behind, never as
 * a count of misses (design.md, "Dashboards").
 */
export function summarizeLoan(loan: LoanRow, viewerId: string, inputs: LoanInputs, today: string): LoanSummary {
	const own = <T extends { loan_id: string | null }>(rows: readonly T[]) => rows.filter((r) => r.loan_id === loan.id);
	const installments = own(inputs.installments).sort((a, b) => a.due_on.localeCompare(b.due_on) || a.seq - b.seq);
	const pauses = own(inputs.pauses);

	const paidCents = sum(installments.map((i) => i.paid_cents));
	const forgivenCents = sum(own(inputs.forgiveness).map((f) => f.amount_cents));
	const remainingCents = Math.max(0, loan.principal_cents - paidCents - forgivenCents);
	const collecting = loan.status === 'active' || loan.status === 'paused';

	const unpaid = installments.find((i) => i.paid_cents < i.amount_cents);
	const open = remainingCents > 0 && !['repaid', 'forgiven', 'defaulted', 'cancelled'].includes(loan.status);
	const next: NextInstallment | null =
		open && unpaid
			? { seq: unpaid.seq, dueOn: unpaid.due_on, owedCents: unpaid.amount_cents - unpaid.paid_cents, paused: unpaid.paused }
			: null;

	const yearAgo = addMonths(today, -12);
	const usedMonths = sum(pauses.filter((p) => p.started_on > yearAgo).map((p) => p.months));
	const latestPause = [...pauses].sort((a, b) => b.started_on.localeCompare(a.started_on))[0];

	return {
		loan,
		role: loan.borrower_id === viewerId ? 'borrower' : 'lender',
		paidCents,
		forgivenCents,
		remainingCents,
		installmentCount: installments.length,
		installmentsPaid: installments.filter((i) => i.paid_cents >= i.amount_cents).length,
		next,
		behindCents: collecting ? sum(own(inputs.missed).map((m) => m.owed_cents ?? 0)) : 0,
		pauseMonthsLeft: Math.max(0, loan.pause_months_per_year - usedMonths),
		pausedUntil: loan.status === 'paused' && latestPause ? addMonths(latestPause.started_on, latestPause.months) : null,
		collecting
	};
}

/** Loans needing attention first (behind, then collecting, then the rest). */
export function sortLoans(loans: LoanSummary[]): LoanSummary[] {
	const rank = (l: LoanSummary) => (l.behindCents > 0 ? 0 : l.collecting || l.next ? 1 : 2);
	return [...loans].sort((a, b) => rank(a) - rank(b) || (a.next?.dueOn ?? '9').localeCompare(b.next?.dueOn ?? '9'));
}

function sum(xs: readonly number[]): number {
	return xs.reduce((a, b) => a + b, 0);
}
