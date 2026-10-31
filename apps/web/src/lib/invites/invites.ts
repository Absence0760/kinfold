import { formatCents } from '#lib/dashboard/format.ts';
import { payeeWord, type RequestKind, type RequestStatus } from '#lib/dashboard/labels.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';

export type ContributionSource = Database['public']['Enums']['contribution_source'];
export type ContributionStatus = Database['public']['Enums']['contribution_status'];

// --- the invite link ------------------------------------------------------------

/** `create_invite` returns 24 random bytes as hex. Anything else isn't a token. */
const TOKEN = /^[0-9a-f]{48}$/;

export const isInviteToken = (token: string): boolean => TOKEN.test(token);

/** The link the owner shares: `/app/invite/<token>` on the site they're using. */
export function inviteLink(origin: string, token: string): string {
	if (!isInviteToken(token)) throw new RangeError('not an invite token');
	return `${origin.replace(/\/+$/, '')}/app/invite/${token}`;
}

// --- relationships --------------------------------------------------------------

/**
 * Who the invitee is to the member. Stored as free text (1 to 40 characters,
 * `request_invites.relationship`); these are the quick choices, stored in lower
 * case the way the seed stores "brother".
 */
export const RELATIONSHIPS = [
	'parent',
	'child',
	'brother',
	'sister',
	'grandparent',
	'aunt or uncle',
	'cousin',
	'partner',
	'friend',
	'coworker',
	'neighbor'
] as const;

export const RELATIONSHIP_MAX = 40;

/** The relationship to store, or a reason it can't be. */
export function checkRelationship(input: string): { value: string } | { problem: string } {
	const value = input.trim().replace(/\s+/g, ' ');
	if (!value) return { problem: 'Say who this person is to you, like “sister” or “friend”.' };
	if (value.length > RELATIONSHIP_MAX)
		return { problem: `Keep it to ${RELATIONSHIP_MAX} characters or fewer.` };
	return { value };
}

/** A stored relationship for display: "aunt or uncle" → "Aunt or uncle". */
export function relationshipLabel(stored: string): string {
	const s = stored.trim();
	return s ? s.charAt(0).toUpperCase() + s.slice(1) : 'Someone you invited';
}

// --- invite state ---------------------------------------------------------------

export interface InviteRow {
	id: string;
	relationship: string;
	created_at: string;
	expires_at: string;
	accepted_by: string | null;
	accepted_at: string | null;
}

export type InviteState = 'waiting' | 'accepted' | 'expired';

export function inviteState(invite: InviteRow, now: Date = new Date()): InviteState {
	if (invite.accepted_at) return 'accepted';
	return new Date(invite.expires_at).getTime() <= now.getTime() ? 'expired' : 'waiting';
}

/** Whole days left on a waiting invite, at least 1 while it's still open. */
export function daysLeft(invite: InviteRow, now: Date = new Date()): number {
	const ms = new Date(invite.expires_at).getTime() - now.getTime();
	return Math.max(1, Math.ceil(ms / 86_400_000));
}

export function inviteStateText(invite: InviteRow, now: Date = new Date()): string {
	switch (inviteState(invite, now)) {
		case 'accepted':
			return 'Accepted';
		case 'expired':
			return 'Expired, not used';
		case 'waiting': {
			const d = daysLeft(invite, now);
			return `Not used yet, ${d} ${d === 1 ? 'day' : 'days'} left`;
		}
	}
}

// --- supporters and their pledges ----------------------------------------------

export interface SupporterRow {
	member_id: string;
	relationship: string;
	joined_at: string;
}

export interface ContributionRow {
	contributor_id: string | null;
	source: ContributionSource;
	amount_cents: number;
	status: ContributionStatus;
}

export interface SupporterLine {
	memberId: string;
	relationship: string;
	joinedAt: string;
	giftCents: number;
	loanCents: number;
	/** Pledges that no longer count (the request ended unpaid, or was refunded). */
	releasedCents: number;
}

export interface SupportSummary {
	supporters: SupporterLine[];
	/** Gifts from verified members who found the request on the board, not by invite. */
	otherGiftCents: number;
	poolCents: number;
	raisedCents: number;
}

const counts = (s: ContributionStatus) => s === 'pledged' || s === 'captured';

/**
 * Each supporter with what they've pledged, in the order they joined. Never
 * sorted by amount: the giving record is private and nobody is ranked.
 */
export function summarizeSupport(supporters: SupporterRow[], contributions: ContributionRow[]): SupportSummary {
	const lines = new Map<string, SupporterLine>();
	for (const s of [...supporters].sort(
		(a, b) => a.joined_at.localeCompare(b.joined_at) || a.member_id.localeCompare(b.member_id)
	)) {
		lines.set(s.member_id, {
			memberId: s.member_id,
			relationship: s.relationship,
			joinedAt: s.joined_at,
			giftCents: 0,
			loanCents: 0,
			releasedCents: 0
		});
	}

	let otherGiftCents = 0;
	let poolCents = 0;
	let raisedCents = 0;
	for (const c of contributions) {
		const live = counts(c.status);
		if (live) raisedCents += c.amount_cents;
		if (c.source === 'pool') {
			if (live) poolCents += c.amount_cents;
			continue;
		}
		const line = c.contributor_id ? lines.get(c.contributor_id) : undefined;
		if (!line) {
			if (live) otherGiftCents += c.amount_cents;
			continue;
		}
		if (!live) line.releasedCents += c.amount_cents;
		else if (c.source === 'gift') line.giftCents += c.amount_cents;
		else line.loanCents += c.amount_cents;
	}

	return { supporters: [...lines.values()], otherGiftCents, poolCents, raisedCents };
}

/** What one supporter has pledged, in words. */
export function pledgeText(line: SupporterLine): string {
	const parts: string[] = [];
	if (line.giftCents) parts.push(`gives ${formatCents(line.giftCents)}`);
	if (line.loanCents) parts.push(`lends ${formatCents(line.loanCents)} at 0%`);
	if (!parts.length) return line.releasedCents ? 'Pledge released' : 'Hasn’t pledged yet';
	const s = parts.join(' and ');
	return s.charAt(0).toUpperCase() + s.slice(1);
}

// --- pledging -------------------------------------------------------------------

/** What's still needed. Never negative. */
export const leftCents = (amountCents: number, raisedCents: number): number =>
	Math.max(0, amountCents - raisedCents);

export type PledgeGate =
	| { open: true }
	| { open: false; reason: string };

/**
 * Whether the invitee can pledge now, mirroring the checks in `pledge`: the
 * request must be open, its payee verified, something still needed, and a loan
 * needs a verified member. The database checks again; this only explains.
 */
export function pledgeGate(input: {
	status: RequestStatus;
	kind: RequestKind;
	payeeVerified: boolean;
	leftCents: number;
}): PledgeGate {
	const payee = payeeWord(input.kind);
	switch (input.status) {
		case 'draft':
		case 'scoring':
		case 'needs_evidence':
		case 'in_review':
			return {
				open: false,
				reason:
					'The request is still being checked. You can pledge once its evidence has been checked and it opens for help. Come back to this page, or find it under Invites.'
			};
		case 'funded':
			return {
				open: false,
				reason: `It’s fully pledged, so no more pledges are needed. The money is being collected, then paid straight to ${payee}.`
			};
		case 'paid':
			return { open: false, reason: `It’s done: the money was paid to ${payee}.` };
		case 'refused':
		case 'withdrawn':
		case 'expired':
			return {
				open: false,
				reason: 'This request has closed without being paid, so it isn’t taking pledges. Any pledges were released and nothing was collected.'
			};
		case 'open':
			break;
	}
	if (!input.payeeVerified)
		return {
			open: false,
			reason: `Pledges open once ${payee} has been verified, so we know the money reaches a real business. This usually takes a day or two.`
		};
	if (input.leftCents <= 0) return { open: false, reason: 'It’s fully pledged, so no more pledges are needed.' };
	return { open: true };
}

/** Why an amount can't be pledged, or null when it can. */
export function pledgeAmountProblem(cents: number | null, left: number): string | null {
	if (cents == null) return 'Enter an amount in dollars, like 50 or 25.50.';
	if (cents < 1) return 'Enter an amount above $0.';
	if (cents > left) return `This request needs ${formatCents(left)} more, so pledge up to that.`;
	return null;
}

/** Quick-pick amounts that fit what's left, ending with "the rest". */
export function quickAmounts(left: number): number[] {
	const picks = [2_500, 5_000, 10_000, 25_000].filter((c) => c < left);
	if (left > 0) picks.push(left);
	return picks;
}

/** 2026 annual gift-tax exclusion per recipient (design.md, Product 1). */
export const GIFT_EXCLUSION_CENTS = 1_900_000;
