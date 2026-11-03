import type { RequestKind } from '#lib/dashboard/labels.ts';

/**
 * Pointers to state and city programmes beside a down payment (roadmap 3g:
 * "state housing finance agency and city programmes in the pilot city"). Kinfold
 * never runs HOME or CDBG paper and never holds a programme's lien: design.md,
 * "Public money stays in the funder's name" — FHLB, HOME, CDBG and state
 * housing-agency help reaches a household under that programme's own note and
 * lien, because programme rules follow the money forever (a HOME repayment
 * stays HOME money, 24 CFR 92.503), and a city's HOME agreement would usually
 * oblige whoever holds the lien to enforce it. So this page points; it
 * administers nothing.
 */

export interface ProgramHelpLine {
	/** What the line is about, shown bold. */
	title: string;
	/** What to do about it, in the member's own words. */
	body: string;
}

/**
 * The two local programmes design.md names as the Home Fund's first priorities
 * ("State housing finance agencies; HOME and CDBG funds through cities"): both
 * are local, competitive, and income-limited per programme, which is exactly why
 * the member, not Kinfold, reads the limits. A city may also be able to count
 * the Fund's own 0% loans as HOME match (24 CFR 92.220) — that ask belongs to
 * the city, so the page says so without asking for anything.
 */
const LINES: ProgramHelpLine[] = [
	{
		// design.md's table row: agencies offer down-payment help and foreclosure
		// prevention; the money arrives under the agency's own note and lien.
		title: 'The state housing finance agency',
		body:
			'A state housing finance agency exists to help households ask a bank for a down payment or for ' +
			'relief on a stalled loan, and whatever it offers reaches you under that agency’s own note and ' +
			'lien. Find the agency that covers your state by name and read its income limits before you ask; ' +
			'Kinfold never becomes the agency and never writes the paperwork behind its help.'
	},
	{
		// 24 CFR 92.503: HOME money keeps HOME rules, so Kinfold cannot hold that
		// lien and stay honest about which programme a repayment belongs to.
		title: 'A city’s HOME or CDBG funds',
		body:
			'A city’s HOME and CDBG funds give money toward a down payment outright, and each grant’s lien ' +
			'stays in that programme’s own name: the programme’s rules follow the money forever, so a HOME ' +
			'repayment stays HOME money (24 CFR 92.503). Kinfold never administers HOME or CDBG paper, never ' +
			'runs a programme of its own, and never takes a city’s lien. A city may be able to count the ' +
			'Fund’s own 0% loans as HOME match (24 CFR 92.220) — that ask goes to the city, not to this page.'
	},
	{
		// Other money for the same gap is recorded on the request, which is what
		// keeps the ask smaller and the books honest (`request_recoveries`).
		title: 'Programme money never joins this request',
		body:
			'Money a state agency or a city already gave for the same gap is recorded with the request, so what ' +
			'you still ask for is only the part that is left. Programme money never joins the Fund’s money and ' +
			'never appears in its books — the funder keeps its own name, and so do you.'
	}
];

/**
 * Down payments get the programme pointers; mortgage gaps already carry their own
 * public-help panel, and car and home-repair kinds are outside the Home Fund's
 * programmes entirely.
 */
export function programHelpLines(kind: RequestKind): ProgramHelpLine[] {
	return kind === 'down_payment' ? LINES : [];
}

/** What this panel is about, so the page can label it once. */
export const programHelpHeading = 'State and city help beside a down payment';