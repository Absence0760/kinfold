import { describe, expect, it } from 'vitest';
import {
	checkRelationship,
	daysLeft,
	inviteLink,
	inviteState,
	inviteStateText,
	isInviteToken,
	leftCents,
	pledgeAmountProblem,
	pledgeGate,
	pledgeText,
	quickAmounts,
	relationshipLabel,
	RELATIONSHIPS,
	summarizeSupport,
	type ContributionRow,
	type InviteRow
} from './invites';

const TOKEN = 'a1'.repeat(24);

describe('invite links', () => {
	it('accepts only the 48-hex token create_invite returns', () => {
		expect(isInviteToken(TOKEN)).toBe(true);
		expect(isInviteToken(TOKEN.slice(0, 47))).toBe(false);
		expect(isInviteToken(TOKEN.toUpperCase())).toBe(false);
		expect(isInviteToken(`${TOKEN}0`)).toBe(false);
		expect(isInviteToken('../../app')).toBe(false);
	});

	it('builds the link on the current origin', () => {
		expect(inviteLink('https://kinfold.org', TOKEN)).toBe(`https://kinfold.org/app/invite/${TOKEN}`);
		expect(inviteLink('http://localhost:7790/', TOKEN)).toBe(`http://localhost:7790/app/invite/${TOKEN}`);
	});

	it('refuses to build a link from anything but a token', () => {
		expect(() => inviteLink('https://kinfold.org', 'nope')).toThrow(RangeError);
	});
});

describe('relationships', () => {
	it('trims, collapses spaces and keeps the member’s words', () => {
		expect(checkRelationship('  big   sister ')).toEqual({ value: 'big sister' });
	});

	it('needs 1 to 40 characters, like the column check', () => {
		expect(checkRelationship('   ')).toHaveProperty('problem');
		expect(checkRelationship('x'.repeat(40))).toEqual({ value: 'x'.repeat(40) });
		expect(checkRelationship('x'.repeat(41))).toHaveProperty('problem');
	});

	it('every quick choice is storable', () => {
		for (const r of RELATIONSHIPS) expect(checkRelationship(r)).toEqual({ value: r });
	});

	it('labels a stored relationship for display', () => {
		expect(relationshipLabel('brother')).toBe('Brother');
		expect(relationshipLabel('aunt or uncle')).toBe('Aunt or uncle');
		expect(relationshipLabel('')).toBe('Someone you invited');
	});
});

describe('invite state', () => {
	const now = new Date('2026-10-31T12:00:00Z');
	const base: InviteRow = {
		id: 'i1',
		relationship: 'friend',
		created_at: '2026-10-30T12:00:00Z',
		expires_at: '2026-11-29T12:00:00Z',
		accepted_by: null,
		accepted_at: null,
		revoked_at: null
	};

	it('is waiting, with days left, until used or expired', () => {
		expect(inviteState(base, now)).toBe('waiting');
		expect(daysLeft(base, now)).toBe(29);
		expect(inviteStateText(base, now)).toBe('Not used yet, 29 days left');
		expect(inviteStateText({ ...base, expires_at: '2026-10-31T13:00:00Z' }, now)).toBe(
			'Not used yet, 1 day left'
		);
	});

	it('is accepted once used, even after the expiry date', () => {
		const used = { ...base, accepted_by: 'm', accepted_at: '2026-10-31T00:00:00Z' };
		expect(inviteState(used, new Date('2027-01-01'))).toBe('accepted');
	});

	it('is cancelled once the owner revokes the link', () => {
		const gone = { ...base, revoked_at: '2026-10-30T18:00:00Z' };
		expect(inviteState(gone, now)).toBe('cancelled');
		expect(inviteStateText(gone, now)).toBe('Cancelled, nobody joined');
	});

	it('expires at expires_at, matching accept_invite’s expires_at > now()', () => {
		expect(inviteState(base, new Date(base.expires_at))).toBe('expired');
		expect(inviteStateText(base, new Date('2026-12-01'))).toBe('Expired, not used');
	});
});

describe('summarizeSupport', () => {
	const supporters = [
		{ member_id: 'b', relationship: 'sister', joined_at: '2026-10-02T00:00:00Z' },
		{ member_id: 'a', relationship: 'brother', joined_at: '2026-10-01T00:00:00Z' }
	];
	const c = (contributor_id: string | null, source: ContributionRow['source'], amount_cents: number, status: ContributionRow['status'] = 'pledged'): ContributionRow => ({
		contributor_id,
		source,
		amount_cents,
		status
	});

	it('totals each supporter’s gifts and loans', () => {
		const s = summarizeSupport(supporters, [c('a', 'gift', 30_000), c('a', 'loan', 70_000, 'captured')]);
		const brother = s.supporters.find((l) => l.memberId === 'a');
		expect(brother).toMatchObject({ giftCents: 30_000, loanCents: 70_000, releasedCents: 0 });
		expect(s.raisedCents).toBe(100_000);
		expect(pledgeText(brother!)).toBe('Gives $300 and lends $700 at 0%');
	});

	it('orders by when they joined, never by how much they gave', () => {
		const s = summarizeSupport(supporters, [c('b', 'gift', 100), c('a', 'gift', 999_900)]);
		expect(s.supporters.map((l) => l.memberId)).toEqual(['a', 'b']);
		const s2 = summarizeSupport(supporters, [c('b', 'gift', 999_900), c('a', 'gift', 100)]);
		expect(s2.supporters.map((l) => l.memberId)).toEqual(['a', 'b']);
	});

	it('keeps board gifts and pool grants apart from supporters', () => {
		const s = summarizeSupport(supporters, [c('stranger', 'gift', 5_000), c(null, 'pool', 20_000)]);
		expect(s.otherGiftCents).toBe(5_000);
		expect(s.poolCents).toBe(20_000);
		expect(s.raisedCents).toBe(25_000);
	});

	it('does not count released or refunded pledges as raised', () => {
		const s = summarizeSupport(supporters, [c('a', 'gift', 5_000, 'released'), c('b', 'loan', 1_000, 'refunded')]);
		expect(s.raisedCents).toBe(0);
		expect(pledgeText(s.supporters[0])).toBe('Pledge released');
	});

	it('says when someone hasn’t pledged', () => {
		const s = summarizeSupport(supporters, []);
		expect(pledgeText(s.supporters[0])).toBe('Hasn’t pledged yet');
	});
});

describe('pledge limits', () => {
	it('leaves never goes negative', () => {
		expect(leftCents(100_000, 30_000)).toBe(70_000);
		expect(leftCents(100_000, 120_000)).toBe(0);
	});

	it('allows 1 cent up to exactly what is left, like pledge()', () => {
		expect(pledgeAmountProblem(1, 500)).toBeNull();
		expect(pledgeAmountProblem(500, 500)).toBeNull();
		expect(pledgeAmountProblem(501, 500)).toBe('This request needs $5 more, so pledge up to that.');
		expect(pledgeAmountProblem(0, 500)).not.toBeNull();
		expect(pledgeAmountProblem(null, 500)).toMatch(/Enter an amount/);
	});

	it('quick amounts fit and end with exactly what is left', () => {
		expect(quickAmounts(7_000)).toEqual([2_500, 5_000, 7_000]);
		expect(quickAmounts(2_500)).toEqual([2_500]);
		expect(quickAmounts(0)).toEqual([]);
		for (const left of [1, 999, 10_000, 123_456]) {
			const picks = quickAmounts(left);
			expect(picks.at(-1)).toBe(left);
			for (const p of picks) expect(pledgeAmountProblem(p, left)).toBeNull();
		}
	});
});

describe('pledgeGate', () => {
	const base = { status: 'open' as const, kind: 'car_deductible' as const, payeeVerified: true, leftCents: 100 };

	it('opens only for an open request with a verified payee and something left', () => {
		expect(pledgeGate(base)).toEqual({ open: true });
		expect(pledgeGate({ ...base, payeeVerified: false })).toMatchObject({ open: false, reason: /verified/ });
		expect(pledgeGate({ ...base, leftCents: 0 })).toMatchObject({ open: false, reason: /fully pledged/ });
	});

	it('explains every other status in words, naming the payee', () => {
		for (const status of ['draft', 'scoring', 'needs_evidence', 'in_review'] as const)
			expect(pledgeGate({ ...base, status })).toMatchObject({ open: false, reason: /being checked/ });
		expect(pledgeGate({ ...base, status: 'funded' })).toMatchObject({ reason: /the shop/ });
		expect(pledgeGate({ ...base, status: 'paid', kind: 'down_payment' })).toMatchObject({
			reason: /the lender or seller/
		});
		for (const status of ['refused', 'withdrawn', 'expired'] as const)
			expect(pledgeGate({ ...base, status })).toMatchObject({ open: false, reason: /released/ });
	});
});
