import { describe, expect, it } from 'vitest';
import { addDays, poolProblems, poolRulesText, type FundSettings, type PoolCheck, type PoolContext } from './eligibility';

const protection: FundSettings = {
	fund: 'protection',
	kinds: ['car_damage', 'car_deductible'],
	max_request_cents: 1_000_000,
	waiting_days: 60,
	min_score: 70
};
const homeFund: FundSettings = {
	fund: 'home_fund',
	kinds: ['home_repair'],
	max_request_cents: 5_000_000,
	waiting_days: 90,
	min_score: 70
};
const car = {
	id: 'car-1',
	kind: 'vehicle' as const,
	description: '2016 Honda Fit',
	registered_on: '2025-01-01',
	removed_on: null
};
const ctx: PoolContext = { settings: protection, coverageStartedOn: '2026-01-01', assets: [car] };
const req: PoolCheck = {
	kind: 'car_damage',
	funding: 'pool',
	amountCents: 185_000,
	incidentOn: '2026-10-20',
	assetId: 'car-1'
};

describe('addDays', () => {
	it('adds calendar days across months and leap years', () => {
		expect(addDays('2026-01-31', 1)).toBe('2026-02-01');
		expect(addDays('2024-02-28', 1)).toBe('2024-02-29');
		expect(addDays('2026-01-01', 60)).toBe('2026-03-02');
	});
});

describe('poolProblems (mirrors submit_request)', () => {
	it('is empty for an eligible pool request', () => {
		expect(poolProblems(req, ctx)).toEqual([]);
	});

	it('ignores requests only family and friends fund', () => {
		expect(poolProblems({ ...req, funding: 'people', assetId: null }, ctx)).toEqual([]);
	});

	it('says when the pool does not cover the kind yet, and stops there', () => {
		const out = poolProblems({ ...req, kind: 'loan_payoff', assetId: null }, { ...ctx, settings: homeFund });
		expect(out).toHaveLength(1);
		expect(out[0]).toMatch(/Home Fund doesn’t cover loan payoff requests/);
	});

	it('names the cap', () => {
		expect(poolProblems({ ...req, amountCents: 1_000_001 }, ctx).join()).toMatch(/at most \$10,000/);
		expect(poolProblems({ ...req, amountCents: 1_000_000 }, ctx)).toEqual([]);
	});

	it('applies the waiting period after the first dues payment, inclusive', () => {
		expect(poolProblems({ ...req, incidentOn: '2026-03-01' }, ctx).join()).toMatch(/from Mar 2, 2026/);
		expect(poolProblems({ ...req, incidentOn: '2026-03-02' }, ctx)).toEqual([]);
		expect(poolProblems(req, { ...ctx, coverageStartedOn: null }).join()).toMatch(/hasn’t started/);
	});

	it('needs a registered car for the repair fund, registered long enough before', () => {
		expect(poolProblems({ ...req, assetId: null }, ctx).join()).toMatch(/Choose the car/);
		expect(poolProblems(req, { ...ctx, assets: [{ ...car, removed_on: '2026-05-01' }] }).join()).toMatch(
			/Choose the car/
		);
		const late = poolProblems(req, { ...ctx, assets: [{ ...car, registered_on: '2026-10-01' }] });
		expect(late.join()).toMatch(/2016 Honda Fit was registered with Kinfold on Oct 1, 2026/);
	});

	it('does not ask for a car on Home Fund requests', () => {
		expect(
			poolProblems(
				{ ...req, kind: 'home_repair', funding: 'both', assetId: null },
				{ ...ctx, settings: homeFund, coverageStartedOn: '2025-01-01' }
			)
		).toEqual([]);
	});

	it('says nothing until the settings have loaded', () => {
		expect(poolProblems(req, { ...ctx, settings: null })).toEqual([]);
	});
});

describe('poolRulesText', () => {
	it('states the cap, the waiting period and the board', () => {
		const t = poolRulesText('car_damage', protection);
		expect(t).toMatch(/\$10,000 per request/);
		expect(t).toMatch(/60 days/);
		expect(t).toMatch(/car registered/);
		expect(t).toMatch(/members-only board/);
		expect(poolRulesText('home_repair', homeFund)).not.toMatch(/car/);
	});
});
