import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { classCoverVehicle, loadCover, setCoverPlan } from './data.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'or', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		chain.maybeSingle = () => Promise.resolve(fixtures[name] ?? { data: null, error: null });
		return chain;
	};
	const db = { from: query, rpc: query } as unknown as Db;
	return { db, asked };
}

const sedan = { id: 'v1', description: 'A grey sedan', vehicle_class: 'sedan', removed_on: null };
const unclassed = { id: 'v2', description: 'A van with no class stated', vehicle_class: null, removed_on: null };
const retired = { id: 'v3', description: 'A retired coupe', vehicle_class: 'sedan', removed_on: '2026-09-01' };
const rates = [
	{ vehicle_class: 'sedan', plan: 'basic', premium_cents: 12900, cap_cents: 50000 },
	{ vehicle_class: 'sedan', plan: 'standard', premium_cents: 18900, cap_cents: 100000 },
	{ vehicle_class: 'van', plan: 'basic', premium_cents: 18900, cap_cents: 50000 }
];

describe('loadCover', () => {
	it('reads the member’s vehicles, the filed rates and their premium', async () => {
		const { db, asked } = fakeDb({
			covered_assets: { data: [sedan, unclassed, retired], error: null },
			cover_plans: { data: rates, error: null },
			cover_choices: { data: { plan: 'standard' }, error: null },
			cover_premium_cents: { data: 18900, error: null }
		});
		const detail = await loadCover(db, 'a1');
		expect(asked).toEqual(['covered_assets', 'cover_plans', 'cover_choices', 'cover_premium_cents']);
		expect(detail.assets).toEqual([sedan, unclassed]);
		expect(detail.filed).toEqual(rates.filter((r) => r.vehicle_class === 'sedan'));
		expect(detail.plan).toEqual('standard');
		expect(detail.premiumCents).toEqual(18900);
	});

	it('no plan chosen reads as nothing chosen, not as a written row', async () => {
		const { db } = fakeDb({
			covered_assets: { data: [sedan], error: null },
			cover_plans: { data: rates, error: null },
			cover_choices: { data: null, error: null },
			cover_premium_cents: { data: 12900, error: null }
		});
		const detail = await loadCover(db, 'a1');
		expect(detail.plan).toBeNull();
		expect(detail.premiumCents).toEqual(12900);
	});

	it('an unclassed vehicle answers with no filed rates and no premium money', async () => {
		const { db } = fakeDb({
			covered_assets: { data: [unclassed], error: null },
			cover_plans: { data: rates, error: null },
			cover_choices: { data: null, error: null },
			cover_premium_cents: { data: 0, error: null }
		});
		const detail = await loadCover(db, 'a1');
		expect(detail.filed).toEqual([]);
		expect(detail.premiumCents).toEqual(0);
	});

	it('a refused read fails loudly rather than showing nothing', async () => {
		const { db } = fakeDb({
			covered_assets: { data: null, error: { message: 'permission denied for table covered_assets' } }
		});
		await expect(loadCover(db, 'a1')).rejects.toThrow(/permission denied/);
	});
});

describe('setCoverPlan', () => {
	it('one call carries the chosen plan', async () => {
		const { db, asked } = fakeDb({ set_my_plan: { data: null, error: null } });
		await setCoverPlan(db, 'standard');
		expect(asked).toEqual(['set_my_plan']);
	});

	it('the schema’s refusal reaches the console', async () => {
		const { db } = fakeDb({
			set_my_plan: { data: null, error: { message: 'the member\u2019s plan is chosen by a signed-in member', code: '42501' } }
		});
		await expect(setCoverPlan(db, 'basic')).rejects.toThrow(/signed-in member/);
	});
});

describe('classCoverVehicle', () => {
	it('one call carries the vehicle and the class', async () => {
		const { db, asked } = fakeDb({ set_vehicle_class: { data: null, error: null } });
		await classCoverVehicle(db, 'v2', 'van');
		expect(asked).toEqual(['set_vehicle_class']);
	});

	it('an asset that isn\u2019t the member\u2019s answers with the schema\u2019s words', async () => {
		const { db } = fakeDb({
			set_vehicle_class: { data: null, error: { message: 'asset not found, not yours, already removed, or not a vehicle', code: 'P0002' } }
		});
		await expect(classCoverVehicle(db, 'v9', 'van')).rejects.toThrow(/not a vehicle/);
	});
});
