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

/** False when the launcher didn't pass a publishable key through. */
export function isConfigured(): boolean {
	return PUBLIC_SUPABASE_ANON_KEY !== '';
}

export const supabaseUrl = PUBLIC_SUPABASE_URL;
