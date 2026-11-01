// Plain-language definitions of the words a new member meets on the board,
// loans, invites and review pages, each shown where the word first appears.
// One place, so the board, the invite panel and the loan agreement never
// explain the same word two different ways. Every line restates docs/design.md
// (sections cited); none of them sets policy. Change the design doc first.

export type Term = 'pool' | 'repairFund' | 'homeFund' | 'payee' | 'redacted' | 'poolRun';

export const TERMS: Record<Term, { word: string; means: string }> = {
	// design.md "4. Funded", Product 3, "Structure".
	pool: {
		word: 'the pool',
		means:
			'The community’s shared money for requests: the community repair fund for cars and the Community Home Fund for homes. A licensed partner holds it, never Kinfold, and it is kept apart from loans between family and friends.'
	},
	// design.md "4. Funded".
	repairFund: {
		word: 'the community repair fund',
		means:
			'Gifts and grants, never dues, that pay capped repair grants. It pays by evidence-score band: the highest band first, every request in it at the same time.'
	},
	// design.md Product 3.
	homeFund: {
		word: 'the Community Home Fund',
		means:
			'A separate charity that lends for homes without interest, from gifts, matching funds and repayments. It will choose by a published needs formula, which isn’t live yet.'
	},
	// design.md "1. Request" and the domain rule "pay the payee, not the member".
	payee: {
		word: 'payee',
		means:
			'The business the money is paid to, such as the repair shop, contractor, lender or seller named on the request. Money never goes to the member.'
	},
	// design.md "2. Evidence".
	redacted: {
		word: 'redacted',
		means:
			'Faces, number plates, names, addresses and account numbers are blurred out automatically, and the member checks the result before it is shown. The original stays private.'
	},
	// design.md "What could go wrong" (a monthly fund can run dry) and Product 2.
	poolRun: {
		word: 'a run',
		means:
			'Each time the fund shares out the money it holds across the requests waiting. 20% is kept back as a reserve, and a lower band waits for the next run rather than being refused.'
	}
};

export const define = (term: Term): string => TERMS[term].means;
