import type { Session } from '@supabase/supabase-js';
import { supabase } from '#lib/supabase/client.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';

export type MemberRole = Database['public']['Enums']['member_role'];
export type MemberRow = Database['public']['Tables']['members']['Row'];

/** Who is signed in: their session, member row and roles. */
export interface Viewer {
	session: Session;
	member: MemberRow | null;
	roles: MemberRole[];
}

export async function getSession(): Promise<Session | null> {
	const { data } = await supabase().auth.getSession();
	return data.session;
}

/** Load the signed-in member's row and roles, or null when signed out. */
export async function loadViewer(): Promise<Viewer | null> {
	const session = await getSession();
	if (!session) return null;
	const db = supabase();
	const uid = session.user.id;
	const [member, roles] = await Promise.all([
		db.from('members').select('*').eq('id', uid).maybeSingle(),
		db.from('member_roles').select('role').eq('member_id', uid)
	]);
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
