import { fundForKind } from '#lib/requests/form.ts';
import { minScoreFor } from '#lib/requests/score-band.ts';
import { supabase } from '#lib/supabase/client.ts';
import { toItems, type BoardItem } from './board.ts';

/**
 * Read the board as the signed-in member, under RLS:
 *
 *   * `board_requests` (the view) for what every verified member may see;
 *   * the viewer's own request ids, from `requests` filtered to their own
 *     member id, so the page can say "Your request" without the view
 *     exposing anyone's identity;
 *   * `request_raised_cents` for open requests, which the backend shares with
 *     any active member while a request is still asking for money;
 *   * `fund_settings` (public to every member) for each fund's minimum score,
 *     so a band is worded against the fund's own bar. If it can't be read,
 *     only the band's status line is left out; the board still shows.
 *
 * One progress call per open request: fine at today's board size; a view
 * column would be the durable fix once the board grows.
 */
export async function loadBoard(viewerId: string): Promise<BoardItem[]> {
	const db = supabase();
	const [board, own, settings] = await Promise.all([
		db.from('board_requests').select('*'),
		db.from('requests').select('id').eq('member_id', viewerId),
		db.from('fund_settings').select('fund, min_score')
	]);
	if (board.error) throw new Error(board.error.message);
	if (own.error) throw new Error(own.error.message);

	const rows = board.data ?? [];
	const open = rows.filter((r) => r.status === 'open' && r.id).map((r) => r.id as string);
	const raisedPairs = await Promise.all(
		open.map(async (id) => {
			const { data, error } = await db.rpc('request_raised_cents', { p_request: id });
			// A missing figure shows as "progress not shown", not as $0 raised.
			return [id, error || data == null ? null : Number(data)] as const;
		})
	);
	const raised = new Map<string, number>();
	for (const [id, cents] of raisedPairs) if (cents != null) raised.set(id, cents);

	return toItems(rows, new Set((own.data ?? []).map((r) => r.id)), raised, (kind) =>
		settings.error ? null : minScoreFor(settings.data, fundForKind(kind))
	);
}

/** Pledge a gift (never a loan: strangers on the board can't lend). */
export async function pledgeGift(requestId: string, cents: number): Promise<void> {
	const { error } = await supabase().rpc('pledge', {
		p_request: requestId,
		p_amount_cents: cents,
		p_source: 'gift'
	});
	if (error) throw new Error(pledgeErrorText(error.message));
}

/** The backend's messages are already plain; this keeps one fallback. */
function pledgeErrorText(message: string): string {
	if (/pledge must be between/.test(message)) {
		return 'Someone pledged while you were deciding, so less is needed now. Refresh the board and try a smaller amount.';
	}
	return message ? `${message[0].toUpperCase()}${message.slice(1)}.` : 'The pledge did not go through.';
}

/** Re-read one open request's progress after a pledge. */
export async function loadRaised(requestId: string): Promise<number | null> {
	const { data, error } = await supabase().rpc('request_raised_cents', { p_request: requestId });
	return error || data == null ? null : Number(data);
}
