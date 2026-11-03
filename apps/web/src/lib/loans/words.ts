import type { CertifiedCounsel } from '#lib/transparency/data.ts';
import { agencyLine, counselorAsks } from '#lib/requests/public-help.ts';

/** 1 → "1st", 2 → "2nd", 11 → "11th", 22 → "22nd". */
export function ordinal(n: number): string {
	const tens = n % 100;
	if (tens >= 11 && tens <= 13) return `${n}th`;
	return `${n}${{ 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] ?? 'th'}`;
}

export const monthsWord = (n: number): string => `${n} month${n === 1 ? '' : 's'}`;


/**
 * The "get the bank's own relief" step beside a loan (design.md's ladder:
 * Kinfold connects the member to a HUD-approved housing counselor to ask for
 * forbearance or a modification, and never becomes one). The agency named is
 * the one the Fund has certified (24 CFR part 214); with no certified agency in
 * effect the honest answer says so, and the 120-day note still belongs on the
 * page because acting early is the member's own step.
 */
export function bankReliefNote(counsel: CertifiedCounsel | null): string {
	if (counsel === null) {
		return (
		"No certified agency is in effect yet: Kinfold names one only with its certification on paper, so this loan " +
		"carries no counselor yet. A servicer generally cannot start foreclosure until a borrower is more than 120 days " +
		"behind, so acting early still matters."
		);
	}
	return (
		`${agencyLine(counsel)}: go to them to ask your bank for ${counselorAsks}.` +
		"Kinfold never becomes a counselor and never asks one on your behalf — the bank decides. A servicer generally " +
		"cannot start foreclosure until a borrower is more than 120 days behind, so acting early matters."
	);
}
