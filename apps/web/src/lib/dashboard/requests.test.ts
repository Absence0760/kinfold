import { describe, expect, it } from 'vitest';
import {
	buildRequestCards,
	latestScores,
	parseReasons,
	raisedByRequest,
	showsRaised,
	type ContributionRow,
	type RequestRow,
	type ScoreRow
} from './requests.ts';

const score = (request_id: string, value: number, created_at: string, reasons: ScoreRow['reasons'] = []): ScoreRow => ({
	request_id,
	score: value,
	reasons,
	model: 'dev-scorer',
	model_version: '0.0.1',
	created_at
});

const request = (id: string, status: RequestRow['status'], created_at: string): RequestRow => ({
	id,
	title: id,
	kind: 'car_damage',
	status,
	funding: 'people',
	amount_cents: 100000,
	created_at
});

describe('parseReasons', () => {
	it('keeps the scorer’s strings', () => {
		expect(parseReasons(['hail pattern consistent', 'no insurer letter yet'])).toEqual([
			'hail pattern consistent',
			'no insurer letter yet'
		]);
	});

	it('reads {reason} or {text} objects and drops anything else', () => {
		expect(parseReasons([{ reason: 'a' }, { text: 'b' }, 3, null, '  ', { other: 'x' }, ['nested']])).toEqual(['a', 'b']);
	});

	it('returns nothing for a non-array', () => {
		expect(parseReasons(null)).toEqual([]);
		expect(parseReasons('one reason')).toEqual([]);
		expect(parseReasons({ reason: 'x' })).toEqual([]);
	});
});

describe('latestScores', () => {
	it('keeps the newest score per request, whatever the row order', () => {
		const m = latestScores([
			score('r1', 60, '2026-10-01T00:00:00Z', ['old']),
			score('r1', 80, '2026-10-02T00:00:00Z', ['new']),
			score('r1', 70, '2026-09-30T00:00:00Z'),
			score('r2', 90, '2026-10-01T00:00:00Z')
		]);
		expect(m.get('r1')).toMatchObject({ score: 80, reasons: ['new'], modelVersion: '0.0.1' });
		expect(m.get('r2')?.score).toBe(90);
	});
});

describe('raisedByRequest', () => {
	it('counts pledged and captured money, not released or refunded', () => {
		const rows: ContributionRow[] = [
			{ request_id: 'r1', source: 'gift', amount_cents: 30000, status: 'pledged' },
			{ request_id: 'r1', source: 'loan', amount_cents: 70000, status: 'captured' },
			{ request_id: 'r1', source: 'gift', amount_cents: 5000, status: 'released' },
			{ request_id: 'r2', source: 'pool', amount_cents: 72000, status: 'refunded' }
		];
		const m = raisedByRequest(rows);
		expect(m.get('r1')).toBe(100000);
		expect(m.has('r2')).toBe(false);
	});
});

describe('buildRequestCards', () => {
	it('puts requests needing the member first, then live, then finished; newest first within', () => {
		const cards = buildRequestCards(
			[
				request('paid', 'paid', '2026-10-05T00:00:00Z'),
				request('open-old', 'open', '2026-09-01T00:00:00Z'),
				request('draft', 'draft', '2026-08-01T00:00:00Z'),
				request('withdrawn', 'withdrawn', '2026-10-30T00:00:00Z'),
				request('open-new', 'open', '2026-10-01T00:00:00Z')
			],
			[score('open-new', 86, '2026-10-02T00:00:00Z')],
			[{ request_id: 'open-new', source: 'gift', amount_cents: 1000, status: 'pledged' }]
		);
		expect(cards.map((c) => c.id)).toEqual(['draft', 'open-new', 'open-old', 'paid', 'withdrawn']);
		expect(cards[1]).toMatchObject({ raisedCents: 1000, score: { score: 86 } });
		expect(cards[0]).toMatchObject({ raisedCents: 0, score: null });
	});
});

describe('showsRaised', () => {
	it('shows progress once a request can take money, or once money came in', () => {
		expect(showsRaised({ status: 'draft', raisedCents: 0 })).toBe(false);
		expect(showsRaised({ status: 'needs_evidence', raisedCents: 0 })).toBe(false);
		expect(showsRaised({ status: 'open', raisedCents: 0 })).toBe(true);
		expect(showsRaised({ status: 'in_review', raisedCents: 500 })).toBe(true);
	});
});
