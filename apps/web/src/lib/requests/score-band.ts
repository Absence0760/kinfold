// How a evidence score is put into words on member screens (home, the
// request page, the board). The review console shows the bare score, band and
// reasons instead, so reviewers aren't anchored on a verdict-like label.
//
// design.md §3: the score measures how well the evidence supports a request,
// not the person. A score below the minimum "never means 'denied'. It means
// 'needs more evidence' and goes to a trained member reviewer." Only a
// person's recorded decision refuses. So nothing here ever says denied,
// failed, rejected or refused, and the wording follows the request's status
// (what the database and any person already decided) before the score.
//
// The minimum is the fund's own `fund_settings.min_score`. It is only compared
// with the score while no person has decided, and only when the comparison
// agrees with the status the database set: the minimum may have changed since
// the request was scored, and the status line must never contradict the status.
// No runtime imports, so any module (board.ts included) can use it without a cycle.

import type { Database } from '../../../../backend/supabase/database.types.ts';

/** Width of a score band, as the board view and the allocation use it. */
export const BAND_SIZE = 10;

export type RequestStatus = Database['public']['Enums']['request_status'];

/** The two pooled funds (`public.fund`, less `people`). */
export type PoolFund = 'protection' | 'home_fund';

/**
 * - `needs-evidence`: waiting for more evidence. The only tone shown warm, and
 *   only on the member's own screens, never on the board.
 * - `review`: with a member reviewer.
 * - `strong` / `enough`: at or above the minimum (90+ is `strong`).
 * - `accepted`: open, funded or paid after a person approved it, or when the
 *   comparison with today's minimum can't be trusted.
 * - `decided`: a person decided, with an appeal.
 * - `near`: board only; the fund's minimum falls inside the band.
 * - `gifts`: board only; a band below the fund's current minimum, so the fund
 *   doesn't pay it and it relies on gifts. Says nothing about who approved it:
 *   the minimum may have risen since the request opened.
 */
export type ScoreTone = 'needs-evidence' | 'review' | 'strong' | 'enough' | 'accepted' | 'decided' | 'near' | 'gifts';

export interface ScoreBand {
	/** First score in the band: 80 means 80 to 89; the top band runs to 100. */
	band: number;
	/** "80 to 89". Words, not a dash, so a screen reader doesn't say "minus". */
	label: string;
	tone: ScoreTone;
	/** Short status: "Strong evidence", "Needs more evidence". */
	status: string;
	/** One plain sentence on what the status means. */
	detail: string;
}

/** A `fund_settings` row, as much of it as this needs. */
export interface FundMinimum {
	fund: string;
	min_score: number;
}

function check(name: string, value: number): void {
	// The database checks both columns `between 0 and 100`; anything else is a bug upstream.
	if (!Number.isInteger(value) || value < 0 || value > 100) {
		throw new RangeError(`${name} must be a whole number from 0 to 100, got ${value}`);
	}
}

/** The band a score falls in: 87 → 80, 100 → 90 (the top band runs to 100). */
export function bandOf(score: number): number {
	check('score', score);
	return Math.min(90, Math.floor(score / BAND_SIZE) * BAND_SIZE);
}

/** "80 to 89"; the top band runs to 100. */
export function scoreBandLabel(band: number): string {
	return band >= 90 ? `${band} to 100` : `${band} to ${band + BAND_SIZE - 1}`;
}

/**
 * The fund's minimum score, or null when its settings weren't read or it has
 * no row. Never a guess: the screen shouldn't invent a number it can't show
 * the member came from the fund's settings.
 */
export function minScoreFor(settings: readonly FundMinimum[] | null | undefined, fund: string): number | null {
	return settings?.find((s) => s.fund === fund)?.min_score ?? null;
}

const NEEDS = 'Needs more evidence';
const REVIEWER_LOOKS = 'A trained member reviewer looks at it, and more evidence can raise the score.';

export interface ScoreContext {
	/** The request's status: the wording follows it. */
	status: RequestStatus;
	/** The fund's minimum, or null when it isn't known. Used only before any review. */
	minScore: number | null;
	/**
	 * What a person did since the current score (`reviewSinceScore`). `'none'`
	 * lets the wording compare against the minimum; `undefined` (not loaded)
	 * keeps to what the status alone says.
	 */
	review?: ReviewSinceScore;
}

/** A person's review since the current score: none, an approval, or another decision. */
export type ReviewSinceScore = 'none' | 'approved' | 'other';

/**
 * Only reviews written after the current score count: a member asked for more
 * evidence, resubmitted, and was opened by the new score with no person
 * involved must not be told a reviewer approved it.
 */
export function reviewSinceScore(
	reviews: readonly { decision: string; created_at: string }[],
	scoredAt: string
): ReviewSinceScore {
	const since = reviews
		.filter((r) => Date.parse(r.created_at) > Date.parse(scoredAt))
		.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
	if (since.length === 0) return 'none';
	return since[0].decision === 'approve' ? 'approved' : 'other';
}

/**
 * The member's own request: its exact score in words, or null when the status
 * gives the score nothing to say (draft, being scored again, withdrawn, expired).
 */
export function scoreBand(score: number, { status, minScore, review }: ScoreContext): ScoreBand | null {
	check('score', score);
	if (minScore != null) check('minimum', minScore);
	const band = bandOf(score);
	const label = scoreBandLabel(band);
	const out = (tone: ScoreTone, status: string, detail: string): ScoreBand => ({ band, label, tone, status, detail });
	// Compare with today's minimum only while no person has decided and the
	// comparison agrees with the status the database set from the minimum.
	const beforeReview = review === 'none' && minScore != null;

	switch (status) {
		case 'needs_evidence':
			return beforeReview && score < minScore
				? out(
						'needs-evidence',
						NEEDS,
						`Below the fund's minimum of ${minScore}, so a trained member reviewer looks at it. More evidence can raise the score.`
					)
				: out('needs-evidence', NEEDS, REVIEWER_LOOKS);
		case 'in_review':
			return out('review', 'With a reviewer', 'A trained member reviewer is looking at it. More evidence can raise the score.');
		case 'open':
		case 'funded':
		case 'paid':
			if (beforeReview && score >= minScore) {
				return score >= 90
					? out('strong', 'Strong evidence', `In the top band, at or above the fund's minimum of ${minScore}.`)
					: out('enough', 'Enough evidence', `At or above the fund's minimum of ${minScore}.`);
			}
			return out(
				'accepted',
				'Evidence accepted',
				review === 'approved' ? 'A member reviewer approved it.' : "It met the fund's minimum score, or a member reviewer approved it."
			);
		case 'refused':
			return out(
				'decided',
				'A person decided',
				'A member reviewer made this decision and wrote down why. You can appeal it once, to someone new.'
			);
		default:
			return null;
	}
}

/**
 * A board band (`board_requests.score_band`, the exact score hidden) in words,
 * or null when the fund's minimum isn't known. The board lists only open,
 * funded and paid requests (`on_board`), so a band below the minimum is never
 * worded as needing evidence and never warm, and never as "approved by a
 * reviewer" either: the minimum may have risen since it opened. Only the repair
 * fund pays by band; the Home Fund is meant to choose by its needs formula
 * (design.md § Product 3), which isn't live yet, so no band claim for it.
 */
export function boardBand(band: number, fund: PoolFund, minScore: number | null): ScoreBand | null {
	check('band', band);
	if (band % BAND_SIZE !== 0) throw new RangeError(`band must be a multiple of ${BAND_SIZE}, got ${band}`);
	if (minScore == null) return null;
	check('minimum', minScore);
	const top = band >= 90 ? 100 : band + BAND_SIZE - 1;
	const label = scoreBandLabel(band);
	const out = (tone: ScoreTone, status: string, detail: string): ScoreBand => ({ band, label, tone, status, detail });
	const repair = fund === 'protection';

	if (top < minScore) {
		return out(
			'gifts',
			'Open for gifts',
			repair
				? `Under the fund's current minimum of ${minScore}, so the fund doesn't pay it by band and it relies on gifts.`
				: `Under the Home Fund's current minimum of ${minScore}, so it relies on gifts.`
		);
	}
	if (band < minScore) {
		return out(
			'near',
			'Near the minimum',
			repair
				? `The fund pays by band from ${minScore} up, which falls inside this band; a request under the current minimum relies on gifts.`
				: `The Home Fund's current minimum of ${minScore} falls inside this band; a request under it relies on gifts.`
		);
	}
	const formula = 'The Home Fund will choose by its needs formula, which isn’t live yet.';
	if (band >= 90) {
		return out('strong', 'Strong evidence', repair ? 'The top band, which the fund fills first.' : formula);
	}
	return out(
		'enough',
		'Enough evidence',
		repair ? `At or above the fund's minimum of ${minScore}.` : `At or above the Home Fund's minimum of ${minScore}. ${formula}`
	);
}
