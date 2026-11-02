import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { appealClaim, claimStatusText } from './claims.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'or', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		return chain;
	};
	const db = { from: query, rpc: query } as unknown as Db;
	return { db, asked };
}

const recorded = { id: 'c1', request_id: 'r1', partner_ref: 'pc_p1', gross_cents: 40000, member_share_cents: 1000, paid_cents: 39000, status: 'recorded', reason: null };
const denied = { ...recorded, id: 'c2', partner_ref: 'pc_p2', status: 'denied', reason: 'Parking damage, not a collision.' };

describe('claimStatusText', () => {
	it('names each claim outcome, including denials', () => {
		expect(claimStatusText('paid')).toBe('Paid in full to the shop');
		expect(claimStatusText('recorded')).toBe('Recorded, payment not confirmed yet');
		expect(claimStatusText('denied')).toBe('Denied by a person');
	});
});

describe('appealClaim', () => {
	it('a short reason is refused before any call', async () => {
		const { db, asked } = fakeDb({});
		const out = await appealClaim(db, 'c2', 'nope');
		expect(out).toEqual({ appealed: false, message: 'An appeal needs a reason of at least 10 characters.' });
		expect(asked).toEqual([]);
	});

	it('the schema decides the rest, and its reason is shown', async () => {
		const { db, asked } = fakeDb({ appeal_claim: { data: null, error: { message: 'claim not found or not denied', code: 'P0002' } } });
		const out = await appealClaim(db, 'c2', 'The photos show the collision clearly.');
		expect(out.appealed).toBe(false);
		expect(out.message).toBe('claim not found or not denied');
		expect(asked).toEqual(['appeal_claim']);
	});

	it('a denied claim with a real reason appeals', async () => {
		const { db, asked } = fakeDb({ appeal_claim: { data: null, error: null } });
		const out = await appealClaim(db, 'c2', 'The photos show the collision clearly.');
		expect(out.appealed).toBe(true);
		expect(asked).toEqual(['appeal_claim']);
	});
});
