// Property-based tests for the community-pool allocation. The example tests in
// allocation.test.ts pin specific cases; these generate thousands of random
// request boards and pools and check the money invariants hold for every one.
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { allocatePool, type FundingRequest } from './allocation';

/** A dollar amount with whole cents, as the app stores money. */
const dollars = (max: number) => fc.integer({ min: 0, max: max * 100 }).map((c) => c / 100);

const request = fc
	.record({
		amount: dollars(50_000),
		fundedShare: fc.double({ min: 0, max: 1.2, noNaN: true }),
		score: fc.integer({ min: 0, max: 100 })
	})
	.map(({ amount, fundedShare, score }) => ({
		amount,
		funded: Math.round(amount * fundedShare * 100) / 100,
		score
	}));

const board = fc
	.array(request, { maxLength: 30 })
	.map((rs): FundingRequest[] => rs.map((r, i) => ({ id: `r${i}`, ...r })));

const need = (r: FundingRequest) => Math.max(0, r.amount - r.funded);
const band = (score: number) => Math.floor(score / 10) * 10;
// Float sums of cent amounts can drift by far less than a cent.
const EPS = 1e-6;

describe('allocatePool properties', () => {
	it('never grants more than the pool, and accounts for every cent', () => {
		fc.assert(
			fc.property(board, dollars(200_000), (requests, pool) => {
				const { allocations, remainingPool } = allocatePool(requests, pool);
				const granted = allocations.reduce((s, a) => s + a.grant, 0);
				expect(granted).toBeLessThanOrEqual(pool + EPS);
				expect(remainingPool).toBeGreaterThanOrEqual(0);
				expect(granted + remainingPool).toBeLessThanOrEqual(pool + EPS);
			})
		);
	});

	it('never grants a negative amount or more than a request still needs', () => {
		fc.assert(
			fc.property(board, dollars(200_000), (requests, pool) => {
				const { allocations } = allocatePool(requests, pool);
				allocations.forEach((a, i) => {
					expect(a.grant).toBeGreaterThanOrEqual(0);
					expect(a.grant).toBeLessThanOrEqual(need(requests[i]) + EPS);
				});
			})
		);
	});

	it('pays nothing below the minimum score; those go to a person for review', () => {
		fc.assert(
			fc.property(board, dollars(200_000), (requests, pool) => {
				const { allocations } = allocatePool(requests, pool);
				allocations.forEach((a, i) => {
					if (requests[i].score < 70) {
						expect(a.grant).toBe(0);
						expect(a.status).toBe('needs-review');
					} else {
						expect(a.status).not.toBe('needs-review');
					}
				});
			})
		);
	});

	it('funds a lower band only once every higher band is fully funded', () => {
		fc.assert(
			fc.property(board, dollars(200_000), (requests, pool) => {
				const { allocations } = allocatePool(requests, pool);
				const eligible = requests
					.map((r, i) => ({ r, a: allocations[i] }))
					.filter(({ r }) => r.score >= 70 && need(r) > 0);
				for (const lower of eligible) {
					if (lower.a.grant === 0) continue;
					for (const higher of eligible) {
						if (band(higher.r.score) > band(lower.r.score)) {
							expect(higher.a.grant).toBeCloseTo(need(higher.r), 6);
						}
					}
				}
			})
		);
	});

	it('gives every request in a partly funded band the same share of its need', () => {
		fc.assert(
			fc.property(board, dollars(200_000), (requests, pool) => {
				const { allocations } = allocatePool(requests, pool);
				const byBand = new Map<number, { need: number; grant: number }[]>();
				requests.forEach((r, i) => {
					if (r.score < 70 || need(r) === 0) return;
					const list = byBand.get(band(r.score)) ?? [];
					list.push({ need: need(r), grant: allocations[i].grant });
					byBand.set(band(r.score), list);
				});
				for (const members of byBand.values()) {
					// No one in a band gets a worse share than the best-treated
					// member, beyond the cent lost to flooring their own grant.
					const best = Math.max(...members.map((m) => m.grant / m.need));
					for (const m of members) {
						expect(m.grant).toBeGreaterThanOrEqual(best * m.need - 0.01 - EPS);
					}
				}
			})
		);
	});
});
