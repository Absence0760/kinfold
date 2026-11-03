import { describe, expect, it } from 'vitest';
import type { Db } from '#lib/supabase/client.ts';
import {
	acceptInvite,
	canInvite,
	createInvite,
	loadSupporting,
	loadSupportView,
	previewInvite,
	pledge,
	revokeInvite
} from './data.ts';
import type { RequestStatus } from '#lib/dashboard/labels.ts';

type Fixture = { data: unknown; error: { message: string; code?: string } | null; status?: number };

function fakeDb(fixtures: Record<string, Fixture>) {
	const asked: string[] = [];
	const query = (name: string) => {
		asked.push(name);
		// An rpcNew call awaits the chain, so `.then` hands the fixture to the caller;
		// `maybeSingle` answers the same fixture for a single-row read.
		const result = fixtures[name] ?? { data: [], error: null };
		const chain: Record<string, unknown> = {};
		for (const m of ['select', 'eq', 'or', 'order', 'in']) chain[m] = () => chain;
		chain.then = (ok: (v: Fixture) => unknown, bad: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
		chain.maybeSingle = () => Promise.resolve(fixtures[name] ?? { data: null, error: null });
		return chain;
	};
	return { db: { from: query, rpc: query } as unknown as Db, asked };
}

const supported = {
	id: 'r1',
	kind: 'car_damage',
	funding: 'people',
	title: 'A dented door',
	description: 'Someone backed into the driver door.',
	amount_cents: 400000,
	status: 'open',
	incident_on: '2026-09-14'
};
const second = { ...supported, id: 'r2', title: 'A cracked drive' };

describe('canInvite', () => {
	it('offers a link for exactly the statuses `create_invite` accepts', () => {
		for (const status of ['draft', 'scoring', 'needs_evidence', 'in_review', 'open', 'funded'] as RequestStatus[]) {
			expect(canInvite(status)).toBe(true);
		}
		// The four closed statuses: there is nothing left to invite people to.
		for (const status of ['withdrawn', 'expired', 'refused', 'paid'] as RequestStatus[]) {
			expect(canInvite(status)).toBe(false);
		}
	});
});

describe('loadSupportView', () => {
	it('names the payee only once the payee is verified', async () => {
		// The row is read either way; only its status decides what crosses to the page,
		// so an unverified shop's legal name never reaches a supporter's browser.
		const { db, asked } = fakeDb({
			support_requests: { data: { ...supported, payee_id: 'p1' }, error: null },
			payees: { data: { legal_name: 'Rapid Fix', status: 'unverified' }, error: null },
			request_raised_cents: { data: 120000, error: null },
			contributions: { data: [{ source: 'gift', amount_cents: 20000, status: 'pledged', created_at: '2026-10-01' }], error: null },
			family_loans: { data: [], error: null },
			request_supporters: { data: { relationship: 'family' }, error: null },
			request_names: { data: { owner_name: 'Ana' }, error: null }
		});
		const view = await loadSupportView(db, 'r1', 'm2');
		if (view === null) throw new Error('fixture has the request');
		expect(view.payeeVerified).toBe(false);
		expect(view.payeeName).toBeNull();
		expect(JSON.stringify(view)).not.toContain('Rapid Fix');
		// Everything else still reads: the refusal is about the name, not the page.
		expect(view.ownerName).toBe('Ana');
		expect(view.relationship).toBe('family');
		expect(view.raisedCents).toBe(120000);
		expect(asked).toContain('payees');
	});

	it('a verified payee shows, and a missing figure reads as nothing rather than zero', async () => {
		const { db, asked } = fakeDb({
			support_requests: { data: { ...supported, payee_id: 'p1' }, error: null },
			payees: { data: { legal_name: 'Rapid Fix', status: 'verified' }, error: null },
			request_raised_cents: { data: null, error: null },
			contributions: { data: [], error: null },
			family_loans: { data: [{ id: 'l1', principal_cents: 100000, status: 'active' }], error: null },
			request_supporters: { data: null, error: null },
			request_names: { data: null, error: null }
		});
		const view = await loadSupportView(db, 'r1', 'm2');
		if (view === null) throw new Error('fixture has the request');
		expect(view.payeeName).toBe('Rapid Fix');
		expect(view.payeeVerified).toBe(true);
		// A missing progress figure is "not shown", never a made-up $0.
		expect(view.raisedCents).toBeNull();
		expect(view.myLoans).toEqual([{ id: 'l1', principal_cents: 100000, status: 'active' }]);
		// A request the loader can't get names for shows no owner, not a blank placeholder.
		expect(view.ownerName).toBeNull();
		expect(asked[0]).toBe('support_requests');
	});

	it('a request a stranger cannot see reads as nothing, and stops the rest of the reads', async () => {
		const { db, asked } = fakeDb({ support_requests: { data: null, error: null } });
		const view = await loadSupportView(db, 'r1', 'm2');
		// RLS answers no row for a request the viewer isn't invited to.
		expect(view).toBeNull();
		expect(asked).toEqual(['support_requests']);
	});

	it('a stranger\u2019s missing-name refusal is silence, but a real failure still throws', async () => {
		// `request_names` answers P0002 for a pair the viewer isn't part of: nothing to
		// show. Anything else is a broken read, and the page must say it failed.
		const quiet = fakeDb({
			support_requests: { data: supported, error: null },
			request_names: { data: null, error: { message: 'request not found', code: 'P0002' } }
		});
		const view = await loadSupportView(quiet.db, 'r1', 'm2');
		if (view === null) throw new Error('fixture has the request');
		expect(view.ownerName).toBeNull();

		const { db } = fakeDb({
			support_requests: { data: supported, error: null },
			request_names: { data: null, error: { message: 'services unavailable', code: '500' } }
		});
		await expect(loadSupportView(db, 'r1', 'm2')).rejects.toThrow(/services unavailable/);
	});
});

describe('loadSupporting', () => {
	it('keeps the invite order and drops requests the supporter view can no longer answer', async () => {
		const { db, asked } = fakeDb({
			request_supporters: {
				data: [
					{ request_id: 'r1', relationship: 'family', joined_at: '2026-10-02' },
					{ request_id: 'r2', relationship: 'friend', joined_at: '2026-10-01' }
				],
				error: null
			},
			support_requests: { data: [second], error: null }
		});
		const rows = await loadSupporting(db, 'm2');
		expect(asked).toEqual(['request_supporters', 'support_requests']);
		// r1 left the supporter view (closed or paid); the pair's list shows what is
		// still there, in the order the invites were accepted.
		expect(rows).toEqual([{ ...second, relationship: 'friend' }]);
	});

	it('a member who has not accepted an invite reads as nothing, without a second read', async () => {
		const { db, asked } = fakeDb({ request_supporters: { data: [], error: null } });
		const rows = await loadSupporting(db, 'm2');
		expect(rows).toEqual([]);
		expect(asked).toEqual(['request_supporters']);
	});
});

describe('the writes carry one argument set each', () => {
	it('a pledge names the money and its source', async () => {
		const { db, asked } = fakeDb({ pledge: { data: null, error: null } });
		await pledge(db, 'r1', 20000, 'gift');
		expect(asked).toEqual(['pledge']);
	});

	it('making and cancelling a link are one call each', async () => {
		const made = fakeDb({ create_invite: { data: 'tok-1', error: null } });
		const token = await createInvite(made.db, 'r1', 'family');
		expect(token).toBe('tok-1');
		expect(made.asked).toEqual(['create_invite']);

		const { db, asked } = fakeDb({ revoke_invite: { data: null, error: null } });
		await revokeInvite(db, 'i1');
		expect(asked).toEqual(['revoke_invite']);
	});

	it('accepting a link answers the request it joins', async () => {
		const { db, asked } = fakeDb({ accept_invite: { data: 'r1', error: null } });
		const requestId = await acceptInvite(db, 'tok-1');
		expect(requestId).toBe('r1');
		expect(asked).toEqual(['accept_invite']);
	});
});

describe('previewInvite', () => {
	it('a live link previews what the invitee would be joining', async () => {
		const { db, asked } = fakeDb({
			invite_preview: {
				data: {
					request_id: 'r1',
					owner_name: 'Ana',
					title: 'A dented door',
					kind: 'car_damage',
					funding: 'people',
					amount_cents: 400000,
					status: 'open',
					relationship: 'family',
					expires_at: '2026-11-01'
				},
				error: null
			}
		});
		const preview = await previewInvite(db, 'tok-1');
		expect(asked).toEqual(['invite_preview']);
		expect(preview).toEqual({
			requestId: 'r1',
			ownerName: 'Ana',
			title: 'A dented door',
			kind: 'car_damage',
			amountCents: 400000,
			status: 'open',
			funding: 'people',
			relationship: 'family',
			expiresAt: '2026-11-01'
		});
	});

	it('a used-up, cancelled or expired link reads as nothing, and its refusal is explained', async () => {
		const { db, asked } = fakeDb({
			invite_preview: { data: null, error: { message: 'invite not found', code: 'P0002' } }
		});
		const preview = await previewInvite(db, 'tok-1');
		expect(preview).toBeNull();
		expect(asked).toEqual(['invite_preview']);
	});

	it('a real failure still reaches the page', async () => {
		const { db } = fakeDb({
			invite_preview: { data: null, error: { message: 'services unavailable', code: '500' } }
		});
		await expect(previewInvite(db, 'tok-1')).rejects.toThrow(/services unavailable/);
	});
});
