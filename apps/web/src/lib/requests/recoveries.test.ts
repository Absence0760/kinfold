import { describe, expect, it } from 'vitest';
import { formatCents } from '#lib/dashboard/format.ts';
import type { Db } from '#lib/supabase/client.ts';
import { recordRecovery, recoveryLabel, recoveryText, recoveryTotalCents } from './recoveries.ts';

describe('recoveryLabel', () => {
	it('names each source in plain words', () => {
		expect(recoveryLabel('own_cover')).toBe('your own deductible cover');
		expect(recoveryLabel('insurance')).toBe('another insurer\u2019s claim');
		expect(recoveryLabel('fema')).toBe('a federal disaster programme');
	});

	it('an unknown source is shown, not swallowed', () => {
		expect(recoveryLabel('whatever')).toBe('whatever');
	});
});

describe('recoveryText', () => {
	it('an unconfirmed record says so', () => {
		const row = { request_id: 'r1', source: 'insurance', amount_cents: 40000, recovered_on: '2026-09-04', note: null, verified_at: null, recorded_at: '2026-10-01T00:00:00Z' };
		expect(recoveryText(row)).toBe('$400 as another insurer\u2019s claim on 2026-09-04 · not confirmed yet');
	});

	it('a confirmed record with a note reads as one line', () => {
		const row = { request_id: 'r1', source: 'own_cover', amount_cents: 100000, recovered_on: '2026-08-01', note: 'The insurer paid it', verified_at: '2026-08-02T00:00:00Z', recorded_at: '2026-08-01T00:00:00Z' };
		expect(recoveryText(row)).toBe('$1,000 as your own deductible cover on 2026-08-01 · the partner confirmed it · The insurer paid it');
	});
});

describe('recoveryTotalCents', () => {
	it('sums every record', () => {
		const rows = [
			{ request_id: 'r1', source: 'insurance', amount_cents: 40000, recovered_on: '2026-09-04', note: null, verified_at: null, recorded_at: '2026-10-01T00:00:00Z' },
			{ request_id: 'r1', source: 'own_cover', amount_cents: 100000, recovered_on: '2026-08-01', note: null, verified_at: '2026-08-02T00:00:00Z', recorded_at: '2026-08-01T00:00:00Z' }
		];
		expect(recoveryTotalCents(rows)).toBe(140000);
	});

	it('nothing recorded is no money, not a failure', () => {
		expect(recoveryTotalCents([])).toBe(0);
		expect(formatCents(0)).toBe('$0');
	});
});


type Fixture = { data: unknown; error: { message: string; code?: string } | null };

function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'where', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		return chain;
	};
	const db = { from: query, rpc: query } as unknown as Db;
	return { db, asked };
}

describe('recordRecovery', () => {
	it('one call carries the claim and the written reason', async () => {
		const { db, asked } = fakeDb({ record_recovery: { data: null, error: null } });
		await recordRecovery(db, 'r1', 'insurance', 40000, '2026-09-04', null);
		expect(asked).toEqual(['record_recovery']);
	});

	it('the schema’s refusal reaches the console', async () => {
		const { db } = fakeDb({
			record_recovery: { data: null, error: { message: 'money for the same damage is recorded by the requester or the service', code: '42501' } }
		});
		await expect(recordRecovery(db, 'r1', 'insurance', 40000, '2026-09-04', null)).rejects.toThrow(/recorded by the requester or the service/);
	});
});
