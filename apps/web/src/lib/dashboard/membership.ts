import type { AllocationTarget } from '#lib/dashboard/labels.ts';

export interface SubscriptionRow {
  id: string;
  monthly_cents: number;
  formula_version: number;
  starts_on: string;
  ends_on: string | null;
}

export interface PaymentRow {
  period: string;
  amount_cents: number;
  status: string;
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
  /** 'no dues to collect' | 'not started' | 'pending' | 'captured' | 'failed' | 'refunded' */
  status: string;
}

export interface CoverState {
  /** Cover is per vehicle (one premium per covered vehicle). */
  vehicles: number;
  claimsPaidCents: number;
  openClaims: number;
}

export interface PlanState {
  target: AllocationTarget;
  weightPct: number;
}

export interface MembershipSummary {
  dues: DuesState;
  cover: CoverState;
  plan: PlanState[];
}

function duesPeriodOf(today: string): string {
  return `${today.slice(0, 7)}-01`;
}

export function summarizeMembership(
  subscriptions: SubscriptionRow[],
  payments: PaymentRow[],
  claims: ClaimRow[],
  assets: AssetRow[],
  preferences: PreferenceRow[],
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

  return {
    dues,
    cover: {
      vehicles: assets.length,
      claimsPaidCents: claims.reduce((sum, c) => (c.status === 'paid' ? sum + c.paid_cents : sum), 0),
      openClaims: claims.filter((c) => c.status === 'recorded').length
    },
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
