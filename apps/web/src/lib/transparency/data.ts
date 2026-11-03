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

/** A published quarter: the three months summed, months counted honestly. */
export interface QuarterlySummary {
	fund: string;
	fundLabel: string;
	/** "Q3 2026" for readers. */
	quarter: string;
	months: number;
	requestsPaid: number;
	paidOutCents: number;
	allocatedCents: number;
	reserveCents: number;
	poolRuns: number;
	poolRunsShort: number;
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

export interface NeedsFormula {
	version: number;
	/** The day the version started being used, as stored. */
	effectiveFrom: string;
	/** Weights in bps (they sum to 10000, the schema checks it). */
	needBps: number;
	readinessBps: number;
	reliabilityBps: number;
}

/** A weight as a share of ten thousand, spelled for readers. */
export function shareWord(bps: number): string {
	const pct = bps / 100;
	return pct % 1 === 0 ? `${pct}%` : `${pct.toFixed(1)}%`;
}

/**
 * The published needs formulas, newest version first: `needs_formulas` is
 * readable by everyone and old versions stay so every member can ask which
 * formula priced their place in the queue. Only weights cross; inputs stay
 * private.
 */
export async function loadNeedsFormulas(db: Db): Promise<NeedsFormula[]> {
	// needs_formulas isn't in the committed generated types yet (`fromNew` seam).
	const result = await fromNew(db, 'needs_formulas')
		.select('version, need_bps, readiness_bps, reliability_bps, effective_from')
		.order('version', { ascending: false });
	const rows = must<Record<string, unknown>[]>(result, 'the published needs formula');
	return rows.map((row) => ({
		version: Number(row['version']),
		effectiveFrom: String(row['effective_from']),
		needBps: Number(row['need_bps']),
		readinessBps: Number(row['readiness_bps']),
		reliabilityBps: Number(row['reliability_bps'])
	}));
}

/** Calendar quarter a month belongs to, e.g. "Q3 2026". */
function quarterOf(month: string): string {
	const [year, index] = month.split('-').map(Number);
	return `Q${Math.floor((index - 1) / 3) + 1} ${year}`;
}

/**
 * The quarterly open-books report: the published months summed per fund and
 * calendar quarter. Only sums of figures the schema already published — the
 * page never recomputes a month itself. A quarter with fewer than three
 * published months carries its `months` count so the page can say so.
 */
export function quarterlySummaries(books: OpenBook[]): QuarterlySummary[] {
	const byFundQuarter = new Map<string, QuarterlySummary>();
	for (const book of books) {
		const quarter = quarterOf(book.month);
		const key = `${book.fund}/${quarter}`;
		const acc = byFundQuarter.get(key);
		if (acc === undefined) {
			byFundQuarter.set(key, {
				fund: book.fund,
				fundLabel: book.fundLabel,
				quarter,
				months: 1,
				requestsPaid: book.monthlyRequestsPaid,
				paidOutCents: book.paidOutCents,
				allocatedCents: book.allocatedCents,
				reserveCents: book.reserveCents,
				poolRuns: book.monthlyPoolRuns,
				poolRunsShort: book.monthlyPoolRunsShort
			});
			continue;
		}
		acc.months += 1;
		acc.requestsPaid += book.monthlyRequestsPaid;
		acc.paidOutCents += book.paidOutCents;
		acc.allocatedCents += book.allocatedCents;
		acc.reserveCents += book.reserveCents;
		acc.poolRuns += book.monthlyPoolRuns;
		acc.poolRunsShort += book.monthlyPoolRunsShort;
	}
	const fundOrder = ['protection', 'home_fund', 'people'];
	/** "Q3 2026" -> sortable number: year * 10 + quarter. */
	const rank = (quarter: string): number => Number(quarter.slice(3)) * 10 + Number(quarter.slice(1, 2));
	return [...byFundQuarter.values()].sort((a, b) => {
		if (rank(b.quarter) !== rank(a.quarter)) return rank(b.quarter) - rank(a.quarter);
		return fundOrder.indexOf(a.fund) - fundOrder.indexOf(b.fund);
	});
}
