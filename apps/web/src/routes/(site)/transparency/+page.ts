import { isConfigured, supabase } from '#lib/supabase/client.ts';
import { loadOpenBooks } from '#lib/transparency/data.ts';
import { classifyLoadError } from '#lib/auth/errors.ts';

const MESSAGE: Record<string, string> = {
	session: 'Open books need the local stack to be reachable.',
	network: 'The open books could not be reached: no connection.',
	server: 'The open books could not be read: the server said no.'
};

/**
 * The published open books. `open_books` is public (anon readable), so this
 * needs no session: if the read fails, the page explains the failure kind
 * rather than showing blank money as zero.
 */
export async function load() {
	if (!isConfigured()) {
		return { books: [], problem: 'The published books need the database to be configured.' };
	}
	try {
		return { books: await loadOpenBooks(supabase()), problem: null };
	} catch (e) {
		return { books: [], problem: MESSAGE[classifyLoadError(e)] };
	}
}
