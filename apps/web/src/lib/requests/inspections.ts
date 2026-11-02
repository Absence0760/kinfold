import { rpcNew, type Db } from '#lib/supabase/client.ts';

export interface InspectionRow {
	id: string;
	request_id: string;
	result: string;
	inspected_at: string;
	inspector_ref: string;
	note: string | null;
}

/** What an inspection result means on the member's screen. */
export const inspectionWord = (result: string): string =>
	({
		clear: 'the visit found the damage as described',
		issue_found: 'the visit found a problem',
		inconclusive: 'the visit could not tell'
	})[result] ?? result;

/**
 * Whether this request is large enough that the partner sends someone to visit
 * the shop in person. The database owns the line and the rule; this only asks.
 */
export async function needsInspection(db: Db, requestId: string): Promise<boolean> {
	const { data, error } = await rpcNew(db, 'needs_inspection', { p_request: requestId });
	if (error) throw error;
	return data === true;
}
