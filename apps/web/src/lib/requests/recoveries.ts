import { rpcNew, type Db } from '#lib/supabase/client.ts';
import { formatCents } from '#lib/dashboard/format.ts';

export interface RecoveryRow {
	request_id: string;
	source: string;
	amount_cents: number;
	recovered_on: string;
	note: string | null;
	verified_at: string | null;
	recorded_at: string;
}

/** How a source of other money reads on the member's screen. */
export const recoveryLabel = (source: string): string =>
	({
		own_cover: 'your own deductible cover',
		insurance: 'another insurer\u2019s claim',
		fema: 'a federal disaster programme',
		sba: 'the Small Business Administration',
		state: 'a state programme',
		charity: 'a charity fund',
		other: 'something else'
	})[source] ?? source;

/** One line per record: what the money is, when it moved, and how sure it is. */
export function recoveryText(row: RecoveryRow): string {
	const when = row.recovered_on || row.recorded_at.slice(0, 10);
	const sure = row.verified_at ? 'the partner confirmed it' : 'not confirmed yet';
	const note = row.note ? ` · ${row.note}` : '';
	return `${formatCents(row.amount_cents)} as ${recoveryLabel(row.source)} on ${when} · ${sure}${note}`;
}

/** Everything recorded for the same damage. */
export const recoveryTotalCents = (rows: RecoveryRow[]): number =>
	rows.reduce((sum, row) => sum + row.amount_cents, 0);

/**
 * Record money that covered the same damage through another source. The
 * requester may record it and the schema re-checks the same thing; the pledge
 * caps and pool needs subtract what is recorded.
 */
export async function recordRecovery(db: Db, requestId: string, source: string, amountCents: number, recoveredOn: string, note: string | null): Promise<void> {
	const { error } = await rpcNew(db, 'record_recovery', {
		p_request: requestId,
		p_source: source,
		p_amount_cents: amountCents,
		p_on: recoveredOn,
		p_note: note
	});
	if (error) throw error;
}
