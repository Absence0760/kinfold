import { fromNew, rpcNew, supabase } from '#lib/supabase/client.ts';
import type { FundingMode, LoanStatus, RequestKind, RequestStatus } from '#lib/dashboard/labels.ts';
import {
	summarizeSupport,
	type ContributionRow,
	type ContributionSource,
	type InviteRow,
	type SupportSummary
} from './invites.ts';

/** Thrown with the PostgrestError's code and message, for explainInviteError. */
export class DbFailure extends Error {
	constructor(
		message: string,
		readonly code?: string
	) {
		super(message);
	}
}

function fail(error: { message: string; code?: string }): never {
	throw new DbFailure(error.message, error.code);
}

// --- the owner's side -----------------------------------------------------------

export interface OwnedRequest {
	id: string;
	kind: RequestKind;
	funding: FundingMode;
	title: string;
	amount_cents: number;
	status: RequestStatus;
}

/** Statuses `create_invite` still accepts. */
const INVITABLE: RequestStatus[] = ['draft', 'scoring', 'needs_evidence', 'in_review', 'open', 'funded'];

export const canInvite = (status: RequestStatus): boolean => INVITABLE.includes(status);

/** The viewer's own requests that family and friends can fund. */
export async function loadOwnPeopleRequests(viewerId: string): Promise<OwnedRequest[]> {
	const { data, error } = await supabase()
		.from('requests')
		.select('id, kind, funding, title, amount_cents, status')
		.eq('member_id', viewerId)
		.in('funding', ['people', 'both'])
		.in('status', INVITABLE)
		.order('created_at', { ascending: false });
	if (error) fail(error);
	return data ?? [];
}

export interface OwnerPanelData {
	invites: InviteRow[];
	support: SupportSummary;
	/** Display names keyed by member id (`request_names`); only this pair sees them. */
	supportNames: Map<string, string>;
	ownerName: string | null;
}

/**
 * Invites, supporters and pledges on one of the viewer's requests. RLS gives
 * the owner all three; it doesn't give them supporters' names (members read
 * only themselves), so supporters are shown by relationship.
 */
export async function loadOwnerPanel(requestId: string): Promise<OwnerPanelData> {
	const db = supabase();
	const [invites, supporters, contributions] = await Promise.all([
		db
			.from('request_invites')
			.select('id, relationship, created_at, expires_at, revoked_at, accepted_by, accepted_at')
			.eq('request_id', requestId)
			.order('created_at', { ascending: false }),
		db.from('request_supporters').select('member_id, relationship, joined_at').eq('request_id', requestId),
		db.from('contributions').select('contributor_id, source, amount_cents, status').eq('request_id', requestId)
	]);
	if (invites.error) fail(invites.error);
	if (supporters.error) fail(supporters.error);
	if (contributions.error) fail(contributions.error);
	const names = await rpcNew(db, 'request_names', { p_request: requestId });
	if (names.error && names.error.code !== 'P0002') fail(names.error);
	const rows = names.error ? [] : (names.data as { supporters?: unknown[] } | null)?.supporters ?? [];
	const byId = new Map<string, string>();
	for (const row of rows) {
		const r = row as { member_id?: string; name?: string };
		if (r?.member_id && r?.name) byId.set(r.member_id, r.name);
	}
	return {
		// `revoked_at` is in the local schema but not yet in the generated
		// database.types.ts (only the live stack regenerates it), so the rows
		// arrive untyped; the shape is pinned by the select above.
		invites: (invites.data ?? []) as unknown as InviteRow[],
		support: summarizeSupport(supporters.data ?? [], (contributions.data ?? []) as ContributionRow[]),
		supportNames: byId,
		ownerName: names.error ? null : (names.data as { owner_name?: string } | null)?.owner_name ?? null
	};
}

/** Make a new single-use invite link. The token is returned once and never stored in plain. */
export async function createInvite(requestId: string, relationship: string): Promise<string> {
	const { data, error } = await supabase().rpc('create_invite', {
		p_request: requestId,
		p_relationship: relationship
	});
	if (error) fail(error);
	return data;
}

// --- the invitee's side ---------------------------------------------------------

export async function acceptInvite(token: string): Promise<string> {
	const { data, error } = await supabase().rpc('accept_invite', { p_token: token });
	if (error) fail(error);
	return data;
}

export interface SupportedRequest {
	id: string;
	kind: RequestKind;
	funding: FundingMode;
	title: string;
	description: string;
	amount_cents: number;
	status: RequestStatus;
	incident_on: string;
}

export interface MyPledge {
	source: ContributionSource;
	amount_cents: number;
	status: ContributionRow['status'];
	created_at: string;
}

export interface SupportView {
	request: SupportedRequest;
	relationship: string | null;
	/** The owner's display name: `request_names` gives a supporter their pair. */
	ownerName: string | null;
	/** The payee's name, when it's verified (only verified payees are readable). */
	payeeName: string | null;
	payeeVerified: boolean;
	raisedCents: number | null;
	myPledges: MyPledge[];
	myLoans: { id: string; principal_cents: number; status: LoanStatus }[];
}

/**
 * Everything an invitee may see about a request they support: the supporter
 * view (`support_requests`, only what their page uses — the row and its
 * `current_score` stay the owner's), the payee if verified, progress
 * (`request_raised_cents` answers supporters), and their own pledges and
 * loans. Null when the viewer can't see it.
 */
export async function loadSupportView(requestId: string, viewerId: string): Promise<SupportView | null> {
	const db = supabase();
	// `support_requests` is newer than the committed types (the `fromNew` seam).
	const req = await fromNew(db, 'support_requests')
		.select('id, kind, funding, title, description, amount_cents, status, incident_on, payee_id')
		.eq('id', requestId)
		.maybeSingle();
	if (req.error) fail(req.error);
	if (!req.data) return null;
	const row = req.data as unknown as SupportedRequest & { payee_id: string | null };
	const payee_id = row.payee_id;
	const request: SupportedRequest = {
		id: row.id,
		kind: row.kind,
		funding: row.funding,
		title: row.title,
		description: row.description,
		amount_cents: row.amount_cents,
		status: row.status,
		incident_on: row.incident_on
	};

	const [payee, raised, mine, loans, me] = await Promise.all([
		payee_id
			? db.from('payees').select('legal_name, status').eq('id', payee_id).maybeSingle()
			: Promise.resolve({ data: null, error: null }),
		db.rpc('request_raised_cents', { p_request: requestId }),
		db
			.from('contributions')
			.select('source, amount_cents, status, created_at')
			.eq('request_id', requestId)
			.eq('contributor_id', viewerId)
			.order('created_at'),
		db
			.from('family_loans')
			.select('id, principal_cents, status')
			.eq('request_id', requestId)
			.eq('lender_id', viewerId)
			.order('created_at'),
		db
			.from('request_supporters')
			.select('relationship')
			.eq('request_id', requestId)
			.eq('member_id', viewerId)
			.maybeSingle()
	]);
	if (payee.error) fail(payee.error);
	if (mine.error) fail(mine.error);
	if (loans.error) fail(loans.error);
	if (me.error) fail(me.error);

	// The owner's name for this pair (`request_names`); a stranger's P0002
	// simply means nothing to show, anything else is a real failure.
	const names = await rpcNew(db, 'request_names', { p_request: requestId });
	if (names.error && names.error.code !== 'P0002') fail(names.error);
	const ownerName = names.error ? null : (names.data as { owner_name?: string } | null)?.owner_name ?? null;
	const verified = payee.data?.status === 'verified';
	return {
		request,
		relationship: me.data?.relationship ?? null,
		ownerName: ownerName,
		payeeName: verified ? (payee.data?.legal_name ?? null) : null,
		payeeVerified: verified,
		// A missing figure shows as "progress not shown", never as $0 raised.
		raisedCents: raised.error || raised.data == null ? null : Number(raised.data),
		myPledges: mine.data ?? [],
		myLoans: loans.data ?? []
	};
}

/** Requests the viewer accepted an invite to, newest first. */
export async function loadSupporting(viewerId: string): Promise<(SupportedRequest & { relationship: string })[]> {
	const db = supabase();
	const rows = await db
		.from('request_supporters')
		.select('request_id, relationship, joined_at')
		.eq('member_id', viewerId)
		.order('joined_at', { ascending: false });
	if (rows.error) fail(rows.error);
	const ids = (rows.data ?? []).map((r) => r.request_id);
	if (!ids.length) return [];
	const reqs = await fromNew(db, 'support_requests')
		.select('id, kind, funding, title, description, amount_cents, status, incident_on')
		.in('id', ids);
	if (reqs.error) fail(reqs.error);
	// The view is newer than the committed types, so its rows arrive untyped.
	const byId = new Map((reqs.data ?? []).map((r) => {
		const row = r as unknown as SupportedRequest;
		return [row.id, row];
	}));
	return (rows.data ?? []).flatMap((r) => {
		const req = byId.get(r.request_id);
		return req ? [{ ...req, relationship: r.relationship }] : [];
	});
}

export async function pledge(requestId: string, cents: number, source: 'gift' | 'loan'): Promise<void> {
	const { error } = await supabase().rpc('pledge', {
		p_request: requestId,
		p_amount_cents: cents,
		p_source: source
	});
	if (error) fail(error);
}
// --- cancelling a link and previewing one --------------------------------------

/** Cancel one of the owner's own waiting links (`revoke_invite`). */
export async function revokeInvite(inviteId: string): Promise<void> {
	const { error } = await rpcNew(supabase(), 'revoke_invite', { p_invite: inviteId });
	if (error) fail(error);
}

/**
 * What the invite page shows before the click (`invite_preview`). Null when the
 * link was used up, cancelled or expired — the same answer the invitee gets
 * when they try to accept it.
 */
export interface InvitePreview {
	requestId: string;
	ownerName: string;
	title: string;
	kind: RequestKind;
	amountCents: number;
	status: RequestStatus;
	funding: FundingMode;
	relationship: string;
	expiresAt: string;
}

export async function previewInvite(token: string): Promise<InvitePreview | null> {
	const { data, error } = await rpcNew(supabase(), 'invite_preview', { p_token: token });
	if (error && error.code !== 'P0002') fail(error);
	if (error || !data) return null;
	const p = data as { request_id?: string; owner_name?: string; title?: string; kind?: string; funding?: string; amount_cents?: number; status?: string; relationship?: string; expires_at?: string };
	return {
		requestId: p.request_id ?? '',
		ownerName: p.owner_name ?? '',
		title: p.title ?? '',
		kind: p.kind as RequestKind,
		amountCents: p.amount_cents ?? 0,
		status: p.status as RequestStatus,
		funding: p.funding as FundingMode,
		relationship: p.relationship ?? '',
		expiresAt: p.expires_at ?? ''
	};
}
