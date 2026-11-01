import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { requestStatusText } from '#lib/dashboard/labels.ts';
import { statusLabel } from '#lib/review/labels.ts';
import {
	bandOf,
	boardBand,
	minScoreFor,
	reviewSinceScore,
	scoreBand,
	scoreBandLabel,
	type PoolFund,
	type RequestStatus,
	type ReviewSinceScore,
	type ScoreBand
} from './score-band.ts';

// design.md §3: a low score "never means denied". No output may read as a refusal.
const REFUSAL = /\b(den(y|ied|ial)|fail(ed|s|ure)?|reject(ed|s|ion)?|refus(e|ed|al)|declin(e|ed)|ineligible|disqualif)/i;
const words = (b: ScoreBand) => `${b.label} ${b.status} ${b.detail}`;

const STATUSES: RequestStatus[] = [
	'draft', 'scoring', 'needs_evidence', 'in_review', 'open', 'funded', 'paid', 'refused', 'withdrawn', 'expired'
];
const FUNDS: PoolFund[] = ['protection', 'home_fund'];

const score = fc.integer({ min: 0, max: 100 });
const minimum = fc.option(score, { nil: null });
const reviewed = fc.constantFrom<ReviewSinceScore | undefined>('approved', 'other', 'none', undefined);
const status = fc.constantFrom(...STATUSES);
const band = fc.integer({ min: 0, max: 9 }).map((n) => n * 10);
const fund = fc.constantFrom(...FUNDS);

const NEEDS = 'Needs more evidence';

describe('scoreBand', () => {
	it('words a fresh score against the fund minimum before any review', () => {
		const ctx = (status: RequestStatus) => ({ status, minScore: 70, review: 'none' as const });
		expect(scoreBand(95, ctx('open'))).toMatchObject({ band: 90, label: '90 to 100', tone: 'strong', status: 'Strong evidence' });
		expect(scoreBand(84, ctx('open'))).toMatchObject({ label: '80 to 89', tone: 'enough', status: 'Enough evidence' });
		expect(scoreBand(70, ctx('funded'))?.detail).toBe("At or above the fund's minimum of 70.");
		expect(scoreBand(42, ctx('needs_evidence'))).toMatchObject({ label: '40 to 49', tone: 'needs-evidence', status: NEEDS });
		expect(scoreBand(42, ctx('needs_evidence'))?.detail).toBe(
			"Below the fund's minimum of 70, so a trained member reviewer looks at it. More evidence can raise the score."
		);
	});

	it("never compares with today's minimum once a person has decided", () => {
		// A reviewer approved a 55: not "below the minimum", not warm.
		expect(scoreBand(55, { status: 'open', minScore: 70, review: 'approved' })).toMatchObject({
			tone: 'accepted',
			status: 'Evidence accepted',
			detail: 'A member reviewer approved it.'
		});
		// A reviewer asked for more evidence on an 85: no minimum in the wording.
		const asked = scoreBand(85, { status: 'needs_evidence', minScore: 70, review: 'approved' });
		expect(asked).toMatchObject({ status: NEEDS });
		expect(asked?.detail).not.toMatch(/minimum/);
		expect(scoreBand(30, { status: 'refused', minScore: 70, review: 'approved' })).toMatchObject({
			tone: 'decided',
			status: 'A person decided'
		});
	});

	it('falls back to the status alone when the minimum disagrees with it (it changed since)', () => {
		// Scored 65 under a minimum of 60, which has since risen to 70.
		expect(scoreBand(65, { status: 'open', minScore: 70, review: 'none' })?.tone).toBe('accepted');
		// Sent for evidence under 70, which has since dropped to 60.
		expect(scoreBand(65, { status: 'needs_evidence', minScore: 60, review: 'none' })?.detail).not.toMatch(/minimum/);
	});

	it('has nothing to say for a draft, a rescore, a withdrawal or an expiry', () => {
		for (const s of ['draft', 'scoring', 'withdrawn', 'expired'] as const) {
			expect(scoreBand(80, { status: s, minScore: 70, review: 'none' })).toBeNull();
		}
	});

	it('rejects input the database would never hold', () => {
		for (const bad of [-1, 101, 70.5, Number.NaN]) expect(() => scoreBand(bad, { status: 'open', minScore: 70 })).toThrow(RangeError);
		expect(() => scoreBand(80, { status: 'open', minScore: 120 })).toThrow(RangeError);
	});

	it('properties: status × score never contradicts the request status label', () => {
		fc.assert(
			fc.property(status, score, minimum, reviewed, (st, s, min, rev) => {
				const b = scoreBand(s, { status: st, minScore: min, review: rev });
				const member = requestStatusText(st, 'car_damage', 'pool').label;
				const reviewer = statusLabel(st);
				if (['draft', 'scoring', 'withdrawn', 'expired'].includes(st)) {
					expect(b).toBeNull();
					return;
				}
				expect(b).not.toBeNull();
				const out = b as ScoreBand;
				// "Needs more evidence" and the warm tone appear exactly when both labels say so.
				expect(out.status === NEEDS).toBe(member === NEEDS && reviewer === NEEDS);
				expect(out.tone === 'needs-evidence').toBe(st === 'needs_evidence');
				if (['open', 'funded', 'paid'].includes(st)) {
					expect(['Strong evidence', 'Enough evidence', 'Evidence accepted']).toContain(out.status);
				}
				if (st === 'refused') expect(words(out)).not.toMatch(/accepted|approved|strong|enough/i);
				if (st === 'in_review') expect(out.status).toBe('With a reviewer');
				// A minimum is named only before any review, and only when it agrees with the status.
				const named = /minimum of (\d+)/.exec(out.detail);
				if (named) {
					expect(rev).toBe('none');
					expect(Number(named[1])).toBe(min);
					expect(st === 'needs_evidence' ? s < (min as number) : s >= (min as number)).toBe(true);
				}
			})
		);
	});

	it('properties: the band holds the score and is a 10-point step', () => {
		fc.assert(
			fc.property(score, (s) => {
				const b = scoreBand(s, { status: 'open', minScore: null }) as ScoreBand;
				expect(b.band % 10).toBe(0);
				expect(s).toBeGreaterThanOrEqual(b.band);
				expect(s).toBeLessThanOrEqual(b.band >= 90 ? 100 : b.band + 9);
				expect(b.label).toBe(scoreBandLabel(bandOf(s)));
			})
		);
	});

	it('properties: never words a score as a refusal, and needing evidence names the reviewer', () => {
		fc.assert(
			fc.property(status, score, minimum, reviewed, (st, s, min, rev) => {
				const b = scoreBand(s, { status: st, minScore: min, review: rev });
				if (!b) return;
				expect(words(b)).not.toMatch(REFUSAL);
				if (b.status === NEEDS) expect(b.detail).toMatch(/member reviewer/);
			})
		);
	});
});

describe('boardBand', () => {
	it('words repair fund bands, band payment and all', () => {
		expect(boardBand(90, 'protection', 70)).toMatchObject({ label: '90 to 100', tone: 'strong', detail: 'The top band, which the fund fills first.' });
		expect(boardBand(70, 'protection', 70)).toMatchObject({ label: '70 to 79', tone: 'enough' });
		expect(boardBand(60, 'protection', 70)).toMatchObject({
			tone: 'gifts',
			status: 'Open for gifts',
			detail: "Under the fund's current minimum of 70, so the fund doesn't pay it by band and it relies on gifts."
		});
		expect(boardBand(70, 'protection', 75)).toMatchObject({ tone: 'near', status: 'Near the minimum' });
		expect(boardBand(70, 'protection', 80)?.tone).toBe('gifts');
		expect(boardBand(90, 'protection', 100)?.tone).toBe('near');
	});

	it('makes no band claim for the Home Fund', () => {
		expect(boardBand(90, 'home_fund', 70)?.detail).toBe('The Home Fund will choose by its needs formula, which isn’t live yet.');
		expect(boardBand(80, 'home_fund', 70)?.detail).toMatch(/isn’t live yet/);
	});

	it('leaves the status out when the minimum is unknown', () => {
		expect(boardBand(80, 'protection', null)).toBeNull();
	});

	it('rejects a value that is not a band', () => {
		expect(() => boardBand(85, 'protection', 70)).toThrow(RangeError);
		expect(() => boardBand(110, 'protection', 70)).toThrow(RangeError);
	});

	it('properties: never says a board request needs evidence, never warm, never a refusal', () => {
		fc.assert(
			fc.property(band, fund, score, (b, f, min) => {
				const out = boardBand(b, f, min) as ScoreBand;
				expect(out.tone).not.toBe('needs-evidence');
				expect(words(out)).not.toMatch(/needs more evidence/i);
				expect(words(out)).not.toMatch(REFUSAL);
			})
		);
	});

	it('properties: only the repair fund is said to pay by band', () => {
		fc.assert(
			fc.property(band, score, (b, min) => {
				expect(words(boardBand(b, 'home_fund', min) as ScoreBand)).not.toMatch(/by band|fills first/i);
			})
		);
	});

	it('properties: "near" exactly when the minimum splits the band; "approved" exactly when the band is under it', () => {
		fc.assert(
			fc.property(band, fund, score, (b, f, min) => {
				const out = boardBand(b, f, min) as ScoreBand;
				const top = b >= 90 ? 100 : b + 9;
				expect(out.tone === 'near').toBe(min > b && min <= top);
				expect(out.tone === 'gifts').toBe(top < min);
			})
		);
	});
});

describe('minScoreFor', () => {
	const settings = [
		{ fund: 'protection', min_score: 75 },
		{ fund: 'home_fund', min_score: 65 }
	];

	it("reads the fund's minimum, and never guesses one", () => {
		expect(minScoreFor(settings, 'protection')).toBe(75);
		expect(minScoreFor(settings, 'home_fund')).toBe(65);
		expect(minScoreFor([], 'protection')).toBeNull();
		expect(minScoreFor(null, 'protection')).toBeNull();
		expect(minScoreFor(undefined, 'home_fund')).toBeNull();
	});
});

describe('reviewSinceScore', () => {
	const scored = '2026-10-20T12:00:00Z';
	it('counts only reviews after the current score', () => {
		expect(reviewSinceScore([], scored)).toBe('none');
		// Asked for more evidence, resubmitted, rescored and opened: no person approved it.
		expect(reviewSinceScore([{ decision: 'needs_evidence', created_at: '2026-10-18T09:00:00Z' }], scored)).toBe('none');
		expect(reviewSinceScore([{ decision: 'approve', created_at: '2026-10-21T09:00:00Z' }], scored)).toBe('approved');
	});

	it('uses the latest review since the score', () => {
		const reviews = [
			{ decision: 'approve', created_at: '2026-10-21T09:00:00Z' },
			{ decision: 'escalate', created_at: '2026-10-22T09:00:00Z' }
		];
		expect(reviewSinceScore(reviews, scored)).toBe('other');
	});

	it('a rescore after a needs-evidence review never claims a reviewer approved it', () => {
		const review = reviewSinceScore([{ decision: 'needs_evidence', created_at: '2026-10-18T09:00:00Z' }], scored);
		expect(scoreBand(75, { status: 'open', minScore: 80, review })?.detail).not.toBe('A member reviewer approved it.');
	});
});

describe('boardBand never claims a reviewer decided', () => {
	it('properties: no board wording mentions approval or a reviewer', () => {
		fc.assert(
			fc.property(
				fc.integer({ min: 0, max: 9 }).map((b) => b * 10),
				fc.constantFrom<PoolFund>('protection', 'home_fund'),
				fc.integer({ min: 0, max: 100 }),
				(band, fund, min) => {
					const b = boardBand(band, fund, min);
					if (b) expect(`${b.status} ${b.detail}`).not.toMatch(/approved|reviewer/i);
				}
			)
		);
	});
});
