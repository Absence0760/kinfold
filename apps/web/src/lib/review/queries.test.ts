import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { decideClaim, loadFraudSignals, loadStandingClaims } from './queries.ts';

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

const standing = {
	id: 'c1',
	request_id: 'r1',
	gross_cents: 40000,
	member_share_cents: 1000,
	paid_cents: 39000
};

describe('loadStandingClaims', () => {
	it('reads standing claims through the claims seam and keeps the figures', async () => {
		const { db, asked } = fakeDb({ claims: { data: [standing], error: null } });
		const claims = await loadStandingClaims(db);
		expect(asked).toEqual(['claims']);
		expect(claims).toEqual([standing]);
	});

	it('a refused read fails loudly rather than showing no claims', async () => {
		const { db } = fakeDb({ claims: { data: null, error: { message: 'permission denied for table claims' } } });
		await expect(loadStandingClaims(db)).rejects.toThrow(/permission denied/);
	});
});

describe('loadFraudSignals', () => {
	it('a reviewer’s read carries kind and severity only', async () => {
		const { db, asked } = fakeDb({
			review_fraud_signals: { data: [{ kind: 'duplicate_photos', severity: 'high', detail: { photo_sha256: 'deadbeef' } }], error: null }
		});
		const rows = await loadFraudSignals(db, ['r1']);
		expect(asked).toEqual(['review_fraud_signals']);
		expect(rows).toEqual([{ request_id: 'r1', kind: 'duplicate_photos', severity: 'high' }]);
		expect(JSON.stringify(rows)).not.toContain('deadbeef');
	});

	it('a request with no findings reads as an empty list', async () => {
		const { db, asked } = fakeDb({ review_fraud_signals: { data: [], error: null } });
		const rows = await loadFraudSignals(db, ['r1']);
		expect(asked).toEqual(['review_fraud_signals']);
		expect(rows).toEqual([]);
	});

	it('a console refusal reads as nothing shown, not a broken queue', async () => {
		const { db, asked } = fakeDb({
			review_fraud_signals: { data: null, error: { message: 'fraud signals are read by the operations console', code: '42501' } }
		});
		const rows = await loadFraudSignals(db, ['r1']);
		expect(asked).toEqual(['review_fraud_signals']);
		expect(rows).toEqual([]);
	});

	it('any other failure still reaches the console loudly', async () => {
		const { db } = fakeDb({ review_fraud_signals: { data: null, error: { message: 'permission denied for table fraud_signals', code: 'P0002' } } });
		await expect(loadFraudSignals(db, ['r1'])).rejects.toThrow(/permission denied/);
	});

	it('no requests means no reads', async () => {
		const { db, asked } = fakeDb({});
		const rows = await loadFraudSignals(db, []);
		expect(asked).toEqual([]);
		expect(rows).toEqual([]);
	});
});

describe('decideClaim', () => {
	it('one call carries the claim and the written reason', async () => {
		const { db, asked } = fakeDb({ decide_claim: { data: null, error: null } });
		await decideClaim(db, 'c1', 'The photos show parking damage.');
		expect(asked).toEqual(['decide_claim']);
	});

	it('the schema\u2019s refusal reaches the console', async () => {
		const { db } = fakeDb({
			decide_claim: { data: null, error: { message: 'claim not found, or already decided', code: 'P0002' } }
		});
		await expect(decideClaim(db, 'c1', 'again')).rejects.toThrow(/already decided/);
	});
});
