import { parseDollars } from '#lib/board/board.ts';
import { localToday } from '#lib/dashboard/format.ts';
import type { FundingMode, RequestKind } from '#lib/dashboard/labels.ts';
import type { Database } from '../../../../backend/supabase/database.types.ts';

type Enums = Database['public']['Enums'];
export type PayeeKind = Enums['payee_kind'];

/** The columns a member may write on a draft (the table's insert/update grants). */
export interface DraftValues {
	kind: RequestKind;
	funding: FundingMode;
	title: string;
	description: string;
	amount_cents: number;
	incident_on: string;
	payee_id: string | null;
	asset_id: string | null;
}

/** What the form holds: everything as typed, so nothing is lost on a bad value. */
export interface DraftInput {
	kind: string;
	funding: string;
	title: string;
	description: string;
	amount: string;
	incidentOn: string;
	payeeId: string;
	assetId: string;
}

export type DraftField = keyof DraftInput;
export type DraftProblems = Partial<Record<DraftField, string>>;

export const TITLE_MAX = 120;
export const DESCRIPTION_MAX = 5000;

export const REQUEST_KINDS: readonly { kind: RequestKind; label: string; hint: string }[] = [
	{ kind: 'car_damage', label: 'Car damage', hint: 'Your car was hit, scraped or damaged and needs a repair.' },
	{
		kind: 'car_deductible',
		label: 'Car insurance deductible',
		hint: 'Your insurer pays the repair, but you have to cover the deductible first.'
	},
	{ kind: 'home_repair', label: 'Home repair', hint: 'A leak, a broken furnace, storm damage: a repair to your home.' },
	{ kind: 'down_payment', label: 'Down payment', hint: 'Help toward the down payment on a home.' },
	{ kind: 'mortgage_gap', label: 'Mortgage gap', hint: 'You’re behind on your mortgage and need to catch up.' },
	{ kind: 'loan_payoff', label: 'Loan payoff', hint: 'Paying off an expensive loan, so you can repay at zero interest instead.' }
];

export const FUNDING_MODES: readonly FundingMode[] = ['people', 'pool', 'both'];

export const isCarKind = (kind: RequestKind): boolean => kind === 'car_damage' || kind === 'car_deductible';

/** Which fund a kind draws on (mirrors `public.fund_for_kind`). */
export const fundForKind = (kind: RequestKind): 'protection' | 'home_fund' =>
	isCarKind(kind) ? 'protection' : 'home_fund';

/** The kinds of payee that fit a request: shops for cars, contractors for repairs, lenders for homes. */
export function payeeKindsFor(kind: RequestKind): PayeeKind[] {
	if (isCarKind(kind)) return ['repair_shop'];
	if (kind === 'home_repair') return ['contractor'];
	return ['lender', 'seller', 'title_company'];
}

const payeeKindLabels: Record<PayeeKind, string> = {
	repair_shop: 'Repair shop',
	contractor: 'Contractor',
	lender: 'Lender',
	seller: 'Seller',
	title_company: 'Title company'
};

export const payeeKindLabel = (kind: PayeeKind): string => payeeKindLabels[kind];

/**
 * Characters as Postgres counts them (`length()` on UTF-8 text counts code
 * points), so an emoji counts once here just as it does in the check.
 */
export const charCount = (s: string): number => [...s].length;

/** A valid calendar date as `YYYY-MM-DD`, or false. */
export function isIsoDate(s: string): boolean {
	const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
	if (!m) return false;
	const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
	return d.toISOString().slice(0, 10) === s;
}

/**
 * The latest incident date the table accepts. Its check is
 * `incident_on <= created_at::date`, with the date taken in the database's
 * timezone (UTC): today for a new draft, the day it was started for an edit.
 * The member's own today caps it too, so a date can't be "tomorrow" for them.
 */
export function latestIncidentDate(now: Date, createdAt?: string): string {
	const utc = (createdAt ? new Date(createdAt) : now).toISOString().slice(0, 10);
	const local = localToday(now);
	return local < utc ? local : utc;
}

const KIND_SET = new Set<string>(REQUEST_KINDS.map((k) => k.kind));
const FUNDING_SET = new Set<string>(FUNDING_MODES);

/**
 * Check a draft against exactly what the `requests` table requires (title 1 to
 * 120 characters, description up to 5,000, amount above zero in whole cents,
 * incident date no later than the day the draft was started) and turn it into
 * the row to write. Payee and car are optional on a draft; submitting needs
 * them, and that is checked when the member submits.
 */
export function validateDraft(
	input: DraftInput,
	latestDate: string
): { ok: true; values: DraftValues } | { ok: false; problems: DraftProblems } {
	const problems: DraftProblems = {};

	if (!KIND_SET.has(input.kind)) problems.kind = 'Choose what the help is for.';
	if (!FUNDING_SET.has(input.funding)) problems.funding = 'Choose who you’re asking.';

	const title = input.title.trim();
	if (title === '') problems.title = 'Give your request a short title, like “Rear bumper after a crash”.';
	else if (charCount(title) > TITLE_MAX)
		problems.title = `Keep the title to ${TITLE_MAX} characters. It’s ${charCount(title)} now.`;

	const description = input.description.trim();
	if (charCount(description) > DESCRIPTION_MAX)
		problems.description = `Keep the description to ${DESCRIPTION_MAX.toLocaleString('en-US')} characters. It’s ${charCount(description).toLocaleString('en-US')} now.`;

	const cents = parseDollars(input.amount);
	if (input.amount.trim() === '') problems.amount = 'Enter how much you need, in dollars.';
	else if (cents == null) problems.amount = 'Enter the amount in dollars and cents, like 1200 or 1,250.50.';

	if (input.incidentOn === '') problems.incidentOn = 'Enter the date it happened (or the bill arrived).';
	else if (!isIsoDate(input.incidentOn)) problems.incidentOn = 'Enter a real date.';
	else if (input.incidentOn > latestDate) problems.incidentOn = 'The date can’t be later than the day you started this request.';

	if (Object.keys(problems).length > 0 || cents == null) return { ok: false, problems };

	const kind = input.kind as RequestKind;
	return {
		ok: true,
		values: {
			kind,
			funding: input.funding as FundingMode,
			title,
			description,
			amount_cents: cents,
			incident_on: input.incidentOn,
			payee_id: input.payeeId || null,
			// Only cars are covered assets on a request; switching kind drops it.
			asset_id: isCarKind(kind) ? input.assetId || null : null
		}
	};
}

/** A stored draft back into the form's typed values. */
export function draftToInput(row: DraftValues): DraftInput {
	return {
		kind: row.kind,
		funding: row.funding,
		title: row.title,
		description: row.description,
		amount: (row.amount_cents / 100).toFixed(row.amount_cents % 100 === 0 ? 0 : 2),
		incidentOn: row.incident_on,
		payeeId: row.payee_id ?? '',
		assetId: row.asset_id ?? ''
	};
}

export const PAYEE_NAME_MAX = 200;

/** A payee the member proposes: the columns `payees` lets them insert. */
export function validatePayee(input: {
	kind: string;
	legalName: string;
	region: string;
}): { ok: true; values: { kind: PayeeKind; legal_name: string; region: string } } | { ok: false; problems: Record<string, string> } {
	const problems: Record<string, string> = {};
	const kinds = new Set<string>(Object.keys(payeeKindLabels));
	if (!kinds.has(input.kind)) problems.kind = 'Choose what kind of business this is.';
	const name = input.legalName.trim();
	if (name === '') problems.legalName = 'Enter the business’s name as it appears on its estimate or bill.';
	else if (charCount(name) > PAYEE_NAME_MAX) problems.legalName = `Keep the name to ${PAYEE_NAME_MAX} characters.`;
	if (!/^[A-Z]{2}$/.test(input.region)) problems.region = 'Choose the state the business is in.';
	if (Object.keys(problems).length > 0) return { ok: false, problems };
	return { ok: true, values: { kind: input.kind as PayeeKind, legal_name: name, region: input.region } };
}

/** US states and DC, for the payee's state. */
export const US_STATES: readonly [code: string, name: string][] = [
	['AL', 'Alabama'], ['AK', 'Alaska'], ['AZ', 'Arizona'], ['AR', 'Arkansas'], ['CA', 'California'],
	['CO', 'Colorado'], ['CT', 'Connecticut'], ['DE', 'Delaware'], ['DC', 'District of Columbia'],
	['FL', 'Florida'], ['GA', 'Georgia'], ['HI', 'Hawaii'], ['ID', 'Idaho'], ['IL', 'Illinois'],
	['IN', 'Indiana'], ['IA', 'Iowa'], ['KS', 'Kansas'], ['KY', 'Kentucky'], ['LA', 'Louisiana'],
	['ME', 'Maine'], ['MD', 'Maryland'], ['MA', 'Massachusetts'], ['MI', 'Michigan'], ['MN', 'Minnesota'],
	['MS', 'Mississippi'], ['MO', 'Missouri'], ['MT', 'Montana'], ['NE', 'Nebraska'], ['NV', 'Nevada'],
	['NH', 'New Hampshire'], ['NJ', 'New Jersey'], ['NM', 'New Mexico'], ['NY', 'New York'],
	['NC', 'North Carolina'], ['ND', 'North Dakota'], ['OH', 'Ohio'], ['OK', 'Oklahoma'], ['OR', 'Oregon'],
	['PA', 'Pennsylvania'], ['RI', 'Rhode Island'], ['SC', 'South Carolina'], ['SD', 'South Dakota'],
	['TN', 'Tennessee'], ['TX', 'Texas'], ['UT', 'Utah'], ['VT', 'Vermont'], ['VA', 'Virginia'],
	['WA', 'Washington'], ['WV', 'West Virginia'], ['WI', 'Wisconsin'], ['WY', 'Wyoming']
];

export const APPEAL_MIN = 10;
export const APPEAL_MAX = 2000;

/** Why an appeal reason can't be sent (the `appeals` reason check), or null. */
export function appealReasonProblem(reason: string): string | null {
	const n = charCount(reason.trim());
	if (n < APPEAL_MIN) return `Write at least ${APPEAL_MIN} characters, so the panel knows what to look at again.`;
	if (n > APPEAL_MAX) return `Keep it to ${APPEAL_MAX.toLocaleString('en-US')} characters. It’s ${n.toLocaleString('en-US')} now.`;
	return null;
}
