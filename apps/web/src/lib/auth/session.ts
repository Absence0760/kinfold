import type { Session } from '@supabase/supabase-js';
import { supabase } from '#lib/supabase/client.ts';
import { classifyLoadError, LoadError } from './errors.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';

export type MemberRole = Database['public']['Enums']['member_role'];
export type MemberRow = Database['public']['Tables']['members']['Row'];

/** Who is signed in: their session, member row and roles. */
export interface Viewer {
	session: Session;
	member: MemberRow | null;
	roles: MemberRole[];
}

/**
 * The stored session, or null when signed out. Throws when refreshing an
 * expired token failed because the network did, so "offline" is never read as
 * "signed out"; any other auth error (a revoked refresh token) means signed out.
 */
export async function getSession(): Promise<Session | null> {
	const { data, error } = await supabase().auth.getSession();
	if (error && classifyLoadError(error) === 'network') throw error;
	return data.session;
}

/**
 * Load the signed-in member's row and roles, or null when signed out.
 *
 * A failed read throws a `LoadError` instead of looking like "no profile":
 * `member: null` means the read succeeded and there is no member row.
 */
export async function loadViewer(): Promise<Viewer | null> {
	const session = await getSession();
	if (!session) return null;
	const db = supabase();
	const uid = session.user.id;
	const [member, roles] = await Promise.all([
		db.from('members').select('*').eq('id', uid).maybeSingle(),
		db.from('member_roles').select('role').eq('member_id', uid)
	]);
	if (member.error) throw new LoadError('your member profile', member.error, member.status);
	if (roles.error) throw new LoadError('your member roles', roles.error, roles.status);
	return {
		session,
		member: member.data ?? null,
		roles: (roles.data ?? []).map((r) => r.role)
	};
}

export async function signIn(email: string, password: string): Promise<void> {
	const { error } = await supabase().auth.signInWithPassword({ email, password });
	if (error) throw error;
}

export async function signOut(): Promise<void> {
	await supabase().auth.signOut();
}

/**
 * Forget the session on this device only, without a network call. For a
 * session the server already rejected: the sign-in page would otherwise find
 * it in storage and send the member straight back.
 */
export async function clearLocalSession(): Promise<void> {
	await supabase().auth.signOut({ scope: 'local' });
}
