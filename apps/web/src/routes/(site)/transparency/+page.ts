import { isConfigured, supabase } from '#lib/supabase/client.ts';
import { loadCertifiedCounsel, loadGrantReport, loadNeedsFormulas, loadOpenBooks, loadShareRules, quarterlySummaries } from '#lib/transparency/data.ts';
import { classifyLoadError } from '#lib/auth/errors.ts';

const MESSAGE: Record<string, string> = {
	session: 'Open books need the local stack to be reachable.',
	network: 'The open books could not be reached: no connection.',
	server: 'The open books could not be read: the server said no.'
};

/**
 * The published open books, the published needs weights, the published share rules and the
 * Fund’s certified housing counselor. All of it is public (anon readable), so this needs no session;
 * each read explains its own
 * failure kind rather than showing blank money or blank weights as zero.
 */
export async function load() {
	if (!isConfigured()) {
		const problem = 'The published books need the database to be configured.';
		return { books: [], quarters: [], problem, formulas: [], formulaProblem: problem, shareRules: [], shareProblem: problem, grants: [], grantProblem: problem, counsel: null, counselProblem: problem };
	}
	// The weights are a separate read: if the table refuses, the published
	// months still show, and the section explains itself.
	const [booksResult, formulasResult, shareResult, grantsResult, counselResult] = await Promise.all([
		loadOpenBooks(supabase()).then(
			(books) => ({ books, quarters: quarterlySummaries(books), problem: null }),
			(e) => ({ books: [], quarters: [], problem: MESSAGE[classifyLoadError(e)] })
		),
		loadNeedsFormulas(supabase()).then(
			(formulas) => ({ formulas, formulaProblem: null }),
			(e) => ({ formulas: [], formulaProblem: MESSAGE[classifyLoadError(e)] })
		),
		loadShareRules(supabase()).then(
			(shareRules) => ({ shareRules, shareProblem: null }),
			(e) => ({ shareRules: [], shareProblem: MESSAGE[classifyLoadError(e)] })
		),
		loadGrantReport(supabase()).then(
			(grants) => ({ grants, grantProblem: null }),
			(e) => ({ grants: [], grantProblem: MESSAGE[classifyLoadError(e)] })
		),
		loadCertifiedCounsel(supabase()).then(
			(counsel) => ({ counsel, counselProblem: null }),
			(e) => ({ counsel: null, counselProblem: MESSAGE[classifyLoadError(e)] })
		)
	]);
	return { ...booksResult, ...formulasResult, ...shareResult, ...grantsResult, ...counselResult };
}
