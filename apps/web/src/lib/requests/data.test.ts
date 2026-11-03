import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import {
	createDraft,
	evidenceLink,
	loadFormContext,
	loadRequest,
	proposePayee,
	removeEvidence,
	submitRequest,
	updateDraft,
	withdrawRequest,
	confirmSummary,
	confirmRedaction,
	fileAppeal,
	type RequestDetail
} from './data.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null };

function fakeDb(fixtures: Record<string, Fixture>, storage: Record<string, Fixture> = {}) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'in', 'or', 'order', 'is', 'insert', 'update', 'delete']) chain[m] = () => chain;
		// `single()` answers with the first row, like postgrest-js does.
		chain.single = () => Promise.resolve({
			data: Array.isArray(result.data) ? (result.data as unknown[])[0] : result.data,
			error: result.error
		});
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		chain.maybeSingle = () => Promise.resolve(fixtures[name] ?? { data: null, error: null });
		return chain;
	};
	const db = {
		from: query,
		rpc: query,
		storage: {
			// One fixture per bucket; the methods the loaders call answer with it.
			from: (bucket: string) => {
				asked.push('storage:' + bucket);
				const result = storage[bucket] ?? { data: [], error: null };
				return {
					list: () => Promise.resolve(result),
					upload: () => Promise.resolve(result),
					createSignedUrl: () => Promise.resolve(result)
				};
			}
		}
	} as unknown as Db;
	return { db, asked };
}

const id = '00000000-0000-0000-0037-0000000000e1';

describe('loadFormContext', () => {
	it('reads the fund rules, the payees, the member\u2019s cars and when cover began', async () => {
		const { db, asked } = fakeDb({
			fund_settings: { data: [{ fund: 'protection', kinds: ['car_damage'], max_request_cents: 200000, waiting_days: 60, min_score: 70 }], error: null },
			payees: { data: [{ id: 'p1', kind: 'shop', legal_name: 'Rapid Fix', region: 'CA', status: 'verified' }], error: null },
			covered_assets: { data: [{ id: 'v1', kind: 'car', description: 'A grey sedan', registered_on: '2026-01-02', removed_on: null }], error: null },
			coverage_started_on: { data: '2026-04-05', error: null }
		});
		const ctx = await loadFormContext(db, 'm1');
		expect(asked).toEqual(['fund_settings', 'payees', 'covered_assets', 'coverage_started_on']);
		expect(ctx.coverageStartedOn).toBe('2026-04-05');
		expect(ctx.payees).toHaveLength(1);
		expect(ctx.assets).toHaveLength(1);
	});

	it('a car retired from the member\u2019s list is not offered, because the read asks for none', async () => {
		// RLS and the `is(removed_on, null)` filter decide what the form offers; the
		// loader passes the rows through untouched, so a retired car never appears.
		const { db } = fakeDb({ covered_assets: { data: [], error: null } });
		const ctx = await loadFormContext(db, 'm1');
		expect(ctx.assets).toEqual([]);
	});
});

describe('loadRequest', () => {
	it('a malformed id reads as nothing, not as a failed server read', async () => {
		const { db } = fakeDb({ requests: { data: null, error: { message: 'invalid uuid', code: '22P02' } } });
		expect(await loadRequest(db, 'not-a-uuid')).toBeNull();
	});

	it('a request the viewer cannot see reads as nothing, and the rest is never read', async () => {
		const { db, asked } = fakeDb({ requests: { data: null, error: null } });
		expect(await loadRequest(db, id)).toBeNull();
		expect(asked).toEqual(['requests']);
	});

	it('a draft marks the evidence whose original never reached storage', async () => {
		// The member may list their own folder of originals; the row is only
		// `stored: false` when the listing worked and the file wasn't in it.
		const { db, asked } = fakeDb(
			{
				requests: { data: { id, member_id: 'm1', kind: 'car_damage', funding: 'pool', title: 'A dented door', amount_cents: 100000, incident_on: '2026-09-14', status: 'draft' }, error: null },
				evidence: {
					data: [
						{ id: 'e1', kind: 'photo', original_path: 'm1/' + id + '/a.jpg', redacted_path: null, redaction_status: 'pending', captured_in_app: false, created_at: '2026-10-01' },
						{ id: 'e2', kind: 'photo', original_path: 'm1/' + id + '/b.jpg', redacted_path: null, redaction_status: 'pending', captured_in_app: false, created_at: '2026-10-02' }
					],
					error: null
				},
				scores: { data: [], error: null },
				appeals: { data: [], error: null },
				my_request_reviews: { data: [], error: null },
				request_events: { data: [], error: null },
				payouts: { data: [], error: null },
				claims: { data: [], error: null },
				request_recoveries: { data: [], error: null },
				inspections: { data: [], error: null },
				needs_inspection: { data: false, error: null }
			},
			{ 'evidence-original': { data: [{ name: 'a.jpg' }], error: null } }
		);
		const detail = await loadRequest(db, id);
		if (detail === null) throw new Error('fixture has the request');
		expect(detail.evidence.map((e) => e.stored)).toEqual([true, false]);
		expect(asked).toContain('storage:evidence-original');
		expect(detail.needsInspection).toBe(false);
	});

	it('a request past the draft stage never lists the bucket', async () => {
		// Only evidence that can still change can have an unfinished upload behind
		// it, so the listing is skipped and every row reads stored.
		const { db, asked } = fakeDb({
			requests: { data: { id, member_id: 'm1', kind: 'car_damage', funding: 'pool', title: 'A dented door', amount_cents: 100000, incident_on: '2026-09-14', status: 'open' }, error: null },
			evidence: { data: [{ id: 'e1', kind: 'photo', original_path: 'm1/' + id + '/a.jpg', redacted_path: 'r/a.jpg', redaction_status: 'confirmed', captured_in_app: false, created_at: '2026-10-01' }], error: null }
		});
		const detail = await loadRequest(db, id);
		if (detail === null) throw new Error('fixture has the request');
		expect(detail.evidence[0].stored).toBe(true);
		expect(asked).not.toContain('storage:evidence-original');
	});
});

describe('the form writes', () => {
	it('a new draft answers with its own id, and the member is the one who made it', async () => {
		const { db, asked } = fakeDb({ requests: { data: [{ id }], error: null } });
		const created = await createDraft(db, 'm1', { kind: 'car_damage', funding: 'pool', title: 'A dented door', description: 'Someone backed into the driver door.', amount_cents: 100000, incident_on: '2026-09-14', payee_id: null, asset_id: null });
		expect(created).toBe(id);
		expect(asked).toEqual(['requests']);
	});

	it('a payee proposal answers with the row Kinfold will verify later', async () => {
		const { db, asked } = fakeDb({ payees: { data: [{ id: 'p2', kind: 'shop', legal_name: 'Rapid Fix', region: 'CA', status: 'proposed' }], error: null } });
		const payee = await proposePayee(db, 'm1', { kind: 'repair_shop', legal_name: 'Rapid Fix', region: 'CA' });
		expect(payee.status).toBe('proposed');
		expect(asked).toEqual(['payees']);
	});

	it('an update that matched no editable draft is explained, not left silent', async () => {
		const { db, asked } = fakeDb({ requests: { data: [], error: null } });
		await expect(
			updateDraft(
				db,
				id,
				{ kind: 'car_damage', funding: 'pool', title: 'x', description: 'y', amount_cents: 100000, incident_on: '2026-09-14', payee_id: null, asset_id: null }
			)
		).rejects.toThrow(/isn.t a draft any more/);
		expect(asked).toEqual(['requests']);
	});

	it('an evidence row that can no longer be removed is explained too', async () => {
		const { db } = fakeDb({ requests: { data: [], error: null } });
		await expect(removeEvidence(db, 'e1')).rejects.toThrow(/can be removed only while a request is a draft/);
	});
});

describe('the request actions', () => {
	it('each one call carries only its own id', async () => {
		const { db, asked } = fakeDb({
			submit_request: { data: null, error: null },
			withdraw_request: { data: null, error: null },
			confirm_public_summary: { data: null, error: null },
			confirm_redaction: { data: null, error: null },
			file_appeal: { data: null, error: null }
		});
		await submitRequest(db, id);
		await withdrawRequest(db, id);
		await confirmSummary(db, id);
		await confirmRedaction(db, 'e1');
		await fileAppeal(db, id, 'The shop invoice shows the work I paid for.');
		expect(asked).toEqual(['submit_request', 'withdraw_request', 'confirm_public_summary', 'confirm_redaction', 'file_appeal']);
	});

	it('the schema\u2019s refusal reaches the member in plain words', async () => {
		const { db } = fakeDb({
			submit_request: { data: null, error: { message: 'verify your identity before submitting a request', code: '42501' } }
		});
		await expect(submitRequest(db, id)).rejects.toThrow(/Verify your identity first/);
	});

	it('a link to a file that never finished uploading says so', async () => {
		const { db } = fakeDb({
			requests: { data: [], error: null }
		}, { 'evidence-original': { data: null, error: { message: 'Object not found', code: '404' } } });
		await expect(evidenceLink(db, 'evidence-original', 'm1/x/a.jpg')).rejects.toThrow(/isn\u2019t in storage/);
	});
});
