import { rpcNew, type Db } from '#lib/supabase/client.ts';

export interface ClaimRow {
	id: string;
	request_id: string;
	partner_ref: string;
	gross_cents: number;
	member_share_cents: number;
	paid_cents: number;
	status: string;
	reason: string | null;
	recorded_at: string;
	deadline: string | null;
}

/** How a claim reads on the request page (the appeal invite is the denied one). */
export function claimStatusText(status: string): string {
	return ({
		recorded: 'Recorded, payment not confirmed yet',
		paid: 'Paid in full to the shop',
		denied: 'Denied by a person'
	})[status] ?? status;
}

/**
 * Appeals a denied claim: the reason is checked locally first (the schema
 * enforces >= 10 characters too), then the schema decides the rest: the claim
 * must be denied and belong to the requester.
 */
export async function appealClaim(db: Db, claimId: string, reason: string): Promise<{ appealed: boolean; message: string | null }> {
	if (reason.trim().length < 10) {
		return { appealed: false, message: 'An appeal needs a reason of at least 10 characters.' };
	}
	const result = await rpcNew(db, 'appeal_claim', { p_claim: claimId, p_reason: reason.trim() });
	if (result.error) {
		const message = result.error.message;
		return { appealed: false, message };
	}
	return { appealed: true, message: null };
}
