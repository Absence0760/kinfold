import type { RequestKind } from '#lib/dashboard/labels.ts';

/**
 * Pointers to a fair lender for the mortgage itself (roadmap 3e: "mortgage
 * matching with fair lenders, with **no referral fees**"). Kinfold does not
 * originate a first mortgage, and it does not price an introduction to one
 * either: RESPA section 8 bans referral fees from mortgage lenders, and a
 * disclosure does not cure the ban, so this page points and never charges.
 * A fee that follows a member to a lender is also money the member pays
 * without a repair behind it, which is what every other fee here exists to
 * fund (design.md, "Revenue").
 */

export interface FairLenderLine {
	/** What the line is about, shown bold. */
	title: string;
	/** What to do about it, in the member's own words. */
	body: string;
}

/**
 * Who a mortgage lender of record may be under the programmes lenders already
 * accept (design.md, "Mortgages"): Freddie Mac Affordable Seconds takes a credit
 * union that isn't also making the first mortgage, a nonprofit, or an
 * already-certified CDFI. Kinfold names those doors and stops there, because
 * choosing between them is the lender's and the member's, not ours.
 */
const LINES: FairLenderLine[] = [
	{
		title: 'Ask a fair lender for the mortgage itself',
		body:
			'The programmes mortgage lenders already accept put a credit union, a nonprofit, or an ' +
			'already-certified community development fund in as the lender of record: find the nearest ' +
			'one by name and ask it in its own branch, in its own words. Kinfold never becomes anyone’s ' +
			'lender of record and never writes a mortgage for you.'
	},
	{
		title: 'Nothing here costs you a fee for the introduction',
		body:
			'Kinfold takes no referral fees and no thank-you charges from mortgage lenders: those fees are ' +
			'banned outright, and saying what you were paid does not undo the ban. This page points you at ' +
			'a fair lender; it prices nothing, and no part of your mortgage money can be spent on getting ' +
			'you there.'
	},
	{
		title: 'The lender sees the smaller ask',
		body:
			'Family money you gave and help the Fund already offered are counted before you ask, so what you ' +
			'discuss with a lender is what is left of the mortgage — the part nobody else has promised to ' +
			'carry.'
	}
];

/** Mortgage kinds get the pointers; car and home-repair kinds get nothing at all. */
export function fairLenderLines(kind: RequestKind): FairLenderLine[] {
	return kind === 'mortgage_gap' || kind === 'down_payment' ? LINES : [];
}

/** What this panel is about, so the page can label it once. */
export const fairLenderHeading = 'A fair lender for the mortgage';
