import { isConfigured, supabase } from '#lib/supabase/client.ts';
import { loadGrantReport, loadNeedsFormulas, loadOpenBooks, quarterlySummaries } from '#lib/transparency/data.ts';
import { classifyLoadError } from '#lib/auth/errors.ts';

const MESSAGE: Record<string, string> = {
	session: 'Open books need the local stack to be reachable.',
	network: 'The open books could not be reached: no connection.',
	server: 'The open books could not be read: the server said no.'
};

/**
 * The published open books and the published needs weights. Both tables are
 * public (anon readable), so this needs no session; each read explains its own
 * failure kind rather than showing blank money or blank weights as zero.
 */
export async function load() {
	if (!isConfigured()) {
		const problem = 'The published books need the database to be configured.';
		return { books: [], quarters: [], problem, formulas: [], formulaProblem: problem, grants: [], grantProblem: problem };
	}
	// The weights are a separate read: if the table refuses, the published
	// months still show, and the section explains itself.
	const [booksResult, formulasResult, grantsResult] = await Promise.all([
		loadOpenBooks(supabase()).then(
			(books) => ({ books, quarters: quarterlySummaries(books), problem: null }),
			(e) => ({ books: [], quarters: [], problem: MESSAGE[classifyLoadError(e)] })
		),
		loadNeedsFormulas(supabase()).then(
			(formulas) => ({ formulas, formulaProblem: null }),
			(e) => ({ formulas: [], formulaProblem: MESSAGE[classifyLoadError(e)] })
		),
		loadGrantReport(supabase()).then(
			(grants) => ({ grants, grantProblem: null }),
			(e) => ({ grants: [], grantProblem: MESSAGE[classifyLoadError(e)] })
		)
	]);
	return { ...booksResult, ...formulasResult, ...grantsResult };
}
