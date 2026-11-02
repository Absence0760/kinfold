import { describe, expect, it } from 'vitest';
import { duesWord, incomeMethodWord, summarizeMembership, type MembershipSummary } from './membership.ts';

const duesRow = { id: 's1', monthly_cents: 4000, ends_on: null as string | null };
const paymentRow = { period: '2026-10-01', amount_cents: 4000, status: 'pending' };

describe('summarizeMembership', () => {
	it('a member with dues and a pending charge sees pending', () => {
		const summary = summarizeMembership([duesRow], [paymentRow], [], [], [], [], '2026-10-19');
		expect(summary.dues).toEqual({ monthlyCents: 4000, period: '2026-10-01', status: 'pending' });
		expect(summary.cover).toEqual({ vehicles: 0, claimsPaidCents: 0, openClaims: 0 });
		expect(summary.plan).toEqual([]);
	});

	it('a subscription with no ask yet reads not started, not a failure', () => {
		const summary = summarizeMembership([duesRow], [], [], [], [], [], '2026-11-02');
		expect(summary.dues.status).toBe('not started');
		expect(summary.dues.period).toBe('2026-11-01');
	});

	it('a $0 subscription has nothing to collect and shows no ask', () => {
		const zero = { ...duesRow, monthly_cents: 0 };
		const summary = summarizeMembership([zero], [paymentRow], [], [], [], [], '2026-10-19');
		expect(summary.dues.status).toBe('no dues to collect');
	});

	it('an ended subscription is not shown as current dues', () => {
		const ended = { ...duesRow, ends_on: '2026-09-01' };
		const summary: MembershipSummary = summarizeMembership([ended], [], [], [], [], [], '2026-10-19');
		expect(summary.dues.status).toBe('no dues yet');
	});

	it('the newest earnings check is shown, live until its expiry passes', () => {
		const income = [
			{ method: 'bank_link', monthly_income_cents: 400000, verified_at: '2025-03-01T00:00:00Z', expires_at: '2026-03-01T00:00:00Z' },
			{ method: 'tax_return', monthly_income_cents: 500000, verified_at: '2026-03-01T00:00:00Z', expires_at: '2027-03-01T00:00:00Z' }
		];
		const summary = summarizeMembership([], [], income, [], [], [], '2026-10-19');
		expect(summary.income.method).toBe('tax_return');
		expect(summary.income.monthlyIncomeCents).toBe(500000);
		expect(summary.income.live).toBe(true);
		expect(incomeMethodWord('tax_return')).toBe('from your tax return');
	});

	it('a check past its expiry is shown as not live', () => {
		const income = [{ method: 'bank_link', monthly_income_cents: 400000, verified_at: '2025-03-01T00:00:00Z', expires_at: '2026-03-01T00:00:00Z' }];
		const summary = summarizeMembership([], [], income, [], [], [], '2026-10-19');
		expect(summary.income.method).toBe('bank_link');
		expect(summary.income.live).toBe(false);
	});

	it('no earnings check yet is honest, not a zero income', () => {
		const summary = summarizeMembership([], [], [], [], [], [], '2026-10-19');
		expect(summary.income).toEqual({ method: null, monthlyIncomeCents: 0, verifiedAt: null, expiresAt: null, live: false });
	});

	it('cover counts premiums per vehicle and open claims separately', () => {
		const claims = [
			{ gross_cents: 40000, paid_cents: 39000, status: 'paid' },
			{ gross_cents: 20000, paid_cents: 19500, status: 'recorded' },
			{ gross_cents: 5000, paid_cents: 4500, status: 'denied' }
		];
		const assets = [{ kind: 'vehicle' }, { kind: 'vehicle' }];
		const summary = summarizeMembership([], [], [], claims, assets, [], '2026-10-19');
		expect(summary.cover).toEqual({ vehicles: 2, claimsPaidCents: 39000, openClaims: 1 });
	});

	it('the plan lists weights heaviest first and drops zeros', () => {
		const prefs = [
			{ target: 'car_damage' as never, weight_pct: 0 },
			{ target: 'home_help' as never, weight_pct: 70 },
			{ target: 'highest_score' as never, weight_pct: 30 }
		];
		const summary = summarizeMembership([], [], [], [], [], prefs, '2026-10-19');
		expect(summary.plan).toEqual([
			{ target: 'home_help', weightPct: 70 },
			{ target: 'highest_score', weightPct: 30 }
		]);
	});
});

describe('duesWord', () => {
	it('a captured charge reads as collected by the partner', () => {
		expect(duesWord('captured')).toBe('Collected by the payment partner');
	});
});
