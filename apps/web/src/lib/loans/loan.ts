import type { Database } from '../../../../backend/supabase/database.types.ts';
import { addMonths } from '#lib/dashboard/format.ts';
import type { LoanStatus } from '#lib/dashboard/labels.ts';

type Public = Database['public'];
/** Every column of a loan the borrower and lender can read. */
export type LoanDetailRow = Public['Tables']['family_loans']['Row'];
export type InstallmentRow = Public['Tables']['loan_installments']['Row'];
export type PauseDetailRow = Public['Tables']['loan_pauses']['Row'];
export type ForgivenessDetailRow = Public['Tables']['loan_forgiveness']['Row'];

export type Side = 'borrower' | 'lender';

export const sideOf = (loan: Pick<LoanDetailRow, 'borrower_id'>, viewerId: string): Side =>
	loan.borrower_id === viewerId ? 'borrower' : 'lender';

// --- installments -------------------------------------------------------------

export type InstallmentState = 'paid' | 'part_paid' | 'missed' | 'due' | 'upcoming' | 'not_collected';

export interface InstallmentText {
	label: string;
	tone: 'done' | 'action' | 'progress' | 'closed';
}

/**
 * One installment's state, as both sides see it. "Missed" means more than 10
 * days late on a loan that is collecting, the same rule as the
 * `loan_missed_installments` view (pass whether the view listed it). Missed
 * is never charged for; it starts a conversation.
 */
export function installmentState(
	row: Pick<InstallmentRow, 'amount_cents' | 'paid_cents' | 'due_on'>,
	loanStatus: LoanStatus,
	missed: boolean,
	today: string
): InstallmentState {
	if (row.paid_cents >= row.amount_cents) return 'paid';
	if (!['active', 'paused', 'signed', 'proposed'].includes(loanStatus)) return 'not_collected';
	if (missed) return 'missed';
	if (row.paid_cents > 0) return 'part_paid';
	return row.due_on <= today ? 'due' : 'upcoming';
}

export function installmentText(state: InstallmentState): InstallmentText {
	switch (state) {
		case 'paid':
			return { label: 'Paid', tone: 'done' };
		case 'part_paid':
			return { label: 'Part paid', tone: 'progress' };
		case 'missed':
			return { label: 'Missed', tone: 'action' };
		case 'due':
			return { label: 'Due', tone: 'action' };
		case 'upcoming':
			return { label: 'Upcoming', tone: 'progress' };
		case 'not_collected':
			return { label: 'Not collected', tone: 'closed' };
	}
}

// --- pauses -------------------------------------------------------------------

/** Pause months used in the rolling 12 months `pause_loan` counts. */
export function pauseMonthsUsed(pauses: readonly Pick<PauseDetailRow, 'months' | 'started_on'>[], today: string): number {
	const yearAgo = addMonths(today, -12);
	return pauses.filter((p) => p.started_on > yearAgo).reduce((a, p) => a + p.months, 0);
}

/** The most months the borrower can pause right now (each pause is 1 to 12 months). */
export function pauseMonthsLeft(allowance: number, used: number): number {
	return Math.max(0, Math.min(12, allowance - used));
}

/** Why a pause of `months` would be refused, or null when it wouldn't. */
export function pauseProblem(months: number, left: number): string | null {
	if (left === 0) return 'This loan’s pause months for the year are used up. Talk to your lender about a new schedule.';
	if (!Number.isInteger(months) || months < 1) return 'Choose at least one month.';
	if (months > left) return `You can pause up to ${left} month${left === 1 ? '' : 's'} right now.`;
	return null;
}

export interface PushedBack {
	seq: number;
	from: string;
	to: string;
	amountCents: number;
}

/**
 * What `pause_loan` does to the schedule: every installment not yet fully paid
 * moves back by `months`; paid ones stay put. Amounts never change, so the
 * total owed stays the same.
 */
export function pushBack(
	installments: readonly Pick<InstallmentRow, 'seq' | 'due_on' | 'amount_cents' | 'paid_cents'>[],
	months: number
): PushedBack[] {
	return installments
		.filter((i) => i.paid_cents < i.amount_cents)
		.map((i) => ({ seq: i.seq, from: i.due_on, to: addMonths(i.due_on, months), amountCents: i.amount_cents - i.paid_cents }));
}

// --- forgiveness --------------------------------------------------------------

/**
 * The 2026 annual gift-tax exclusion per recipient (design.md, "Gift instead
 * of lend"). Above it in a year, the lender files a gift-tax return (Form 709);
 * tax is rarely due.
 */
export const GIFT_EXCLUSION_YEAR = 2026;
export const GIFT_EXCLUSION_CENTS = 1_900_000;

/** Why forgiving `cents` would be refused, or null. */
export function forgiveProblem(cents: number | null, outstandingCents: number): string | null {
	if (outstandingCents <= 0) return 'Nothing is left to forgive.';
	if (cents == null || cents <= 0) return 'Enter an amount in dollars, like 100 or 49.50.';
	if (cents > outstandingCents) return 'That’s more than is left to repay. Forgive the rest instead.';
	return null;
}

/** Forgiveness recorded against one tax year, in cents. */
export function forgivenInYear(rows: readonly Pick<ForgivenessDetailRow, 'tax_year' | 'amount_cents'>[], year: number): number {
	return rows.filter((r) => r.tax_year === year).reduce((a, r) => a + r.amount_cents, 0);
}

// --- signing ------------------------------------------------------------------

export interface Signatures {
	you: string | null;
	them: string | null;
}

export function signatures(loan: Pick<LoanDetailRow, 'borrower_signed_at' | 'lender_signed_at'>, side: Side): Signatures {
	return side === 'borrower'
		? { you: loan.borrower_signed_at, them: loan.lender_signed_at }
		: { you: loan.lender_signed_at, them: loan.borrower_signed_at };
}

// --- the IRS minimum rate -------------------------------------------------------

/** Basis points as a percentage, e.g. 412 → "4.12%". */
export const formatBps = (bps: number): string => `${(bps / 100).toFixed(2)}%`;

// --- what each side can do ------------------------------------------------------

export type LoanAction = 'set_terms' | 'set_schedule' | 'sign' | 'pause' | 'resume' | 'forgive';

/**
 * The actions open to this side of the loan right now. Mirrors who each
 * function lets in and when:
 *  - `set_loan_terms`, `set_loan_schedule`, `sign_loan`: either side, only
 *    while `proposed` (a change clears both signatures);
 *  - `pause_loan`: the borrower, while `active` or `paused`, within the allowance;
 *  - `resume_loan`: the borrower, while `paused`;
 *  - `forgive_loan`: the lender, while `active` or `paused`, with something left.
 * `apply_default_plan` is service-only, so it is never a member action.
 */
export function loanActions(input: {
	status: LoanStatus;
	side: Side;
	youSigned: boolean;
	scheduleMatchesPrincipal: boolean;
	pauseMonthsLeft: number;
	outstandingCents: number;
}): LoanAction[] {
	const { status, side } = input;
	const out: LoanAction[] = [];
	if (status === 'proposed') {
		out.push('set_terms', 'set_schedule');
		if (!input.youSigned && input.scheduleMatchesPrincipal) out.push('sign');
	}
	const collecting = status === 'active' || status === 'paused';
	if (side === 'borrower' && collecting && input.pauseMonthsLeft > 0 && input.outstandingCents > 0) out.push('pause');
	if (side === 'borrower' && status === 'paused') out.push('resume');
	if (side === 'lender' && collecting && input.outstandingCents > 0) out.push('forgive');
	return out;
}
