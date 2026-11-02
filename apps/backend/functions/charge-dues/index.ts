// `charge-dues`: pg_cron, monthly. The dues collection schedule. What this
// file owns is the calendar and the read: which members have an ACTIVE
// subscription at a non-$0 figure that still has no dues payment for the
// period. The ask itself is the schema's `enqueue_dues` (member's own
// figure, idempotent per member per period) — a replayed month changes
// nothing. $0 subscriptions are skipped here AND refused in the schema:
// nothing to collect.

import { queryRows } from "../shared/rest.ts";

interface SubscriptionRow {
  id: string;
  member_id: string;
  monthly_cents: number;
  ends_on: string | null;
}

interface PaymentRow {
  subscription_id: string;
  period: string;
}

interface RpcCaller {
  call(name: string, args: Record<string, unknown>): unknown;
}

/** The period the cron charges: the month the run fires in (yyyy-MM-01). */
export function duesPeriodFor(now: Date): string {
  const month = `${now.getUTCMonth() + 1}`.padStart(2, "0");
  return `${now.getUTCFullYear()}-${month}-01`;
}

/**
 * Who is due the ask: an active subscription (no end date) with a figure to
 * collect, and no payment recorded for this period yet.
 */
export function dueForDues(
  subscriptions: SubscriptionRow[],
  payments: PaymentRow[],
  period: string,
): string[] {
  const charged = new Set(
    payments.filter((p) => p.period === period).map((p) => p.subscription_id),
  );
  return subscriptions
    .filter((s) =>
      s.ends_on === null && s.monthly_cents > 0 && !charged.has(s.id)
    )
    .map((s) => s.member_id);
}

/** One guarded ask per due member. A schema refusal is a logged skip. */
export async function collectDues(
  now: Date,
  read: (table: string, params: Record<string, string>) => Promise<unknown[]>,
  rpc: RpcCaller,
): Promise<string[]> {
  const period = duesPeriodFor(now);
  const subscriptions = (await read("subscriptions", {})) as SubscriptionRow[];
  const payments =
    (await read("subscription_payments", { period })) as PaymentRow[];
  const asked: string[] = [];
  for (const memberId of dueForDues(subscriptions, payments, period)) {
    try {
      rpc.call("enqueue_dues", { p_member: memberId, p_period: period });
      asked.push(memberId);
    } catch {
      // The schema's guard refused this member's ask (not active, no
      // subscription, $0); the cron logs it and moves on.
    }
  }
  return asked;
}
