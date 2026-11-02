import {
	decidedLabel,
	statusLabel,
	type EvidenceKind,
	type RedactionStatus,
	type RequestKind,
	type RequestStatus,
	type ReviewDecision
} from './labels.ts';

// --- rows as selected (only the columns the console shows) --------------------

export interface QueueRequestRow {
	id: string;
	kind: RequestKind;
	status: RequestStatus;
	amount_cents: number;
	public_summary: string | null;
	current_score: number | null;
	incident_on: string;
	submitted_at: string | null;
}

export interface ScoreRow {
	request_id: string;
	score: number;
	reasons: unknown;
	model_version: string;
	created_at: string;
}

/** Evidence metadata only: never `original_path`, which is private to the member. */
export interface EvidenceRow {
	id: string;
	request_id: string;
	kind: EvidenceKind;
	redaction_status: RedactionStatus;
	captured_in_app: boolean;
	created_at: string;
}

export interface ReviewRow {
	request_id: string;
	decision: ReviewDecision;
	reason: string;
	created_at: string;
	/** Present on panel reads; used only to spot the viewer's own reviews, never shown. */
	reviewer_id?: string;
}

export interface AppealRow {
	id: string;
	request_id: string;
	reason: string;
	status: 'open' | 'upheld' | 'denied';
	created_at: string;
}

// --- assembled for the page -------------------------------------------------------

/** The kinds the Home Fund ranks by need (fund_for_kind in the schema). */
export function isHomeFundKind(kind: string): boolean {
	return kind === 'home_repair' || kind === 'down_payment' ||
		kind === 'mortgage_gap' || kind === 'loan_payoff';
}

export interface ScoreView {
	score: number;
	reasons: string[];
	modelVersion: string;
	at: string;
}

/** One row of the Fund's needs ranking (`needs_records`, filtered by RLS). */
export interface NeedsRow {
	request_id: string;
	score: number;
	formula_version: number;
}

/** The Fund's ranking a Home Fund applicant got, newest effective version. */
export interface NeedsView {
	score: number;
	formulaVersion: number;
}

export interface QueueItem {
	request: QueueRequestRow;
	score: ScoreView | null;
	evidence: EvidenceRow[];
	/** Reviews this reviewer already wrote on it, oldest first. */
	myReviews: ReviewRow[];
	/** The Fund's needs ranking, when one is recorded. */
	needs: NeedsView | null;
	/** False when the database says this viewer may not review it. */
	mayReview: boolean;
}

/**
 * A score's reasons as display lines. `scores.reasons` is a non-empty JSON
 * array; entries are normally strings, but an object with a `text` or `reason`
 * field is read too, so a richer scorer format still shows its explanation
 * instead of nothing.
 */
export function scoreReasons(reasons: unknown): string[] {
	if (!Array.isArray(reasons)) return [];
	return reasons
		.map((r): string => {
			if (typeof r === 'string') return r;
			if (r && typeof r === 'object') {
				const o = r as Record<string, unknown>;
				for (const key of ['text', 'reason', 'label']) {
					if (typeof o[key] === 'string') return o[key] as string;
				}
			}
			return '';
		})
		.map((s) => s.trim())
		.filter((s) => s.length > 0);
}

function byTimeAsc<T extends { created_at: string }>(a: T, b: T): number {
	return a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : 0;
}

/** The most recent score for each request. */
export function latestScores(scores: readonly ScoreRow[]): Map<string, ScoreView> {
	const out = new Map<string, ScoreView>();
	for (const s of [...scores].sort(byTimeAsc)) {
		out.set(s.request_id, {
			score: s.score,
			reasons: scoreReasons(s.reasons),
			modelVersion: s.model_version,
			at: s.created_at
		});
	}
	return out;
}

function groupBy<T extends { request_id: string }>(rows: readonly T[]): Map<string, T[]> {
	const out = new Map<string, T[]>();
	for (const row of rows) {
		const list = out.get(row.request_id) ?? [];
		list.push(row);
		out.set(row.request_id, list);
	}
	return out;
}

/** Order the queue: what a person can act on first, oldest submission first. */
const QUEUE_ORDER: Partial<Record<RequestStatus, number>> = {
	in_review: 0,
	needs_evidence: 1,
	refused: 2
};

export function buildQueue(
	requests: readonly QueueRequestRow[],
	scores: readonly ScoreRow[],
	evidence: readonly EvidenceRow[],
	myReviews: readonly ReviewRow[],
	/** The Fund's needs ranking rows RLS lets this viewer read. */
	needs: readonly NeedsRow[] = [],
	/** Requests the database says this viewer may not review. */
	mayNotReview: readonly string[] = []
): QueueItem[] {
	const score = latestScores(scores);
	// One map pass: later rows overwrite earlier ones, so sort by version
	// ascending and the highest formula version ends up on the map.
	const needsByRequest = new Map(
		[...needs]
			.sort((a, b) => a.formula_version - b.formula_version)
			.map((row) => [row.request_id, row])
	);
	const ev = groupBy(evidence);
	const mine = groupBy(myReviews);
	return [...requests]
		.sort(
			(a, b) =>
				(QUEUE_ORDER[a.status] ?? 9) - (QUEUE_ORDER[b.status] ?? 9) ||
				(a.submitted_at ?? '').localeCompare(b.submitted_at ?? '')
		)
		.map((request) => ({
			request,
			score: score.get(request.id) ?? null,
			evidence: [...(ev.get(request.id) ?? [])].sort(byTimeAsc),
			myReviews: [...(mine.get(request.id) ?? [])].sort(byTimeAsc),
			needs: (() => {
				const row = needsByRequest.get(request.id);
				return row === undefined
					? null
					: { score: row.score, formulaVersion: row.formula_version };
			})(),
			mayReview: !mayNotReview.includes(request.id)
		}));
}

export interface AppealItem {
	appeal: AppealRow;
	/** The refusal being appealed: the latest refuse review before the appeal. */
	refusal: ReviewRow | null;
	/** Every review on the request, oldest first, without who wrote it. */
	history: Omit<ReviewRow, 'reviewer_id'>[];
	/** The request itself, when RLS lets this viewer read it. */
	request: QueueRequestRow | null;
	score: ScoreView | null;
	/** The viewer reviewed this request, so `decide_appeal` will refuse them. */
	viewerReviewed: boolean;
}

export function buildAppeals(
	appeals: readonly AppealRow[],
	reviews: readonly ReviewRow[],
	requests: readonly QueueRequestRow[],
	scores: readonly ScoreRow[],
	viewerId: string
): AppealItem[] {
	const byRequest = groupBy([...reviews].sort(byTimeAsc));
	const requestById = new Map(requests.map((r) => [r.id, r]));
	const score = latestScores(scores);
	return [...appeals].sort(byTimeAsc).map((appeal) => {
		const all = byRequest.get(appeal.request_id) ?? [];
		const refusals = all.filter((r) => r.decision === 'refuse' && r.created_at <= appeal.created_at);
		return {
			appeal,
			refusal: refusals.at(-1) ?? null,
			history: all.map(({ reviewer_id: _hidden, ...rest }) => rest),
			request: requestById.get(appeal.request_id) ?? null,
			score: score.get(appeal.request_id) ?? null,
			viewerReviewed: all.some((r) => r.reviewer_id === viewerId)
		};
	});
}

/** The confirmation after `record_review`, from the status it returned. */
export function reviewOutcome(decision: ReviewDecision, next: RequestStatus): string {
	const done = decidedLabel(decision);
	if (decision === 'refuse' && next !== 'refused')
		return `${done}. Money has already reached the payee, so the request stays in review until it's recovered.`;
	if (next === 'open') return `${done}. The request is open for funding.`;
	if (next === 'funded') return `${done}. Its pledges already cover it, so it's back to funded.`;
	if (next === 'needs_evidence') return `${done}. The member has been asked for more.`;
	if (next === 'refused') return `${done}. The member can appeal to the panel.`;
	return `${done}. The request is now “${statusLabel(next)}”.`;
}

/** The confirmation after `decide_appeal`. */
export function appealOutcome(uphold: boolean): string {
	return uphold
		? 'Appeal upheld. The request is back in review for a fresh decision.'
		: 'Appeal denied. The refusal stands.';
}
