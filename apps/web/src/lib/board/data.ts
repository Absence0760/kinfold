import { fundForKind } from '#lib/requests/form.ts';
import type { Db } from '#lib/supabase/client.ts';
import { minScoreFor } from '#lib/requests/score-band.ts';
import { toItems, type BoardItem } from './board.ts';
import { explainInviteError } from '#lib/invites/errors.ts';
import { BoardLoadError } from './errors.ts';

/**
 * Read the board as the signed-in member, under RLS:
 *
 *   * `board_requests` (the view) for what every verified member may see;
 *   * the viewer's own request ids, from `requests` filtered to their own
 *     member id, so the page can say "Your request" without the view
 *     exposing anyone's identity;
 *   * the view's own `raised_cents` for each open request, so the whole board
 *     needs one read; `request_raised_cents` still answers a single card
 *     after a pledge, where the page needs the figure it moved to.
 *   * `fund_settings` (public to every member) for each fund's minimum score,
 *     so a band is worded against the fund's own bar. If it can't be read,
 *     only the band's status line is left out; the board still shows.
 *
 * One progress call per open request: fine at today's board size; a view
 * column would be the durable fix once the board grows.
 */
export async function loadBoard(db: Db, viewerId: string): Promise<BoardItem[]> {
	const [board, own, settings] = await Promise.all([
		db.from('board_requests').select('*'),
		db.from('requests').select('id').eq('member_id', viewerId),
		db.from('fund_settings').select('fund, min_score')
	]);
	// Keep the code: the page words the failure with `explainBoardError`, never the raw message.
	if (board.error) throw new BoardLoadError(board.error);
	if (own.error) throw new BoardLoadError(own.error);

	const rows = board.data ?? [];
	// The view carries each open request's progress now, so the whole board is one
	// read; the empty map stays as the fallback for rows that predate the column.
	return toItems(rows, new Set((own.data ?? []).map((r) => r.id)), new Map(), (kind) =>
		settings.error ? null : minScoreFor(settings.data, fundForKind(kind))
	);
}

/** Pledge a gift (never a loan: strangers on the board can't lend). */
export async function pledgeGift(db: Db, requestId: string, cents: number): Promise<void> {
	const { error } = await db.rpc('pledge', {
		p_request: requestId,
		p_amount_cents: cents,
		p_source: 'gift'
	});
	if (error) throw new Error(explainInviteError(error));
}

/** Re-read one open request's progress after a pledge. */
export async function loadRaised(db: Db, requestId: string): Promise<number | null> {
	const { data, error } = await db.rpc('request_raised_cents', { p_request: requestId });
	return error || data == null ? null : Number(data);
}
