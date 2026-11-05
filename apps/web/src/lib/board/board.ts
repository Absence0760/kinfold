import type { Database } from '../../../../backend/supabase/database.types.ts';
export { scoreBandLabel } from '#lib/requests/score-band.ts';

// Pure helpers for the members-only request board (/app/board). Everything
// here works on what the `board_requests` view exposes and nothing more: no
// names, no towns, no member ids, no exact dates. The board never sorts or
// filters by who gave or who asked.

export type RequestKind = Database['public']['Enums']['request_kind'];
export type RequestStatus = Database['public']['Enums']['request_status'];
export type BoardRow = Database['public']['Views']['board_requests']['Row'];
/** A `board_requests` row with its progress columns (`raised_cents`,
 * `taking_pledges`): the generated view type carries both now, and a view
 * column is nullable, so a missing figure still reads as null. */
export type BoardRowProgress = BoardRow;

/** One request on the board, as the page shows it. */
export interface BoardItem {
	id: string;
	kind: RequestKind;
	summary: string;
	status: RequestStatus;
	/** The exact ask, only while the request is still open. */
	amountCents: number | null;
	bandMinCents: number | null;
	bandMaxCents: number | null;
	/** 10-point evidence score band: 80 means 80 to 89. */
	scoreBand: number | null;
	/** The minimum score of the fund this request draws on (`fund_settings.min_score`); null when not read. */
	minScore: number | null;
	/** State, or Census division where the state is small. */
	area: string | null;
	/** First day of the month it was posted, `YYYY-MM-DD`. */
	monthOf: string | null;
	/** Pledged or collected so far; null when the backend doesn't share it. */
	raisedCents: number | null;
	/** Whether a pledge would be accepted now (open and the payee verified); null when the row predates the view's column. */
	takingPledges: boolean | null;
	/** The viewer posted this request. */
	own: boolean;
}

export const KIND_LABELS: Record<RequestKind, string> = {
	car_damage: 'Car damage',
	car_deductible: 'Car deductible',
	home_repair: 'Home repair',
	down_payment: 'Down payment',
	mortgage_gap: 'Mortgage gap',
	loan_payoff: 'Loan payoff'
};

/** Who is paid when the request is funded. Never the member. */
const PAYEE: Record<RequestKind, string> = {
	car_damage: 'the repair shop, against its invoice',
	car_deductible: 'the repair shop, against its invoice',
	home_repair: 'the contractor, against its invoice',
	down_payment: 'the seller or title company at closing',
	mortgage_gap: 'the mortgage lender',
	loan_payoff: 'the lender holding the loan'
};

export const kindLabel = (kind: RequestKind): string => KIND_LABELS[kind];
export const payeeLabel = (kind: RequestKind): string => PAYEE[kind];

/**
 * The pooled fund a board request draws on, as `public.fund_for_kind` maps it:
 * car requests from the community repair fund, home requests from the Home
 * Fund. Every board request is pool-funded (`on_board`), and members can give
 * on top.
 */
export const fundLabel = (kind: RequestKind): string =>
	kind === 'car_damage' || kind === 'car_deductible'
		? 'the community repair fund'
		: 'the Community Home Fund';

export const STATUS_LABELS: Partial<Record<RequestStatus, string>> = {
	open: 'Asking now',
	funded: 'Funded',
	paid: 'Paid to the payee'
};

export const statusLabel = (status: RequestStatus): string => STATUS_LABELS[status] ?? status;

/** Rows missing the fields the board can't do without are dropped. */
export function toItems(
	rows: BoardRowProgress[],
	ownIds: ReadonlySet<string>,
	raised: ReadonlyMap<string, number>,
	minScoreOf: (kind: RequestKind) => number | null = () => null
): BoardItem[] {
	const items: BoardItem[] = [];
	for (const r of rows) {
		if (!r.id || !r.kind || !r.public_summary || !r.status) continue;
		items.push({
			id: r.id,
			kind: r.kind,
			summary: r.public_summary,
			status: r.status,
			amountCents: r.amount_cents,
			bandMinCents: r.amount_band_min_cents,
			bandMaxCents: r.amount_band_max_cents,
			scoreBand: r.score_band,
			minScore: minScoreOf(r.kind),
			area: r.area,
			monthOf: r.month_of,
			raisedCents: r.raised_cents ?? raised.get(r.id) ?? null,
			takingPledges: r.taking_pledges ?? null,
			own: ownIds.has(r.id)
		});
	}
	return items;
}

// --- filter and sort -----------------------------------------------------------------

export type KindFilter = RequestKind | 'all';
export type StatusFilter = 'open' | 'all';
export type SortOrder = 'newest' | 'closest' | 'evidence';

export const SORT_LABELS: Record<SortOrder, string> = {
	newest: 'Newest first',
	closest: 'Closest to funded',
	evidence: 'Strongest evidence first'
};

export function filterItems(items: BoardItem[], kind: KindFilter, status: StatusFilter): BoardItem[] {
	return items.filter(
		(i) => (kind === 'all' || i.kind === kind) && (status === 'all' || i.status === 'open')
	);
}

/** Share raised, 0 to 1; null when there is no exact ask or no progress to show. */
export function fundedShare(item: BoardItem): number | null {
	if (item.amountCents == null || item.amountCents <= 0 || item.raisedCents == null) return null;
	return Math.min(1, Math.max(0, item.raisedCents / item.amountCents));
}

const byId = (a: BoardItem, b: BoardItem) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
const byNewest = (a: BoardItem, b: BoardItem) => (b.monthOf ?? '').localeCompare(a.monthOf ?? '');

/**
 * Sort without mutating. Ties fall back to newest, then id, so the order is
 * stable. Requests with no progress to show sort after those with some when
 * sorting by how close they are.
 */
export function sortItems(items: BoardItem[], order: SortOrder): BoardItem[] {
	const out = [...items];
	out.sort((a, b) => {
		if (order === 'closest') {
			const sa = fundedShare(a) ?? -1;
			const sb = fundedShare(b) ?? -1;
			if (sa !== sb) return sb - sa;
		} else if (order === 'evidence') {
			const d = (b.scoreBand ?? -1) - (a.scoreBand ?? -1);
			if (d !== 0) return d;
		}
		return byNewest(a, b) || byId(a, b);
	});
	return out;
}

/** Kinds present on the board, in the order the product lists them. */
export function kindsPresent(items: BoardItem[]): RequestKind[] {
	const seen = new Set(items.map((i) => i.kind));
	return (Object.keys(KIND_LABELS) as RequestKind[]).filter((k) => seen.has(k));
}

// --- money and labels ---------------------------------------------------------------

const whole = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	maximumFractionDigits: 0
});
const exact = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	minimumFractionDigits: 2
});

/** Integer cents as dollars; cents shown only when there are any. */
export function formatCents(cents: number): string {
	return cents % 100 === 0 ? whole.format(cents / 100) : exact.format(cents / 100);
}

/** The exact ask while open, else the amount band. */
export function amountText(item: BoardItem): string {
	if (item.amountCents != null) return formatCents(item.amountCents);
	if (item.bandMinCents == null) return 'Amount not shown';
	if (item.bandMaxCents == null) return `${formatCents(item.bandMinCents)} or more`;
	return `${formatCents(item.bandMinCents)} to ${formatCents(item.bandMaxCents)}`;
}

export interface Progress {
	raisedCents: number;
	leftCents: number;
	/** Whole percent, rounded down so "100%" only ever means fully funded. */
	percent: number;
	/** The same facts as text, for people who can't see the bar. */
	text: string;
}

export function progress(item: BoardItem): Progress | null {
	const share = fundedShare(item);
	if (share == null || item.amountCents == null || item.raisedCents == null) return null;
	const raised = Math.min(item.raisedCents, item.amountCents);
	const left = item.amountCents - raised;
	const percent = Math.floor(share * 100);
	const text =
		left === 0
			? `${formatCents(raised)} raised of ${formatCents(item.amountCents)}, fully pledged`
			: `${formatCents(raised)} raised of ${formatCents(item.amountCents)}, ${formatCents(left)} still needed`;
	return { raisedCents: raised, leftCents: left, percent, text };
}

const MONTHS = [
	'January', 'February', 'March', 'April', 'May', 'June',
	'July', 'August', 'September', 'October', 'November', 'December'
];

/** `2026-10-01` → `October 2026`, read as a calendar date (no time zone shift). */
export function monthLabel(monthOf: string | null): string {
	const m = monthOf?.match(/^(\d{4})-(\d{2})/);
	if (!m) return 'Month not shown';
	const month = MONTHS[Number(m[2]) - 1];
	return month ? `${month} ${m[1]}` : 'Month not shown';
}

// --- pledge input -------------------------------------------------------------------

/**
 * Parse what a member typed as a dollar amount into integer cents. Accepts
 * `50`, `$50`, `1,250.5`, `12.34`; rejects more than two decimals, negatives
 * and anything else. Returns null when it isn't a usable amount.
 */
export function parseDollars(input: string): number | null {
	const s = input.trim().replace(/^\$/, '').replace(/,/g, '');
	if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
	const [d, c = ''] = s.split('.');
	const cents = Number(d) * 100 + Number(c.padEnd(2, '0'));
	return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
}

/** Why an amount can't be pledged, or null when it can. */
export function pledgeAmountProblem(cents: number | null, leftCents: number): string | null {
	if (cents == null) return 'Enter an amount in dollars, like 50 or 25.50.';
	if (cents > leftCents) return `This request needs ${formatCents(leftCents)} more, so pledge up to that.`;
	return null;
}

/** Quick-pick amounts that fit what's left, ending with "the rest". */
export function quickAmounts(leftCents: number): number[] {
	const picks = [2_500, 5_000, 10_000].filter((c) => c < leftCents);
	if (leftCents > 0) picks.push(leftCents);
	return picks;
}

// --- accessible names and status lines ------------------------------------------------

/**
 * A short form of a card's summary for button names, so ten "Pledge a gift"
 * buttons each say which request they belong to ("Pledge a gift to “Rear-ended
 * at a light, bumper…”"). Cut at a word boundary, never mid-word.
 */
export function shortTitle(summary: string, max = 60): string {
	const s = summary.replace(/\s+/g, ' ').trim();
	if (s.length <= max) return s;
	const cut = s.slice(0, max);
	const space = cut.lastIndexOf(' ');
	return `${(space > max / 2 ? cut.slice(0, space) : cut).replace(/[\s,.;:–—-]+$/, '')}…`;
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** What the filtered board shows, as one line (also what the live region announces). */
export function countText(
	shown: number,
	status: StatusFilter,
	kind: KindFilter,
	openCount: number
): string {
	if (status === 'open')
		return `${plural(shown, 'request', 'requests')} asking now${kind === 'all' ? '' : `, ${kindLabel(kind).toLowerCase()}`}.`;
	return `${plural(shown, 'request', 'requests')} in the last 12 months; ${openCount} still asking.`;
}
