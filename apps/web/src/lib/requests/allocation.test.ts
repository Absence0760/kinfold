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
	it('stacks insured cover before pledges', () => {
		// A 1,000.00 request the insurer covered 300.00 of needs only the gap.
		const a = byId(allocatePool([{ id: 'a', amount: 1000, score: 92, funded: 0, covered: 300 }], 900));
		expect(a.a).toEqual({ id: 'a', grant: 700, status: 'funded' });
	});

	it('fully covered requests need no grant', () => {
		const a = byId(allocatePool([{ id: 'a', amount: 1000, score: 92, funded: 0, covered: 1000 }], 900));
		expect(a.a).toEqual({ id: 'a', grant: 0, status: 'funded' });
	});

	const shareRule = { stepBps: 1000, capBps: 3000 };

	it('no paid requests in three years means no share: the pool grants the whole need', () => {
		const a = byId(allocatePool([{ id: 'a', amount: 1000, score: 92, funded: 0, paid3y: 0 }], 2000, { share: shareRule }));
		expect(a.a).toEqual({ id: 'a', grant: 1000, status: 'funded' });
	});

	it('one paid request moves a tenth of the need to the member\u2019s own share', () => {
		const a = byId(allocatePool([{ id: 'a', amount: 1000, score: 92, funded: 0, paid3y: 1 }], 2000, { share: shareRule }));
		expect(a.a.grant).toBe(900);
		expect(a.a.status).toBe('partial');
	});

	it('the share caps at three tenths whatever the count', () => {
		const a = byId(allocatePool([{ id: 'a', amount: 1000, score: 92, funded: 0, paid3y: 4 }], 2000, { share: shareRule }));
		expect(a.a.grant).toBe(700);
	});

	it('a bigger share still fills, never refuses: the claimant waits for no more', () => {
		// A share that leaves the band short of the pool means the request is
		// granted and partial - the member carries the rest themselves; nothing
		// about the rule answers "needs-review" or drops the row.
		const a = byId(allocatePool([{ id: 'a', amount: 1000, score: 92, funded: 0, paid3y: 9 }], 2000, { share: shareRule }));
		expect(a.a.grant).toBe(700);
		expect(a.a.status).toBe('partial');
	});
});
