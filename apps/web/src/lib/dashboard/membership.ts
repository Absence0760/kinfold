import type { AllocationTarget } from '#lib/dashboard/labels.ts';

export interface SubscriptionRow {
	id: string;
	monthly_cents: number;
	ends_on: string | null;
}

export interface PaymentRow {
	period: string;
	amount_cents: number;
	/** 'pending' | 'captured' | 'failed' | 'refunded' */
	status: string;
}

export interface IncomeRow {
	method: string;
	monthly_income_cents: number;
	verified_at: string;
	expires_at: string;
}

export interface ClaimRow {
	gross_cents: number;
	paid_cents: number;
	status: string;
}

export interface AssetRow {
	kind: string;
}

export interface PreferenceRow {
	target: AllocationTarget;
	weight_pct: number;
}

/**
 * What dues are doing this month: the member's own figure, and how far the
 * partner's charge for the current period has come. `no dues to collect` is a
 * $0 subscription (the schema refuses an ask for it); `not started` is no ask
 * yet — the monthly cron hasn't created one, which is not a failure.
 */
export interface DuesState {
	monthlyCents: number;
	/** The period shown: the month `today` sits in (yyyy-MM-01). */
	period: string;
	status: string;
}

/** The earnings check the dues were priced from, and whether it is still live. */
export interface IncomeState {
	method: string | null;
	monthlyIncomeCents: number;
	verifiedAt: string | null;
	expiresAt: string | null;
	live: boolean;
}

export interface CoverState {
	/** Cover is per vehicle (one premium per covered vehicle). */
	vehicles: number;
	/** The filed premiums the cooperative pays for the member's classed vehicles. */
	premiumCents: number;
	claimsPaidCents: number;
	openClaims: number;
}

export interface PlanState {
	target: AllocationTarget;
	weightPct: number;
}

/** The member's own account state: identity check done or not, and when they joined. */
export interface IdentityState {
	status: string | null;
	joinedAt: string | null;
}

export interface MembershipSummary {
	dues: DuesState;
	income: IncomeState;
	cover: CoverState;
	plan: PlanState[];
	identity: IdentityState;
}

function duesPeriodOf(today: string): string {
	return `${today.slice(0, 7)}-01`;
}

export function summarizeMembership(
	subscriptions: SubscriptionRow[],
	payments: PaymentRow[],
	income: IncomeRow[],
	claims: ClaimRow[],
	assets: AssetRow[],
	premiumCents: number,
	preferences: PreferenceRow[],
	memberStatus: string | null,
	memberJoinedAt: string | null,
	today: string
): MembershipSummary {
	// One active subscription at a time is enforced by the schema's index; if a
	// member has none, dues are simply not started.
	const active = subscriptions.find((s) => s.ends_on === null) ?? null;
	const period = duesPeriodOf(today);
	let dues: DuesState = { monthlyCents: 0, period, status: 'no dues yet' };
	if (active) {
		dues = {
			monthlyCents: active.monthly_cents,
			period,
			status: active.monthly_cents === 0 ? 'no dues to collect' : 'not started'
		};
		if (active.monthly_cents > 0) {
			const thisMonth = payments.find((p) => p.period === period);
			if (thisMonth) dues.status = thisMonth.status;
		}
	}

	// The newest earnings check; live while its expiry hasn't passed. The stored
		// timestamps are ISO, so comparing them with `today` compares dates.
	const newest = income.reduce<IncomeRow | null>(
		(best, row) => (best === null || row.verified_at > best.verified_at ? row : best),
		null
	);
	const incomeState: IncomeState = newest === null
		? { method: null, monthlyIncomeCents: 0, verifiedAt: null, expiresAt: null, live: false }
		: {
			method: newest.method,
			monthlyIncomeCents: newest.monthly_income_cents,
			verifiedAt: newest.verified_at,
			expiresAt: newest.expires_at,
			live: newest.expires_at > today
		};

	return {
		dues,
		income: incomeState,
		cover: {
			vehicles: assets.length,
			premiumCents,
			claimsPaidCents: claims.reduce((sum, c) => (c.status === 'paid' ? sum + c.paid_cents : sum), 0),
			openClaims: claims.filter((c) => c.status === 'recorded').length
		},
		identity: { status: memberStatus, joinedAt: memberJoinedAt },
		plan: preferences
			.filter((p) => p.weight_pct > 0)
			.sort((a, b) => b.weight_pct - a.weight_pct)
			.map((p) => ({ target: p.target, weightPct: p.weight_pct }))
	};
}

/** How a dues status reads on the member's own screen. */
export const duesWord = (status: string): string =>
	({
		captured: 'Collected by the payment partner',
		pending: 'Asked of the partner, not collected yet',
		failed: 'The partner\u2019s charge failed; it can be asked again',
		refunded: 'Refunded — nothing was taken',
		'not started': 'Not asked yet — the monthly cron is due',
		'no dues to collect': 'Nothing to collect — this dues plan is $0',
		'no dues yet': 'No dues set up yet'
	})[status] ?? status;

/** How the member’s own identity check reads on their screen. */
export const identityWord = (status: string | null): string =>
	({
		pending_verification: 'Not done yet — the check has to pass before you can post',
		active: 'Done',
		suspended: 'Suspended',
		closed: 'Closed'
	})[status ?? ''] ?? (status ?? 'no account row yet');

/** How the earnings check reads, in the words design.md uses. */
export const incomeMethodWord = (method: string): string =>
	({
		bank_link: 'read at your bank (through the bank-link vendor)',
		tax_return: 'from your tax return',
		self_attested: 'you stated it (random audits watch this path)'
	})[method] ?? method;
