import { supabase } from '#lib/supabase/client.ts';
import { loadCover } from '#lib/cover/data.ts';

/**
 * The member's car cover, read as the signed-in member: RLS answers with their
 * own vehicles, their own plan row and the filed rates. The premium figure is
 * the cooperative's paid-in-full sum (never an earnings price); money lives in
 * the ledger, not here.
 */
export async function load({ parent, depends }) {
	depends('app:cover');
	const { viewer } = await parent();
	return { uid: viewer.session.user.id, cover: loadCover(supabase(), viewer.session.user.id) };
}
