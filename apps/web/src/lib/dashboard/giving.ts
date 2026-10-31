import type { Database } from '../../../../backend/supabase/database.types.ts';
import type { ContributionRow } from './requests.ts';

type Functions = Database['public']['Functions'];
export type GivingRecordRow = Functions['my_giving_record']['Returns'][number];
export type ReliabilityRow = Functions['my_reliability']['Returns'][number];

export interface GivingLine {
	label: string;
	cents: number;
}

export interface GivingSummary {
	given: GivingLine[];
	givenCents: number;
	received: GivingLine[];
	receivedCents: number;
	/** The member's own gifts and loans pledged but not collected yet. */
	pledgedGiftCents: number;
	pledgedLoanCents: number;
	/** True when there's nothing to show on either side yet. */
	empty: boolean;
}

/**
 * The member's private giving record (`my_giving_record`) as two columns.
 * Deliberately no net figure, ratio or badge: the record shows what their
 * money did, and nothing reads it to rank or refuse a request (design.md,
 * "Tracking what people give and receive").
 */
export function givingSummary(
	record: GivingRecordRow | null,
	ownContributions: readonly Pick<ContributionRow, 'source' | 'amount_cents' | 'status'>[]
): GivingSummary {
	const r = record ?? {
		subscriptions_paid_cents: 0,
		gifts_given_cents: 0,
		lent_cents: 0,
		received_from_pool_cents: 0,
		received_from_people_cents: 0,
		requests_paid: 0
	};
	const given = [
		{ label: 'Monthly dues paid', cents: r.subscriptions_paid_cents },
		{ label: 'Gifts to other members', cents: r.gifts_given_cents },
		{ label: 'Lent at zero interest', cents: r.lent_cents }
	];
	const received = [
		{ label: 'From the community funds', cents: r.received_from_pool_cents },
		{ label: 'From family and friends', cents: r.received_from_people_cents }
	];
	const pledged = (source: 'gift' | 'loan') =>
		ownContributions
			.filter((c) => c.source === source && c.status === 'pledged')
			.reduce((a, c) => a + c.amount_cents, 0);
	const givenCents = given.reduce((a, l) => a + l.cents, 0);
	const receivedCents = received.reduce((a, l) => a + l.cents, 0);
	const pledgedGiftCents = pledged('gift');
	const pledgedLoanCents = pledged('loan');
	return {
		given,
		givenCents,
		received,
		receivedCents,
		pledgedGiftCents,
		pledgedLoanCents,
		empty: givenCents + receivedCents + pledgedGiftCents + pledgedLoanCents === 0
	};
}
