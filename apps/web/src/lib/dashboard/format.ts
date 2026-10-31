import { formatUsd } from '#lib/core/format.ts';

const usdCents = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	minimumFractionDigits: 2,
	maximumFractionDigits: 2
});

/**
 * Integer cents as US dollars: whole dollars when there are no cents
 * (`$1,000`), otherwise exact (`$99.50`). A payment amount is never rounded.
 */
export function formatCents(cents: number): string {
	if (!Number.isInteger(cents)) throw new RangeError(`cents must be an integer, got ${cents}`);
	return cents % 100 === 0 ? formatUsd(cents / 100) : usdCents.format(cents / 100);
}

const dayFormat = new Intl.DateTimeFormat('en-US', {
	month: 'short',
	day: 'numeric',
	year: 'numeric',
	timeZone: 'UTC'
});

/** A Postgres `date` (`YYYY-MM-DD`) as `Nov 15, 2026`, with no timezone shift. */
export function formatDay(isoDate: string): string {
	return dayFormat.format(parseDay(isoDate));
}

export function parseDay(isoDate: string): Date {
	const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(isoDate);
	if (!m) throw new RangeError(`not a date: ${isoDate}`);
	return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
}

/** Today in the member's own timezone, as `YYYY-MM-DD`. */
export function localToday(now: Date = new Date()): string {
	const y = now.getFullYear();
	const m = String(now.getMonth() + 1).padStart(2, '0');
	const d = String(now.getDate()).padStart(2, '0');
	return `${y}-${m}-${d}`;
}

/**
 * Add calendar months to a `YYYY-MM-DD` date the way Postgres does
 * (`date + interval 'n months'`): the day is clamped to the month's last day.
 */
export function addMonths(isoDate: string, months: number): string {
	const d = parseDay(isoDate);
	const y = d.getUTCFullYear();
	const m = d.getUTCMonth() + months;
	const lastDay = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
	const out = new Date(Date.UTC(y, m, Math.min(d.getUTCDate(), lastDay)));
	return out.toISOString().slice(0, 10);
}
