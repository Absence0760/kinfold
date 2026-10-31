import { addMonths, parseDay } from '#lib/dashboard/format.ts';

/** One installment of a schedule preview, before it is saved. */
export interface PlannedInstallment {
	seq: number;
	dueOn: string;
	amountCents: number;
}

/** The limits `set_loan_schedule` enforces. */
export const MIN_MONTHS = 1;
export const MAX_MONTHS = 480;

/** The limits `set_loan_terms` enforces. */
export const MIN_PAYMENT_DAY = 1;
export const MAX_PAYMENT_DAY = 28;

/**
 * Why a schedule can't be set, or null when it can. Mirrors the refusals in
 * `set_loan_schedule`: 1 to 480 months, and at least one cent each month.
 */
export function scheduleProblem(principalCents: number, months: number): string | null {
	if (!Number.isInteger(months) || months < MIN_MONTHS || months > MAX_MONTHS)
		return `Choose 1 to ${MAX_MONTHS} monthly installments.`;
	if (Math.floor(principalCents / months) === 0)
		return 'That’s more installments than there are cents to repay. Choose fewer.';
	return null;
}

/**
 * The first due date `set_loan_schedule` picks: the payment day in the month
 * of `firstDue`, or in the next month when `firstDue` is past the payment day.
 * So the first installment is never earlier than the date asked for.
 */
export function firstDueOn(firstDue: string, paymentDay: number): string {
	const d = parseDay(firstDue);
	const monthStart = `${firstDue.slice(0, 7)}-01`;
	const month = d.getUTCDate() > paymentDay ? addMonths(monthStart, 1) : monthStart;
	return `${month.slice(0, 8)}${String(paymentDay).padStart(2, '0')}`;
}

/**
 * The schedule `set_loan_schedule` would write, worked out the same way:
 * equal monthly installments of `floor(principal / months)` cents on the
 * payment day, with the last taking the remainder so the total is exactly the
 * principal. No interest, so nothing is ever added.
 *
 * Returns an empty list when the database would refuse (see `scheduleProblem`).
 */
export function planSchedule(
	principalCents: number,
	months: number,
	firstDue: string,
	paymentDay: number
): PlannedInstallment[] {
	if (!Number.isSafeInteger(principalCents) || principalCents <= 0) return [];
	if (scheduleProblem(principalCents, months)) return [];
	const each = Math.floor(principalCents / months);
	const start = firstDueOn(firstDue, paymentDay);
	return Array.from({ length: months }, (_, i) => ({
		seq: i + 1,
		dueOn: addMonths(start, i),
		amountCents: i === months - 1 ? principalCents - each * (months - 1) : each
	}));
}

/**
 * Where `set_loan_terms` moves an existing installment when the payment day
 * changes: same month, new day.
 */
export function moveToPaymentDay(dueOn: string, paymentDay: number): string {
	return `${dueOn.slice(0, 8)}${String(paymentDay).padStart(2, '0')}`;
}

/** A schedule's total, in cents. */
export function scheduleTotal(rows: readonly { amountCents: number }[]): number {
	return rows.reduce((a, r) => a + r.amountCents, 0);
}

/** A one-line summary like "6 of $100, then $100.04". */
export function describeSplit(rows: readonly PlannedInstallment[], format: (cents: number) => string): string {
	if (rows.length === 0) return '';
	if (rows.length === 1) return `One payment of ${format(rows[0].amountCents)}`;
	const first = rows[0].amountCents;
	const last = rows[rows.length - 1].amountCents;
	if (first === last) return `${rows.length} monthly payments of ${format(first)}`;
	return `${rows.length - 1} monthly payments of ${format(first)}, then ${format(last)}`;
}

/** The day after a `YYYY-MM-DD` date. */
export function dayAfter(isoDate: string): string {
	const d = parseDay(isoDate);
	d.setUTCDate(d.getUTCDate() + 1);
	return d.toISOString().slice(0, 10);
}
