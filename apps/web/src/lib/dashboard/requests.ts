import type { Database, Json } from '../../../../backend/supabase/database.types.ts';
import { requestSortRank } from './labels.ts';

type Tables = Database['public']['Tables'];
export type RequestRow = Pick<
	Tables['requests']['Row'],
	'id' | 'title' | 'kind' | 'status' | 'funding' | 'amount_cents' | 'created_at'
>;
export type ScoreRow = Pick<Tables['scores']['Row'], 'request_id' | 'score' | 'reasons' | 'model' | 'model_version' | 'created_at'>;
export type ContributionRow = Pick<Tables['contributions']['Row'], 'request_id' | 'source' | 'amount_cents' | 'status'>;

export interface RequestScore {
	score: number;
	reasons: string[];
	model: string;
	modelVersion: string;
	scoredAt: string;
}

export interface RequestCard extends RequestRow {
	/** The latest evidence score, or null when it hasn't been scored. */
	score: RequestScore | null;
	/** Pledged or collected so far (people and pool), in cents. */
	raisedCents: number;
}

/**
 * A score's reasons as a list of sentences. The scorer writes a JSON array of
 * strings; anything else in there is dropped rather than shown raw.
 */
export function parseReasons(reasons: Json): string[] {
	if (!Array.isArray(reasons)) return [];
	return reasons.flatMap((r) => {
		if (typeof r === 'string') return r.trim() ? [r.trim()] : [];
		if (r && typeof r === 'object' && !Array.isArray(r)) {
			const text = r.reason ?? r.text;
			if (typeof text === 'string' && text.trim()) return [text.trim()];
		}
		return [];
	});
}

/** The newest score per request (scores are append-only; a rescore adds a row). */
export function latestScores(scores: readonly ScoreRow[]): Map<string, RequestScore> {
	const out = new Map<string, RequestScore & { at: number }>();
	for (const s of scores) {
		const at = Date.parse(s.created_at);
		const prev = out.get(s.request_id);
		if (prev && prev.at >= at) continue;
		out.set(s.request_id, {
			score: s.score,
			reasons: parseReasons(s.reasons),
			model: s.model,
			modelVersion: s.model_version,
			scoredAt: s.created_at,
			at
		});
	}
	return new Map([...out].map(([id, { at: _at, ...score }]) => [id, score]));
}

/**
 * Raised so far per request: pledged and collected money, from people and the
 * pool. Released and refunded money no longer counts (matches `raised_cents`).
 */
export function raisedByRequest(contributions: readonly ContributionRow[]): Map<string, number> {
	const out = new Map<string, number>();
	for (const c of contributions) {
		if (c.status !== 'pledged' && c.status !== 'captured') continue;
		out.set(c.request_id, (out.get(c.request_id) ?? 0) + c.amount_cents);
	}
	return out;
}

/** The member's requests, things needing them first, newest first within that. */
export function buildRequestCards(
	requests: readonly RequestRow[],
	scores: readonly ScoreRow[],
	contributions: readonly ContributionRow[]
): RequestCard[] {
	const byScore = latestScores(scores);
	const raised = raisedByRequest(contributions);
	return requests
		.map((r) => ({ ...r, score: byScore.get(r.id) ?? null, raisedCents: raised.get(r.id) ?? 0 }))
		.sort(
			(a, b) =>
				requestSortRank(a.status) - requestSortRank(b.status) ||
				Date.parse(b.created_at) - Date.parse(a.created_at)
		);
}

/** Whether a "raised so far" figure means anything yet for this request. */
export function showsRaised(card: Pick<RequestCard, 'status' | 'raisedCents'>): boolean {
	return card.status === 'open' || card.status === 'funded' || card.status === 'paid' || card.raisedCents > 0;
}
