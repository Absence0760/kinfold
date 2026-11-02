import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import type { Database } from '../../../../backend/supabase/database.types.ts';

export type Db = SupabaseClient<Database>;

/**
 * The one Supabase client for the member area.
 *
 * Created lazily, so importing `#lib/...` (including from prerendered marketing
 * pages) never demands a configured key, and the sign-in page can say "the key
 * is missing" instead of dying on import.
 */
let client: Db | null = null;

export function supabase(): Db {
	if (client) return client;
	client = createClient<Database>(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		auth: {
			persistSession: true,
			autoRefreshToken: true,
			// No OAuth redirects here; detection would rewrite the URL on every load.
			detectSessionInUrl: false
		}
	});
	return client;
}

/**
 * Calls an RPC the generated `database.types.ts` doesn't list yet. That file is
 * generated from a running stack (`gen:types`) and is never hand-edited, so
 * functions added by the newest migrations aren't in it; this one seam lets the
 * call compile until the types are regenerated. See docs/ledger.md.
 */
export async function rpcNew(db: Db, name: string, args: Record<string, unknown>) {
	const untyped = db as unknown as {
		rpc: (name: string, args: Record<string, unknown>) => { data?: unknown; error: { message: string; code?: string } | null };
	};
	return untyped.rpc(name, args);
}

/**
 * Reads a table or view the generated `database.types.ts` doesn't list yet.
 * Same seam as `rpcNew`: the committed types lag the newest schema until the
 * live stack regenerates them, so the rows come back untyped and the call
 * site pins the shape. See docs/ledger.md.
 */
export function fromNew(db: Db, table: string) {
	return (db as unknown as SupabaseClient).from(table);
}

/** False when the launcher didn't pass a publishable key through. */
export function isConfigured(): boolean {
	return PUBLIC_SUPABASE_ANON_KEY !== '';
}

export const supabaseUrl = PUBLIC_SUPABASE_URL;
