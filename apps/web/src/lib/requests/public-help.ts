import type { CertifiedCounsel } from '#lib/transparency/data.ts';
import { formatDay } from '#lib/dashboard/format.ts';

/**
 * The one line about housing counselors that a mortgage-gap page offers a member
 * (roadmap 3c's referral). The agency named comes from the published `housing_counsel`
 * table - the Fund's one certified agency, certified under 24 CFR part 214 - so the
 * page can name a real agency with its credential instead of pointing at counselors
 * in general. design.md's ladder: Kinfold connects a household to a counselor and
 * never becomes one, and never asks one on a member's behalf - the bank decides.
 * With no certified agency in effect the honest answer says so and hands the member
 * the public list, because naming an uncertified agency would be a claim the schema
 * cannot support.
 */

/** The heading the panel shows, shared so tests can pin what the page offers. */
export const publicHelpHeading = 'Public help alongside this gap';

/**
 * The counselor line for the panel. `counsel === null` covers both "no agency is
 * certified yet" and "the published agency could not be read": in either state the
 * page points at the public list rather than naming anyone.
 */
export function publicHelpCounselLine(counsel: CertifiedCounsel | null): string {
	// Shared first: what a housing counselor is, true in both states.
	const what =
		'Nonprofit agencies certified by the government that help households ask a bank for ' +
		'forbearance (a pause the bank agrees to) or a loan modification (easier terms).';
	if (counsel === null) {
		// No agency is claimed: the member finds one that certified itself.
		return `${what} Find the one nearest you on hud.gov — Kinfold never becomes a counselor itself; you go to theirs.`;
	}
	return (
		`${what} ${counsel.agencyName} is the agency the Fund partners with, certified under ${counsel.certifiedUnder} ` +
		`and HUD-approved on ${formatDay(counsel.hudApprovedOn)}: you go to them, never through Kinfold, and the bank ` +
		'decides — Kinfold never becomes a counselor and never asks one on your behalf.'
	);
}
