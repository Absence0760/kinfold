import { describe, expect, it } from 'vitest';
import {
	appealOutcome,
	buildAppeals,
	buildQueue,
	latestScores,
	reviewOutcome,
	scoreReasons,
	needsOutcome,
	type AppealRow,
	type EvidenceRow,
	type QueueRequestRow,
	type ReviewRow,
	type NeedsRow,
	type NeedsReviewRow,
	type ScoreRow
} from './queue';

const ME = 'reviewer-1';

function request(id: string, over: Partial<QueueRequestRow> = {}): QueueRequestRow {
	return {
		id,
		kind: 'car_damage',
		status: 'in_review',
		amount_cents: 185000,
		public_summary: 'Rear bumper after being rear-ended.',
		current_score: 60,
		incident_on: '2026-10-20',
		submitted_at: '2026-10-21T10:00:00Z',
		...over
	};
}

function score(request_id: string, value: number, created_at: string, reasons: unknown = ['ok']): ScoreRow {
	return { request_id, score: value, reasons, model_version: '0.0.1', created_at };
}

function review(request_id: string, over: Partial<ReviewRow> = {}): ReviewRow {
	return {
		request_id,
		decision: 'escalate',
		reason: 'Second look please.',
		created_at: '2026-10-22T10:00:00Z',
		...over
	};
}

describe('scoreReasons', () => {
	it('reads an array of strings, trimmed, without blanks', () => {
		expect(scoreReasons([' photos match ', '', 'estimate dated'])).toEqual(['photos match', 'estimate dated']);
	});

	it('reads text from object entries so a richer format still explains itself', () => {
		expect(scoreReasons([{ text: 'a' }, { reason: 'b' }, { label: 'c' }, { other: 1 }])).toEqual([
			'a',
			'b',
			'c'
		]);
	});

	it('returns nothing for a non-array', () => {
		expect(scoreReasons(null)).toEqual([]);
		expect(scoreReasons('photos match')).toEqual([]);
	});
});

describe('latestScores', () => {
	it('keeps the most recent score per request, whatever the row order', () => {
		const m = latestScores([
			score('a', 90, '2026-10-22T00:00:00Z'),
			score('a', 55, '2026-10-21T00:00:00Z'),
			score('b', 70, '2026-10-21T00:00:00Z')
		]);
		expect(m.get('a')?.score).toBe(90);
		expect(m.get('b')?.score).toBe(70);
	});
});

describe('buildQueue', () => {

	it('the checks\u2019 findings ride along in kind and severity only', () => {
		const items = buildQueue(
			[request('flagged', { status: 'in_review', submitted_at: '2026-10-01T00:00:00Z' })],
			[],
			[],
			[],
			[],
			[],
			[
				{ request_id: 'flagged', kind: 'duplicate_photos', severity: 'high' },
				{ request_id: 'flagged', kind: 'cross_shop', severity: 'low' }
			]
		);
		expect(items[0].findings).toEqual([
			{ kind: 'duplicate_photos', severity: 'high' },
			{ kind: 'cross_shop', severity: 'low' }
		]);
		expect(JSON.stringify(items[0].findings)).not.toContain('request_id');
	});

	it('puts actionable requests first, then oldest submission first', () => {
		const items = buildQueue(
			[
				request('refused', { status: 'refused', submitted_at: '2026-10-01T00:00:00Z' }),
				request('newer', { submitted_at: '2026-10-25T00:00:00Z' }),
				request('evidence', { status: 'needs_evidence', submitted_at: '2026-10-02T00:00:00Z' }),
				request('older', { submitted_at: '2026-10-20T00:00:00Z' })
			],
			[],
			[],
			[]
		);
		expect(items.map((i) => i.request.id)).toEqual(['older', 'newer', 'evidence', 'refused']);
	});

	it('attaches each request its own score, evidence and my reviews', () => {
		const evidence: EvidenceRow[] = [
			{ id: 'e2', request_id: 'a', kind: 'estimate', redaction_status: 'confirmed', captured_in_app: false, created_at: '2026-10-21T02:00:00Z' },
			{ id: 'e1', request_id: 'a', kind: 'photo', redaction_status: 'confirmed', captured_in_app: true, created_at: '2026-10-21T01:00:00Z' },
			{ id: 'e3', request_id: 'b', kind: 'photo', redaction_status: 'pending', captured_in_app: true, created_at: '2026-10-21T01:00:00Z' }
		];
		const [a, b] = buildQueue(
			[request('a', { submitted_at: '2026-10-01T00:00:00Z' }), request('b')],
			[score('a', 64, '2026-10-21T00:00:00Z', ['estimate missing a date'])],
			evidence,
			[review('a')]
		);
		expect(a.score).toEqual({ score: 64, reasons: ['estimate missing a date'], modelVersion: '0.0.1', at: '2026-10-21T00:00:00Z' });
		expect(a.evidence.map((e) => e.id)).toEqual(['e1', 'e2']);
		expect(a.myReviews).toHaveLength(1);
		expect(b.score).toBe(null);
		expect(b.evidence.map((e) => e.id)).toEqual(['e3']);
		expect(b.myReviews).toEqual([]);
	});
});

describe('buildAppeals', () => {
	const appeal: AppealRow = {
		id: 'ap1',
		request_id: 'a',
		reason: 'The shop re-did the estimate.',
		status: 'open',
		created_at: '2026-10-25T00:00:00Z'
	};

	it('finds the refusal being appealed: the latest refuse review before the appeal', () => {
		const [item] = buildAppeals(
			[appeal],
			[
				review('a', { decision: 'refuse', reason: 'first refusal', created_at: '2026-10-10T00:00:00Z', reviewer_id: 'r1' }),
				review('a', { decision: 'refuse', reason: 'second refusal', created_at: '2026-10-20T00:00:00Z', reviewer_id: 'r2' }),
				review('a', { decision: 'refuse', reason: 'after the appeal', created_at: '2026-10-26T00:00:00Z', reviewer_id: 'r3' })
			],
			[],
			[],
			ME
		);
		expect(item.refusal?.reason).toBe('second refusal');
		expect(item.request).toBe(null);
		expect(item.score).toBe(null);
	});

	it('never passes on who reviewed, but knows when the viewer did', () => {
		const reviews = [
			review('a', { decision: 'refuse', created_at: '2026-10-20T00:00:00Z', reviewer_id: ME })
		];
		const [item] = buildAppeals([appeal], reviews, [], [], ME);
		expect(item.viewerReviewed).toBe(true);
		expect(item.history.every((h) => !('reviewer_id' in h))).toBe(true);

		const [other] = buildAppeals([appeal], reviews, [], [], 'someone-else');
		expect(other.viewerReviewed).toBe(false);
	});

	it('shows the request and score when RLS returned them', () => {
		const [item] = buildAppeals([appeal], [], [request('a')], [score('a', 40, '2026-10-01T00:00:00Z')], ME);
		expect(item.request?.id).toBe('a');
		expect(item.score?.score).toBe(40);
		expect(item.refusal).toBe(null);
	});
});

describe('reviewOutcome', () => {
	it('confirms each outcome from the status the database returned', () => {
		expect(reviewOutcome('approve', 'open')).toBe('Approved. The request is open for funding.');
		expect(reviewOutcome('approve', 'funded')).toMatch(/back to funded/);
		expect(reviewOutcome('needs_evidence', 'needs_evidence')).toMatch(/asked for more/);
		expect(reviewOutcome('refuse', 'refused')).toMatch(/can appeal/);
		expect(reviewOutcome('escalate', 'in_review')).toBe('Escalated. The request is now “In review”.');
	});

	it('says when a refusal is held because money already reached the payee', () => {
		expect(reviewOutcome('refuse', 'in_review')).toMatch(/Money has already reached the payee/);
	});
});

describe('appealOutcome', () => {
	it('says what each panel decision does', () => {
		expect(appealOutcome(true)).toMatch(/back in review/);
		expect(appealOutcome(false)).toMatch(/refusal stands/);
	});
});

describe('needs ranking and answers', () => {
	it('keeps the newest formula version when ranking a request', () => {
		const items = buildQueue(
			[request('a', { kind: 'home_repair' })],
			[],
			[],
			[],
			[
				{ request_id: 'a', score: 55, formula_version: 1 },
				{ request_id: 'a', score: 72, formula_version: 2 }
			]
		);
		expect(items[0].needs).toEqual({ score: 72, formulaVersion: 2 });
	});

	it('attaches needs answers oldest first, without authors', () => {
		const items = buildQueue(
			[request('a', { kind: 'home_repair' })],
			[],
			[],
			[],
			[{ request_id: 'a', score: 72, formula_version: 2 }],
			[
				{
					request_id: 'a',
					formula_version: 2,
					decision: 'needs',
					reason: 'The street floods every storm.',
					created_at: '2026-11-02T03:00:00Z'
				},
				{
					request_id: 'a',
					formula_version: 1,
					decision: 'not_needs',
					reason: 'Public grants cover this one.',
					created_at: '2026-11-01T03:00:00Z'
				}
			]
		);
		expect(items[0].needsReviews.map((r) => r.at)).toEqual(
			['2026-11-01T03:00:00Z', '2026-11-02T03:00:00Z']
		);
	});

	it('says the published ranking never changed', () => {
		expect(needsOutcome('needs')).toMatch(/published ranking stays as it is/);
		expect(needsOutcome('not_needs')).toMatch(/published ranking stays as it is/);
	});
});
