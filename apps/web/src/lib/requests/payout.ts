import { formatCents } from '#lib/dashboard/format.ts';
import type { Tone } from '#lib/dashboard/labels.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';

export type PayoutStatus = Database['public']['Enums']['payout_status'];

/** The payout columns the owner reads (the "owners read payouts" policy). */
export interface PayoutLike {
	status: PayoutStatus;
	amount_cents: number;
	sent_at: string | null;
}

export interface PayoutText {
	label: string;
	line: string;
	tone: Tone;
}

const day = (at: string) => new Date(at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

/**
 * A payout to the payee in words, for the member's request page. Kinfold
 * never holds the money: the payment partner sends it straight to the payee,
 * so every line names the payee, never the member.
 */
export function payoutText(p: PayoutLike, payee: string): PayoutText {
	const amount = formatCents(p.amount_cents);
	switch (p.status) {
		case 'pending':
			return {
				label: 'Being sent',
				line: `${amount} is on its way from the payment partner to ${payee}.`,
				tone: 'progress'
			};
		case 'sent':
			return {
				label: 'Sent',
				line: p.sent_at ? `${amount} was sent to ${payee} on ${day(p.sent_at)}.` : `${amount} was sent to ${payee}.`,
				tone: 'done'
			};
		case 'failed':
			return {
				label: 'Didn’t go through',
				line: `Sending ${amount} to ${payee} didn’t go through. Kinfold follows it up with the payment partner; you don’t need to do anything.`,
				tone: 'action'
			};
		case 'returned':
			return {
				label: 'Returned',
				line: `${payee}’s bank sent ${amount} back to the payment partner. Kinfold follows it up before it is sent again; you don’t need to do anything.`,
				tone: 'action'
			};
	}
}
