import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import { loadBoard, loadRaised, pledgeGift } from './data.ts';

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
	return { db: { from: query, rpc: query } as unknown as Db, asked };
}

const carRow = {
	id: 'b1',
	kind: 'car_damage',
	public_summary: 'Rear bumper after being rear-ended.',
	status: 'open',
	amount_cents: 185_000,
	amount_band_min_cents: 100_000,
	amount_band_max_cents: 250_000,
	score_band: 80,
	area: 'Pacific',
	month_of: '2026-10-01',
	raised_cents: 0,
	taking_pledges: true
};
const homeRow = { ...carRow, id: 'b2', kind: 'home_repair', public_summary: 'Water reached the furnace.' };

describe('loadBoard', () => {
	it('marks the viewer’s own requests and words each band against its fund’s minimum', async () => {
		const { db, asked } = fakeDb({
			board_requests: { data: [carRow, homeRow], error: null },
			requests: { data: [{ id: 'b1' }], error: null },
			fund_settings: { data: [{ fund: 'protection', min_score: 70 }, { fund: 'home_fund', min_score: 65 }], error: null }
		});
		const items = await loadBoard(db, 'm1');
		expect(asked.length).toBe(3);
		expect(items.map((i) => i.own)).toEqual([true, false]);
		// The fund a kind draws on decides which minimum words its band: a car
		// request reads the repair fund's, a home request the Home Fund's.
		expect(items.map((i) => i.minScore)).toEqual([70, 65]);
		expect(items[0].summary).toBe(carRow.public_summary);
		expect(items[0].raisedCents).toBe(0);
	});

	it('a fund_settings read that fails leaves the board standing, without the minimum', async () => {
		const { db, asked } = fakeDb({
			board_requests: { data: [carRow], error: null },
			requests: { data: [], error: null },
			fund_settings: { data: null, error: { message: 'permission denied', code: '42501' } }
		});
		const items = await loadBoard(db, 'm1');
		// The band's status line is left out rather than inventing a minimum; the
		// board itself must still show.
		expect(items).toHaveLength(1);
		expect(items[0].minScore).toBeNull();
		expect(asked.length).toBe(3);
	});

	it('a board read the member cannot do throws the board’s own error, with the code kept', async () => {
		const { db, asked } = fakeDb({
			board_requests: { data: null, error: { message: 'permission denied for view board_requests', code: '42501' } },
			requests: { data: [], error: null },
			fund_settings: { data: [], error: null }
		});
		await expect(loadBoard(db, 'm1')).rejects.toThrow(/permission denied/);
	});

	it('rows the view answers with nothing read as an empty board, not an error', async () => {
		const { db, asked } = fakeDb({ board_requests: { data: [], error: null }, requests: { data: [], error: null }, fund_settings: { data: [], error: null } });
		const items = await loadBoard(db, 'm1');
		expect(items).toEqual([]);
		expect(asked.length).toBe(3);
	});
});

describe('the pledge from the board', () => {
	it('a board pledge is a gift, never a loan: strangers cannot lend', async () => {
		const { db, asked } = fakeDb({ pledge: { data: null, error: null } });
		await pledgeGift(db, 'b1', 20_000);
		expect(asked).toEqual(['pledge']);
	});

	it('the pledge form keeps the database’s refusal for its explainer', async () => {
		const { db } = fakeDb({
			pledge: { data: null, error: { message: 'permission denied for insert contributions', code: '42501' } }
		});
		await expect(pledgeGift(db, 'b1', 20_000)).rejects.toThrow(/permission denied/);
	});

	it('re-reading progress answers the figure, or nothing when it is not shared', async () => {
		const withFigure = fakeDb({ request_raised_cents: { data: 20_000, error: null } });
		expect(await loadRaised(withFigure.db, 'b1')).toBe(20_000);

		const { db } = fakeDb({ request_raised_cents: { data: null, error: null } });
		expect(await loadRaised(db, 'b1')).toBeNull();
	});
});
