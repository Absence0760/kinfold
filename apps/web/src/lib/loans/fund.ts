// Loans the lending Fund has taken out with you (roadmap 3a). Same no-interest
// promise as family loans, but the lender is the Fund itself: no invitation pair
// and no agreement page — the Fund signs at once, and only the partner's
// disbursement starts collection. Money still moves with the partner, never
// through Kinfold.

import { fromNew, rpcNew } from '#lib/supabase/client.ts';
import type { Db } from '#lib/supabase/client.ts';
import type { Tone } from '#lib/dashboard/labels.ts';
import { addMonths } from '#lib/dashboard/format.ts';

export interface FundLoanRow {
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
	// How many months a year the borrower may pause (the agreed allowance).
	pause_months_per_year: number;
	created_at: string;
}

export interface FundInstallmentRow {
	loan_id: string;
	// Schedule order, used for the pause preview like family loans.
	seq: number;
	due_on: string;
	amount_cents: number;
	paid_cents: number;
}

export interface FundPauseRow {
	loan_id: string;
	months: number;
	started_on: string;
}

export interface FundRestructureRow {
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

/** One Fund loan console view; the open restructure ask is the unapplied row. */
export interface FundLoanDetail {
	loan: FundLoanRow;
	installments: FundInstallmentRow[];
	pauses: FundPauseRow[];
	/** The borrower's staged ask waiting for the partner's event, or null. */
	restructure: FundRestructureRow | null;
	outstandingCents: number;
}

function cents(r: { data?: unknown; error: { message: string } | null }, what: string): number {
	if (r.error) throw new Error(`Couldn't load ${what}: ${r.error.message}`);
	return (r.data as number | null) ?? 0;
}

/** The day the latest pause on this loan runs out, or null with no pauses. */
export function pauseEnd(rows: FundPauseRow[], loanId: string): string | null {
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
		.select('id, principal_cents, status, schedule, income_share_bps, lien_bps, fund_signed_at, borrower_signed_at, pause_months_per_year, created_at')
		.eq('borrower_id', uid)
		.order('created_at', { ascending: false });
	if (rows.error) throw new Error(`Couldn't load the Fund loans: ${rows.error.message}`);
	const loans = (rows.data ?? []) as FundLoanRow[];
	if (loans.length === 0) return [];
	const ids = loans.map((l) => l.id);

	const [inst, pauses, restructures, outstanding, share] = await Promise.all([
		fromNew(db, 'fund_loan_installments').select('loan_id, seq, due_on, amount_cents, paid_cents').in('loan_id', ids).order('due_on'),
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

/**
 * One Fund loan's console view: the loan, its unpaid schedule, pause and
 * restructure history, and its outstanding read from the schema's own door.
 * RLS returns the loan only to its borrower, so a stranger gets null.
 */
export async function loadFundLoan(db: Db, loanId: string): Promise<FundLoanDetail | null> {
  const loanRow = await fromNew(db, 'fund_loans')
    .select('id, principal_cents, status, schedule, income_share_bps, lien_bps, fund_signed_at, borrower_signed_at, pause_months_per_year, created_at')
    .eq('id', loanId);
  if (loanRow.error) throw new Error(`Couldn't load the Fund loan: ${loanRow.error.message}`);
  const loan = ((loanRow.data ?? [])[0] ?? null) as FundLoanRow | null;
  if (loan === null) return null;

  const [inst, pauses, restructures, outstanding] = await Promise.all([
    fromNew(db, 'fund_loan_installments').select('loan_id, seq, due_on, amount_cents, paid_cents').eq('loan_id', loanId).order('due_on'),
    fromNew(db, 'fund_loan_pauses').select('loan_id, months, started_on').eq('loan_id', loanId),
    fromNew(db, 'fund_loan_restructures').select('loan_id, months, first_due, applied_at').eq('loan_id', loanId),
    rpcNew(db, 'fund_loan_outstanding_cents', { p_loan: loanId })
  ]);
  for (const r of [inst, pauses, restructures])
    if (r.error) throw new Error(`Couldn't load the Fund loan schedule: ${r.error.message}`);

  return {
    loan,
    installments: (inst.data ?? []) as FundInstallmentRow[],
    pauses: (pauses.data ?? []) as FundPauseRow[],
    restructure: (restructures.data ?? []).find((r: FundRestructureRow) => r.applied_at === null) ?? null,
    outstandingCents: cents(outstanding, 'the Fund loan balance')
  };
}

/** A door's refusal throws, so the page's `explainLoanError` explains it. */
function call(r: { error: { message: string; code?: string } | null }) {
	if (r.error) throw r.error;
}

export async function pauseFundLoan(db: Db, loan: string, months: number) {
	call(await rpcNew(db, 'pause_fund_loan', { p_loan: loan, p_months: months }));
}

export async function resumeFundLoan(db: Db, loan: string) {
	call(await rpcNew(db, 'resume_fund_loan', { p_loan: loan }));
}

/** Stages a new schedule; the lending partner's servicing event applies it. */
export async function restructureFundLoan(db: Db, loan: string, months: number, firstDue: string) {
	call(await rpcNew(db, 'restructure_fund_loan', { p_loan: loan, p_months: months, p_first_due: firstDue }));
}

/**
 * Why a pause of `months` would be refused, in the lending Fund's words — the
 * same allowance the schema enforces, so the console refuses before sending and
 * explains what the partner restructure door answers instead.
 */
export function fundPauseProblem(months: number, left: number): string | null {
	if (left === 0) return 'This loan’s pause allowance for the year is used up. Ask the lending Fund for a new schedule instead.';
	if (!Number.isInteger(months) || months < 1) return 'Choose at least one month.';
	if (months > left) return `You can pause up to ${left} month${left === 1 ? '' : 's'} right now.`;
	return null;
}
/** The borrower signs their side of a Fund loan the Fund already signed. */
export async function signFundLoan(db: Db, loan: string) {
	call(await rpcNew(db, 'sign_fund_loan', { p_loan: loan }));
}

/**
 * What the Fund loan console can offer now, in the borrower's frame: the Fund
 * signs at once so there are no terms or schedule forms; the borrower's own
 * moves are sign (while proposed), pause, resume, restructure. Money always
 * moves through the lending partner, never through a console door. Income
 * schedules are computed from income, so there is nothing to re-schedule.
 */
export function fundLoanActions(
	status: string,
	outstandingCents: number,
	pauseMonthsLeft: number,
	schedule: string,
	restructureWaiting: boolean
): FundLoanAction {
	const collecting = status === 'active' || status === 'paused';
	return {
		sign: status === 'proposed',
		pause: collecting && pauseMonthsLeft > 0 && outstandingCents > 0,
		resume: status === 'paused',
		restructure: collecting && schedule === 'monthly' && outstandingCents > 0 && !restructureWaiting
	};
}

export interface FundLoanAction {
	sign: boolean;
	pause: boolean;
	resume: boolean;
	restructure: boolean;
}
/** Why a restructure ask of `months` payments would be refused, or null. Mirrors
 * `restructure_fund_loan` so the console refuses before sending. Income
 * schedules have no rows to re-spread; the door says so. */
export function fundRestructureProblem(
	status: string,
	schedule: string,
	months: number,
	outstandingCents: number,
	restructureWaiting: boolean,
	firstDue: string,
	today: string
): string | null {
	if (status !== 'active' && status !== 'paused') return 'This Fund loan isn\u2019t collecting, so there is no schedule to change.';
	if (schedule !== 'monthly') return 'Income payments are sized from income each month; nothing to re-schedule.';
	if (restructureWaiting) return 'The lending Fund hasn\u2019t answered your last ask yet. One ask waits at a time.';
	if (!Number.isInteger(months) || months < 1) return 'Choose at least one payment.';
	if (firstDue < today) return 'A restructured schedule can\u2019t start in the past.';
	if (Math.floor(outstandingCents / months) === 0) return 'That\u2019s more payments than there are cents left to repay. Choose fewer.';
	return null;
}

/**
 * The dates and amounts the schema will write when it applies the ask:
 * `first_due` + one month per payment, split evenly with the last payment
 * taking the remainder — the same rule as `apply_fund_loan_restructure`, shown
 * so the preview matches what the partner's event will write.
 */
export function fundSplit(
	outstandingCents: number,
	months: number,
	firstDue: string
): FundPlannedPayment[] {
	if (months < 1 || Math.floor(outstandingCents / months) === 0) return [];
	const each = Math.floor(outstandingCents / months);
	return Array.from({ length: months }, (_, i) => ({
		seq: i + 1,
		dueOn: addMonths(firstDue, i),
		amountCents: i === months - 1 ? outstandingCents - each * (months - 1) : each
	}));
}

/**
 * The voluntary fair-lending self-test (1002.5(b)(1)): the borrower offers
 * their own race, ethnicity and sex for the fairness audit. The schema refuses
 * unless all four disclosures are acknowledged and refuses a second offer on a
 * loan — the borrower can never read the record back, so that refusal is the
 * console's marker that the offer went through.
 */
export async function offerFundLoanSelfTest(
	db: Db,
	loan: string,
	acknowledged: boolean,
	race: string,
	ethnicity: string,
	sex: string
) {
	call(await rpcNew(
		db,
		'offer_fair_lending_self_test',
		{
			p_loan: loan,
			p_purpose_ack: acknowledged,
			p_use_ack: acknowledged,
			p_limit_ack: acknowledged,
			p_retain_ack: acknowledged,
			p_race: race,
			p_ethnicity: ethnicity,
			p_sex: sex
		}
	));
}

export function fundSelfTestProblem(acknowledged: boolean): string | null {
	if (!acknowledged) return 'Check all four disclosures before offering the self-test.';
	return null;
}

export interface FundPlannedPayment {
	seq: number;
	dueOn: string;
	amountCents: number;
}
