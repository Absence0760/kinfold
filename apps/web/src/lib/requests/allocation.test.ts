import { describe, expect, it } from 'vitest';
import { allocatePool, type FundingRequest } from './allocation';

const req = (id: string, amount: number, score: number, funded = 0): FundingRequest => ({
	id,
	amount,
	score,
	funded
});

const byId = (result: ReturnType<typeof allocatePool>) =>
	Object.fromEntries(result.allocations.map((a) => [a.id, a]));

describe('allocatePool', () => {
	it('fills every request in the top band before the next band', () => {
		const result = allocatePool([req('a', 1000, 95), req('b', 500, 91), req('c', 400, 85)], 1700);
		const a = byId(result);
		expect(a.a).toEqual({ id: 'a', grant: 1000, status: 'funded' });
		expect(a.b).toEqual({ id: 'b', grant: 500, status: 'funded' });
		expect(a.c).toEqual({ id: 'c', grant: 200, status: 'partial' });
		expect(result.remainingPool).toBe(0);
	});

	it('splits a short pool evenly by need within a band', () => {
		const a = byId(allocatePool([req('a', 1000, 99), req('b', 3000, 90)], 2000));
		expect(a.a.grant).toBe(500);
		expect(a.b.grant).toBe(1500);
		expect(a.a.status).toBe('partial');
	});

	it('never pays requests below the minimum score', () => {
		const result = allocatePool([req('low', 100, 69)], 10_000);
		expect(byId(result).low).toEqual({ id: 'low', grant: 0, status: 'needs-review' });
		expect(result.remainingPool).toBe(10_000);
	});

	it('counts money already raised from family and friends', () => {
		const a = byId(allocatePool([req('a', 1000, 95, 800)], 5000));
		expect(a.a).toEqual({ id: 'a', grant: 200, status: 'funded' });
	});

	it('leaves lower bands waiting when the pool runs out', () => {
		const a = byId(allocatePool([req('a', 1000, 95), req('b', 1000, 75)], 1000));
		expect(a.b).toEqual({ id: 'b', grant: 0, status: 'waiting' });
	});

	it('never grants more than the pool holds', () => {
		const requests = [req('a', 333.33, 92), req('b', 333.33, 94), req('c', 333.34, 97)];
		const result = allocatePool(requests, 100);
		const total = result.allocations.reduce((s, x) => s + x.grant, 0);
		expect(total).toBeLessThanOrEqual(100);
	});

	it('treats a negative pool as empty', () => {
		expect(byId(allocatePool([req('a', 10, 99)], -5)).a.status).toBe('waiting');
	});
});
