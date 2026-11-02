import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { inspectionWord, needsInspection } from './inspections.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null };

/** Stand-in for the Supabase client (same shape as the other data tests). */
function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		// `rpcNew` reads `.data`/`.error` straight off the call's result.
		return result;
	};
	const db = { rpc: query } as unknown as Db;
	return { db, asked };
}

describe('inspectionWord', () => {
	it('names each result in plain words', () => {
		expect(inspectionWord('clear')).toBe('the visit found the damage as described');
		expect(inspectionWord('issue_found')).toBe('the visit found a problem');
	});

	it('an unknown result is shown, not swallowed', () => {
		expect(inspectionWord('weird')).toBe('weird');
	});
});

describe('needsInspection', () => {
	it('the schema answers whether a visit is needed', async () => {
		const { db, asked } = fakeDb({ needs_inspection: { data: true, error: null } });
		const needed = await needsInspection(db, 'r1');
		expect(asked).toEqual(['needs_inspection']);
		expect(needed).toBe(true);
	});

	it('the schema\u2019s refusal reaches the caller', async () => {
		const { db } = fakeDb({ needs_inspection: { data: null, error: { message: 'request not found', code: 'P0002' } } });
		await expect(needsInspection(db, 'missing')).rejects.toThrow(/request not found/);
	});
});
