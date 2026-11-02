import { LoadError } from '#lib/auth/errors.ts';
import { fromNew, supabase, type Db } from '#lib/supabase/client.ts';

export interface OpenBook {
	fund: string;
	fundLabel: string;
	/** First day of the month, as stored. */
	month: string;
	/** "October 2026" for readers. */
	yearMonth: string;
	/** Small-numbers rules (counts 0 or >= 11, money rounded to $1,000) are enforced by the schema at publish time. */
	monthlyRequestsPaid: number;
	paidOutCents: number;
	allocatedCents: number;
	reserveCents: number;
	monthlyPoolRuns: number;
	monthlyPoolRunsShort: number;
}

type Result<T> = { data: T | null; error: { message: string; code?: string } | null; status?: number };

function must<T>(result: Result<T>, what: string): T {
	if (result.error) throw new LoadError(what, result.error, result.status);
	return result.data as T;
}

const FUND_LABEL: Record<string, string> = { protection: 'Car help', 'home_fund': 'Home help', people: 'Family and friends' };

/** "2026-10-01" -> "October 2026". */
function monthName(month: string): string {
	const [year, index] = month.split('-').map(Number);
	const names = [
		'January',
		'February',
		'March',
		'April',
		'May',
		'June',
		'July',
		'August',
		'September',
		'October',
		'November',
		'December'
	];
	return `${names[index - 1]} ${year}`;
}

/**
 * The published open books, newest month first. `open_books` is readable by
 * everyone (anon included): it only ever carries totals that survive the
 * small-numbers rules the schema enforces at publish time.
 */
export async function loadOpenBooks(db: Db): Promise<OpenBook[]> {
	// open_books isn't in the committed generated types yet (`fromNew` seam).
	const result = await fromNew(db, 'open_books')
		.select(
			'fund, month, requests_paid, paid_out_cents, allocated_cents, reserve_cents, pool_runs, pool_runs_short, published_at'
		)
		.order('month', { ascending: false });
	const rows = must<Record<string, unknown>[]>(result, 'the open books');
	return rows.map((row) => {
		const month = String(row['month']);
		return {
			fund: String(row['fund']),
			fundLabel: FUND_LABEL[String(row['fund'])] ?? String(row['fund']),
			month,
			yearMonth: monthName(month),
			monthlyRequestsPaid: Number(row['requests_paid']),
			paidOutCents: Number(row['paid_out_cents']),
			allocatedCents: Number(row['allocated_cents']),
			reserveCents: Number(row['reserve_cents']),
			monthlyPoolRuns: Number(row['pool_runs']),
			monthlyPoolRunsShort: Number(row['pool_runs_short'])
		};
	});
}
